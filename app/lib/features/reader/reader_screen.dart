// The PDF reader: pdfrx viewer + our tooltip layer.
//
// Tap a word → WordTooltip (local entry now, /context pinned when it lands).
// Long-press/drag (pdfrx's own selection) → SentenceTooltip (streamed
// translation). The tooltip hangs off a LayerLink target that we place in the
// viewer overlay at the anchor's current on-screen rect, so it tracks scroll
// and zoom; the follower lives in an OverlayPortal above everything.

import 'dart:async';

import 'package:arth/app/dev_hooks.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/normalize.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/reader/details_sheet.dart';
import 'package:arth/features/reader/page_text_cache.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:arth/features/reader/tooltip/sentence_tooltip.dart';
import 'package:arth/features/reader/tooltip/tooltip_card.dart';
import 'package:arth/features/reader/tooltip/tooltip_placement.dart';
import 'package:arth/features/reader/tooltip/word_tooltip.dart';
import 'package:arth/features/settings/reading_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

const _pronouns = {
  'he', 'she', 'it', 'they', 'them', 'his', 'her', 'hers', 'its', 'their', //
  'theirs', 'him', 'this', 'that', 'these', 'those', 'i', 'we', 'you', 'who',
};

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.book, required this.filePath, super.key});

  final Book book;

  /// Absolute path, resolved against the documents directory at open time.
  final String filePath;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controller = PdfViewerController();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final GlobalKey _viewerKey = GlobalKey();
  PageTextCache? _cache;
  Timer? _selectionDebounce;
  bool _selectionHaptic = false;
  bool _warnedNoText = false;
  int? _page;

  /// Prefetch (Section 7): sentences already sent for /context this session.
  final Set<String> _prefetched = {};
  static const _prefetchRankThreshold = 8000;
  static const _prefetchMaxPerPage = 12;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewerChanged);
    _registerDevHooks();
  }

  @override
  void dispose() {
    _controller.removeListener(_onViewerChanged);
    _selectionDebounce?.cancel();
    DevHooks.off('tapWord');
    DevHooks.off('select');
    DevHooks.off('dismiss');
    DevHooks.off('state');
    super.dispose();
  }

  void _registerDevHooks() {
    DevHooks.on('tapWord', (p) async {
      final cache = _cache!;
      final page = int.tryParse(p['page'] ?? '') ?? (_page ?? 1);
      final idx = await cache.page(page);
      final key = normalizeWord(p['word'] ?? '');
      final nth = int.tryParse(p['nth'] ?? '') ?? 0;
      final matches = idx.words.where((w) => w.key == key).toList();
      if (matches.length <= nth) return {'ok': false, 'reason': 'word not on page'};
      await _openWord(cache, page, idx, matches[nth]);
      return {'ok': true, 'rect': matches[nth].rect.toString()};
    });
    DevHooks.on('select', (p) async {
      final cache = _cache!;
      final page = int.tryParse(p['page'] ?? '') ?? (_page ?? 1);
      final idx = await cache.page(page);
      final from = idx.words.indexWhere((w) => w.key == normalizeWord(p['from'] ?? ''));
      final to = idx.words.indexWhere((w) => w.key == normalizeWord(p['to'] ?? ''), from);
      if (from < 0 || to < 0) return {'ok': false, 'reason': 'words not on page'};
      final span = SentenceSpan(firstWord: from, lastWord: to);
      final text = normalizeSentence(idx.rawSentence(span));
      _portal.show();
      ref.read(readerControllerProvider.notifier).showSentence(
            text: text,
            anchor: idx.rectOf(span),
            page: page,
          );
      return {'ok': true, 'text': text};
    });
    DevHooks.on('dismiss', (_) async {
      ref.read(readerControllerProvider.notifier).dismiss();
      return {'ok': true};
    });
    DevHooks.on('state', (_) async {
      final s = ref.read(readerControllerProvider);
      return {
        'tooltip': s?.runtimeType.toString(),
        'page': _page,
        'ready': _cache != null,
        if (s is WordTooltipState)
          'word': {
            'key': s.key,
            'outcome': s.outcome?.runtimeType.toString(),
            'lemma': s.outcome is LookupFound ? (s.outcome! as LookupFound).lemma : null,
            'contextLoading': s.contextLoading,
            'context': s.context?.toJson(),
            'contextError': s.contextError,
          },
        if (s is SentenceTooltipState)
          'sentence': {'text': s.text, 'hindi': s.hindi, 'error': s.error, 'done': s.done},
      };
    });
  }

  void _onViewerChanged() {
    // The overlay target moves with the document; rebuild so the follower's
    // above/below decision and clamp track it.
    if (mounted && ref.read(readerControllerProvider) != null) setState(() {});
  }

  // ---- geometry ----

  Rect _docToViewer(Rect doc) => MatrixUtils.transformRect(_controller.value, doc);

  Offset get _viewerOrigin {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.localToGlobal(Offset.zero) ?? Offset.zero;
  }

  // ---- taps ----

  bool _onTap(BuildContext context, PdfViewerController controller, PdfViewerGeneralTapHandlerDetails d) {
    if (d.type != PdfViewerGeneralTapType.tap) return false;
    final cache = _cache;
    if (cache == null) return false;
    unawaited(_handleTap(cache, d.documentPosition));
    return true;
  }

  Future<void> _handleTap(PageTextCache cache, Offset docPos) async {
    final page = cache.pageAt(docPos);
    final rc = ref.read(readerControllerProvider.notifier);
    if (page == null) {
      rc.dismiss();
      return;
    }
    final idx = await cache.page(page);
    if (idx.words.isEmpty && mounted && !_warnedNoText) {
      _warnedNoText = true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).noTextLayer)));
    }
    final word = idx.wordAt(docPos, margin: 3);
    if (word == null || word.key.isEmpty) {
      rc.dismiss();
      return;
    }
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
    await _openWord(cache, page, idx, word);
  }

  Future<void> _openWord(PageTextCache cache, int page, PageTextIndex idx, PageWord word) async {
    final rc = ref.read(readerControllerProvider.notifier);
    final sentence = await cache.sentenceFor(page, idx, word);
    final around = idx.tokensAround(word.index);
    final offset = word.index - around.index;
    _portal.show();
    await rc.showWord(
      word: word,
      page: page,
      sentence: sentence,
      tokens: around.tokens,
      index: around.index,
      rectsForWindow: (start, count) => [
        for (var i = start; i < start + count; i++)
          if (i + offset >= 0 && i + offset < idx.words.length) idx.words[i + offset].rect,
      ],
    );
  }

  // ---- selection ----

  void _onSelectionChanged(PdfTextSelection sel) {
    final rc = ref.read(readerControllerProvider.notifier);
    if (!sel.hasSelectedText) {
      _selectionHaptic = false;
      if (ref.read(readerControllerProvider) is SentenceTooltipState) rc.dismiss();
      return;
    }
    if (!_selectionHaptic) {
      _selectionHaptic = true;
      unawaited(HapticFeedback.selectionClick());
    }
    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(const Duration(milliseconds: 350), () => _handleSelection(sel));
  }

  Future<void> _handleSelection(PdfTextSelection sel) async {
    final cache = _cache;
    if (cache == null || !mounted) return;
    final ranges = await sel.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final raw = await sel.getSelectedText();
    final text = normalizeSentence(raw);
    if (text.isEmpty) return;

    Rect? anchor;
    for (final r in ranges) {
      final rect = _controller.calcRectForRectInsidePage(pageNumber: r.pageNumber, rect: r.bounds);
      anchor = anchor == null ? rect : anchor.expandToInclude(rect);
    }
    final page = ranges.first.pageNumber;
    final idx = await cache.page(page);

    // A single selected word gets the word tooltip, with its sentence.
    if (!text.contains(' ')) {
      final word = idx.wordAtChar(ranges.first.start);
      if (word != null) {
        await _openWord(cache, page, idx, word);
        return;
      }
    }

    String? previous;
    final first = normalizeWord(text.split(' ').first);
    if (_pronouns.contains(first)) {
      final w = idx.wordAtChar(ranges.first.start);
      if (w != null) previous = await cache.previousSentence(page, idx, w);
    }
    _portal.show();
    ref.read(readerControllerProvider.notifier).showSentence(
          text: text,
          anchor: anchor!,
          page: page,
          context: previous,
        );
  }

  // ---- prefetch ----

  /// Quietly resolve /context for rare or unknown words on this page and the
  /// next, so the tooltip's "इस वाक्य में" is a cache hit when tapped.
  /// Fire-and-forget: no retries, never blocks rendering, errors ignored.
  Future<void> _prefetch(int page) async {
    if (!ref.read(settingsProvider).prefetch) return;
    final cache = _cache;
    if (cache == null) return;
    final store = ref.read(localStoreProvider);
    final repo = ref.read(dictionaryRepoProvider);
    for (final p in [page, page + 1]) {
      if (p < 1 || p > _controller.pageCount) continue;
      final PageTextIndex idx;
      try {
        idx = await cache.page(p);
      } on Exception {
        continue;
      }
      var sent = 0;
      final sentenceStarts = {for (final s in idx.sentences) s.firstWord};
      for (final w in idx.words) {
        if (sent >= _prefetchMaxPerPage || !mounted) break;
        final key = w.key;
        if (key.length < 3) continue;
        // Capitalised mid-sentence → almost certainly a name; not worth a call.
        if (_looksLikeName(w.text) && !sentenceStarts.contains(w.index)) continue;
        final rank = await store.rankOf(key);
        if (rank != null && rank <= _prefetchRankThreshold) continue;
        final sentence = await cache.sentenceFor(p, idx, w);
        final id = '$key|$sentence';
        if (!_prefetched.add(id)) continue;
        sent++;
        unawaited(
          repo.contextFor(word: key, sentence: sentence).then((_) {}, onError: (Object _) {}),
        );
      }
    }
  }

  static final RegExp _leadingPunct = RegExp('^[^a-zA-Z]+');

  static bool _looksLikeName(String token) {
    final t = token.replaceFirst(_leadingPunct, '');
    if (t.isEmpty) return false;
    final c = t[0];
    return c.toUpperCase() == c && c.toLowerCase() != c;
  }

  // ---- helpers ----

  Future<void> _lookupTyped(String word) async {
    // From a suggestion chip or a difficult-word chip: same tooltip, same anchor.
    final s = ref.read(readerControllerProvider);
    if (s == null) return;
    final cache = _cache;
    if (cache == null) return;
    final idx = await cache.page(s.page);
    final key = normalizeWord(word);
    final match = idx.words.where((w) => w.key == key).firstOrNull;
    final rc = ref.read(readerControllerProvider.notifier);
    if (match != null) {
      await _openWord(cache, s.page, idx, match);
    } else {
      final sentence = s is WordTooltipState ? s.sentence : (s as SentenceTooltipState).text;
      await rc.showWord(
        word: PageWord(index: 0, start: 0, end: 0, text: word, rect: s.anchor),
        page: s.page,
        sentence: sentence,
        tokens: [key],
        index: 0,
        rectsForWindow: (_, _) => [s.anchor],
      );
    }
  }

  void _showDetails(WordTooltipState s) {
    final outcome = s.outcome;
    if (outcome is! LookupFound) return;
    unawaited(
      showEntryDetailsSheet(
        context,
        entry: outcome.entry,
        contextResult: s.context,
        contextLoading: s.contextLoading,
        sentence: s.sentence,
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        onTapWord: _lookupTyped,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final tooltip = ref.watch(readerControllerProvider);
    if (tooltip == null && _portal.isShowing) _portal.hide();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_page != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '$_page / ${_controller.isReady ? _controller.pageCount : '…'}',
                  style: EnglishText.label(c.inkMuted),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: t.readingSettings,
            onPressed: () => showReadingSettingsSheet(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewer.file(
            widget.filePath,
            key: _viewerKey,
            controller: _controller,
            initialPageNumber: widget.book.lastPage,
            params: PdfViewerParams(
              backgroundColor: c.paper,
              textSelectionParams: PdfTextSelectionParams(
                showContextMenuAutomatically: false,
                onTextSelectionChange: _onSelectionChanged,
              ),
              // Our tooltip replaces the OS copy/paste menu entirely.
              buildContextMenu: (_, _) => null,
              errorBannerBuilder: (ctx, error, stack, ref) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    t.pdfOpenFailed,
                    style: uiBody(hindi: t.isHindi, color: c.inkMuted),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              onGeneralTap: _onTap,
              onViewerReady: (doc, controller) {
                _cache = PageTextCache(controller);
                unawaited(
                  ref.read(libraryProvider.notifier).touch(widget.book.id, pageCount: doc.pages.length),
                );
                setState(() => _page = controller.pageNumber);
                unawaited(_prefetch(controller.pageNumber ?? 1));
              },
              onPageChanged: (p) {
                if (p == null) return;
                setState(() => _page = p);
                unawaited(ref.read(libraryProvider.notifier).touch(widget.book.id, lastPage: p));
                unawaited(_prefetch(p));
              },
              viewerOverlayBuilder: (ctx, size, _) => _overlays(tooltip),
            ),
          ),
          OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (ctx) => _follower(ctx, tooltip),
          ),
        ],
      ),
    );
  }

  List<Widget> _overlays(ReaderTooltip? t) {
    if (t == null) return const [];
    final c = context.colors;
    final highlights = t is WordTooltipState ? (t.highlight ?? [t.anchor]) : const <Rect>[];
    final anchor = _docToViewer(t.anchor);
    return [
      for (final r in highlights)
        Positioned.fromRect(
          rect: _docToViewer(r).inflate(1.5),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.highlight,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      Positioned.fromRect(
        rect: anchor,
        child: IgnorePointer(
          child: CompositedTransformTarget(link: _link, child: const SizedBox.expand()),
        ),
      ),
    ];
  }

  Widget _follower(BuildContext ctx, ReaderTooltip? t) {
    if (t == null) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(ctx);
    final padding = MediaQuery.paddingOf(ctx);
    final anchorOnScreen = _docToViewer(t.anchor).shift(_viewerOrigin);
    final usable = Size(screen.width, screen.height - padding.bottom);
    // Place for the worst case (the height cap) rather than a measured height:
    // a measured height is already clipped by the previous placement, which
    // would feed back into a shrinking loop. Near the bottom third the tooltip
    // therefore flips above even when short, which is the conventional feel.
    final placement = placeTooltip(
      anchor: anchorOnScreen,
      tooltipSize: Size(340, usable.height * 0.45),
      screen: usable,
    );
    // Horizontal shift from "centred on the anchor" to the clamped position.
    final dx = placement.offset.dx + placement.width / 2 - anchorOnScreen.center.dx;

    final child = switch (t) {
      WordTooltipState() => WordTooltip(
          state: t,
          bookId: widget.book.id,
          bookTitle: widget.book.title,
          onShowDetails: () => _showDetails(t),
          onSuggestion: _lookupTyped,
        ),
      SentenceTooltipState() => SentenceTooltip(state: t, onTapWord: _lookupTyped),
    };

    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: placement.above ? Alignment.topCenter : Alignment.bottomCenter,
        followerAnchor: placement.above ? Alignment.bottomCenter : Alignment.topCenter,
        offset: Offset(dx, 0),
        child: TooltipCard(
          width: placement.width,
          maxHeight: placement.maxHeight,
          above: placement.above,
          child: child,
        ),
      ),
    );
  }
}
