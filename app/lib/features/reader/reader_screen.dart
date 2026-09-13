// The PDF reader: pdfrx viewer + our tooltip layer.
//
// Tap a word → WordTooltip (local entry now, /context pinned when it lands).
// Long-press/drag (pdfrx's own selection) → SentenceTooltip (streamed
// translation). The tooltip hangs off a LayerLink target that we place in the
// viewer overlay at the anchor's current on-screen rect, so it tracks scroll
// and zoom; the follower lives in an OverlayPortal above everything.

import 'dart:async';

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
  const ReaderScreen({required this.book, super.key});

  final Book book;

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
  Size _tooltipSize = const Size(340, 220);
  int? _page;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onViewerChanged);
    _selectionDebounce?.cancel();
    super.dispose();
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
                  style: EnglishText.caps(c.inkMuted),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: 'पढ़ने की सेटिंग',
            onPressed: () => showReadingSettingsSheet(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewer.file(
            widget.book.path,
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
              onGeneralTap: _onTap,
              onViewerReady: (doc, controller) {
                _cache = PageTextCache(controller);
                unawaited(
                  ref.read(libraryProvider.notifier).touch(widget.book.id, pageCount: doc.pages.length),
                );
                setState(() => _page = controller.pageNumber);
              },
              onPageChanged: (p) {
                if (p == null) return;
                setState(() => _page = p);
                unawaited(ref.read(libraryProvider.notifier).touch(widget.book.id, lastPage: p));
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
    final placement = placeTooltip(
      anchor: anchorOnScreen,
      tooltipSize: _tooltipSize,
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
        child: _MeasureSize(
          onChange: (s) {
            if ((s.height - _tooltipSize.height).abs() > 4 && mounted) {
              setState(() => _tooltipSize = s);
            }
          },
          child: TooltipCard(
            width: placement.width,
            maxHeight: placement.maxHeight,
            above: placement.above,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Reports the child's laid-out size after each frame it changes.
class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onChange, required this.child});

  final ValueChanged<Size> onChange;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  final GlobalKey _key = GlobalKey();
  Size? _last;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      if (_last != box.size) {
        _last = box.size;
        widget.onChange(box.size);
      }
    });
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
