// The PDF reader: pdfrx viewer + our tooltip layer.
//
// Tap a word → WordTooltip (local entry now, /context pinned when it lands).
// Long-press/drag (pdfrx's own selection) → SentenceTooltip (streamed
// translation), whose colour row saves the selection as a highlight. The
// tooltip hangs off a LayerLink target that we place in the viewer overlay at
// the anchor's current on-screen rect, so it tracks scroll and zoom; the
// follower lives in an OverlayPortal above everything.
//
// Highlights are anchored to (page, word range) in the page's PageTextIndex
// and painted in the viewer overlay from rects resolved per page.

import 'dart:async';
import 'dart:math' as math;

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/dev_hooks.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/normalize.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/ads/interstitials.dart';
import 'package:arth/features/cards/card_editor.dart';
import 'package:arth/features/cards/deck_screen.dart';
import 'package:arth/features/reader/bookmarks_sheet.dart';
import 'package:arth/features/reader/details_sheet.dart';
import 'package:arth/features/reader/flick_physics.dart';
import 'package:arth/features/reader/go_to_page.dart';
import 'package:arth/features/reader/highlights/highlight_colors.dart';
import 'package:arth/features/reader/highlights/highlights_sheet.dart';
import 'package:arth/features/reader/page_text_cache.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:arth/features/reader/reader_menu.dart';
import 'package:arth/features/reader/tooltip/tooltip_layer.dart';
import 'package:arth/features/settings/reading_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

const _pronouns = {
  'he', 'she', 'it', 'they', 'them', 'his', 'her', 'hers', 'its', 'their', //
  'theirs', 'him', 'this', 'that', 'these', 'those', 'i', 'we', 'you', 'who',
};

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.book, required this.filePath, super.key, this.initialPage});

  final Book book;

  /// Open here instead of where the reader left off.
  final int? initialPage;

  /// Absolute path, resolved against the documents directory at open time.
  final String filePath;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> with AdBreakOnClose {
  final _controller = PdfViewerController();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final GlobalKey _viewerKey = GlobalKey();
  PageTextCache? _cache;
  Timer? _selectionDebounce;
  bool _selectionHaptic = false;
  bool _warnedNoText = false;

  /// null = not checked yet; true = the first pages had no text at all.
  bool? _documentIsScanned;
  int? _page;

  /// The word range behind the sentence card, when it came from a selection
  /// we could place; the card's colour row highlights it.
  ({int page, int start, int end})? _selectionWords;

  /// Document-space bands per highlight id, resolved for pages near the
  /// current one (see _resolveHighlightRects).
  final Map<int, List<Rect>> _highlightRects = {};
  List<Highlight> _highlightsSeen = const [];

  /// Prefetch (Section 7): sentences already sent for /context this session.
  final Set<String> _prefetched = {};
  static const _prefetchRankThreshold = 8000;
  static const _prefetchMaxPerPage = 6;
  static const _prefetchMaxPerMinute = 12;
  final List<DateTime> _prefetchSent = [];
  DateTime? _prefetchPausedUntil;
  int _prefetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewerChanged);
    _registerDevHooks();
  }

  @override
  void dispose() {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
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
      _selectionWords = (page: page, start: from, end: to);
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
        'highlights': ref.read(highlightsProvider(widget.book.id)).valueOrNull?.map((h) => {'id': h.id, 'page': h.page, 'start': h.startWord, 'end': h.endWord, 'color': h.color.name}).toList(),
        'highlightRects': _highlightRects.length,
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

  // ---- highlights ----

  /// Resolve bands for highlights on pages near [page] that aren't resolved
  /// yet; drop entries for highlights that no longer exist.
  Future<void> _resolveHighlightRects(List<Highlight> highlights, int page) async {
    final cache = _cache;
    if (cache == null) return;
    _highlightRects.removeWhere((id, _) => !highlights.any((h) => h.id == id));
    var changed = false;
    for (final h in highlights) {
      if ((h.page - page).abs() > 3 || _highlightRects.containsKey(h.id)) continue;
      final PageTextIndex idx;
      try {
        idx = await cache.page(h.page);
      } on Exception {
        continue;
      }
      if (!mounted) return;
      if (idx.words.isEmpty) continue; // not loaded yet; resolved on a later pass
      final to = math.min(h.endWord, idx.words.length - 1);
      _highlightRects[h.id] = highlightBands([for (var i = h.startWord; i <= to; i++) idx.words[i].rect]);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  /// Map pdfrx's selection onto our word index by position: the words under
  /// the first and last selected characters. pdfrx's character offsets come
  /// from a different text extraction (drop caps and hyphenation throw them
  /// off), but both put the same glyph in the same place.
  ({int page, int start, int end})? _wordsForSelection(List<PdfPageTextRange> ranges, PageTextIndex idx) {
    if (ranges.map((r) => r.pageNumber).toSet().length != 1 || idx.words.isEmpty) return null;
    final page = ranges.first.pageNumber;
    Offset? centreOf(PdfPageTextRange r, int i) {
      final rects = r.pageText.charRects;
      if (i < 0 || i >= rects.length) return null;
      return _controller.calcRectForRectInsidePage(pageNumber: page, rect: rects[i]).center;
    }

    // Skip selected whitespace at either end; it has no word under it.
    final text = ranges.first.pageText.fullText;
    var from = ranges.first.start;
    while (from < ranges.first.end - 1 && text[from].trim().isEmpty) {
      from++;
    }
    var to = ranges.last.end - 1;
    final lastText = ranges.last.pageText.fullText;
    while (to > ranges.last.start && lastText[to].trim().isEmpty) {
      to--;
    }
    final first = centreOf(ranges.first, from);
    final last = centreOf(ranges.last, to);
    if (first == null || last == null) return null;
    final start = nearestWord(idx, first)?.index;
    final end = nearestWord(idx, last)?.index;
    if (start == null || end == null) return null;
    return (page: page, start: math.min(start, end), end: math.max(start, end));
  }

  Future<void> _highlightSelection(SentenceTooltipState s, HighlightColor color) async {
    final words = _selectionWords;
    final cache = _cache;
    if (words == null || cache == null) return;
    final idx = await cache.page(words.page);
    await ref.read(highlightsProvider(widget.book.id).notifier).add(
          page: words.page,
          startWord: words.start,
          endWord: words.end,
          color: color,
          textOf: (a, b) => normalizeSentence(idx.fullText.substring(idx.words[a].start, idx.words[b].end)),
        );
    if (!mounted) return;
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
    ref.read(readerControllerProvider.notifier).dismiss();
  }

  Future<void> _showHighlights() async {
    final t = ref.read(stringsProvider);
    await showHighlightsSheet(
      context,
      bookId: widget.book.id,
      emptyText: t.highlightsEmptyPdf,
      locationOf: (h) => t.page(h.page, _controller.isReady ? _controller.pageCount : h.page),
      onJump: (h) => unawaited(_controller.goToPage(pageNumber: h.page)),
    );
  }

  // ---- progress, bookmarks, cards ----

  Future<void> _reportProgress(int page) async {
    final count = _controller.isReady ? _controller.pageCount : 0;
    if (count == 0) return;
    final finished = await ref.read(libraryProvider.notifier).reportProgress(widget.book.id, page / count, lastPage: page);
    if (finished && mounted) await showFinishedSheet(context, ref, widget.book);
  }

  Future<void> _toggleBookmark() async {
    final page = _page ?? 1;
    final t = ref.read(stringsProvider);
    final notifier = ref.read(bookmarksProvider(widget.book.id).notifier);
    final existing = (ref.read(bookmarksProvider(widget.book.id)).valueOrNull ?? const <Bookmark>[]).where((b) => b.page == page).toList();
    if (existing.isNotEmpty) {
      for (final b in existing) {
        await notifier.remove(b.id);
      }
      return;
    }
    await notifier.add(page: page, label: t.pageLabel(page));
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.bookmarkAdded), duration: const Duration(seconds: 1)));
  }

  Future<void> _makeCard(CardDraft draft) async {
    final page = ref.read(readerControllerProvider)?.page ?? _page ?? 1;
    ref.read(readerControllerProvider.notifier).dismiss();
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
    final t = ref.read(stringsProvider);
    final saved = await showCardEditor(
      context,
      draft: draft.at(bookId: widget.book.id, bookTitle: widget.book.title, page: page, location: t.pageLabel(page)),
    );
    if (saved != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.cardSaved), duration: const Duration(seconds: 1)));
  }

  void _onViewerChanged() {
    // The overlay target moves with the document; rebuild so the follower's
    // above/below decision and clamp track it.
    if (mounted && ref.read(readerControllerProvider) != null) _afterLayout(() => setState(() {}));
  }

  /// pdfrx can notify from its own layout, when neither setState nor the
  /// portal may be touched; wait for the frame then.
  void _afterLayout(VoidCallback fn) {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) fn();
      });
    } else {
      fn();
    }
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
    // A tap anywhere lets go of a selection; a tap on a word then opens it.
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
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
    if (idx.words.isEmpty && mounted) {
      // A scanned document gets the banner (see _checkForTextLayer); a lone
      // image page in a text book just gets a one-line note, once.
      if (_documentIsScanned != true && !_warnedNoText) {
        _warnedNoText = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).noTextOnPage)));
      }
      rc.dismiss();
      return;
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
      book: (id: widget.book.id, title: widget.book.title),
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
      Haptics.choose();
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
    _selectionWords = _wordsForSelection(ranges, idx);

    // A single selected word gets the word card (speaker, save), with its
    // sentence. pdfrx's character offsets don't always line up with our
    // index, so match by text and pick the occurrence nearest the selection.
    if (!text.contains(' ')) {
      final key = normalizeWord(text);
      final centre = anchor!.center;
      var word = idx.wordAtChar(ranges.first.start);
      if (word == null || word.key != key) {
        final same = idx.words.where((w) => w.key == key).toList();
        if (same.isNotEmpty) {
          same.sort(
            (a, b) => (a.rect.center - centre).distanceSquared.compareTo((b.rect.center - centre).distanceSquared),
          );
          word = same.first;
        }
      }
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

  // ---- text layer check ----

  /// Sample the first pages once: if none has text, the whole PDF is almost
  /// certainly scanned images, and the reader should say so before the first
  /// tap fails rather than after.
  Future<void> _checkForTextLayer(int pageCount) async {
    final cache = _cache;
    if (cache == null) return;
    final sample = [for (var p = 1; p <= pageCount && p <= 6; p++) p];
    var words = 0;
    for (final p in sample) {
      try {
        words += (await cache.page(p)).words.length;
      } on Exception {
        // unreadable page: treat as no text
      }
      if (words > 0) break;
    }
    if (!mounted) return;
    setState(() => _documentIsScanned = words == 0);
    if (words == 0) {
      final t = ref.read(stringsProvider);
      final c = context.colors;
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          backgroundColor: c.card,
          content: Text(t.noTextLayer, style: uiBody(hindi: t.isHindi, color: c.ink, scale: ref.read(settingsProvider).hindiScale)),
          leading: Icon(Icons.image_not_supported_outlined, color: c.accent),
          actions: [
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: Text(t.dismiss, style: TextStyle(color: c.accent)),
            ),
          ],
        ),
      );
    }
  }

  // ---- prefetch ----

  /// Quietly resolve /context for rare or unknown words on this page and the
  /// next, so the tooltip's "इस वाक्य में" is a cache hit when tapped.
  /// Fire-and-forget: no retries, never blocks rendering, errors ignored.
  Future<void> _prefetch(int page) async {
    if (!ref.read(settingsProvider).prefetch) return;
    // Prefetch is free, but only for readers who could tap for these answers.
    final access = ref.read(aiAccessProvider);
    if (access != AiAccess.open && access != AiAccess.allowed) return;
    final cache = _cache;
    if (cache == null) return;
    final gen = ++_prefetchGeneration; // a newer page turn cancels this pass
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
        if (gen != _prefetchGeneration || !_prefetchAllowed()) return;
        final sentence = await cache.sentenceFor(p, idx, w);
        final id = '$key|$sentence';
        if (!_prefetched.add(id)) continue;
        sent++;
        _prefetchSent.add(DateTime.now());
        // One at a time: a burst would still trip the server bucket and
        // compete with the user's own tap for the connection.
        try {
          await repo.contextFor(word: key, sentence: sentence, prefetch: true);
        } on ApiFailure catch (e) {
          if (e.code == 'RATE_LIMITED') {
            _prefetchPausedUntil = DateTime.now().add(const Duration(minutes: 1));
            return;
          }
          if (e.isOffline) return;
        } on Exception catch (_) {
          // never retried; the tap path will fetch it if needed
        }
      }
    }
  }

  bool _prefetchAllowed() {
    final now = DateTime.now();
    if (_prefetchPausedUntil != null && now.isBefore(_prefetchPausedUntil!)) return false;
    _prefetchSent.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    return _prefetchSent.length < _prefetchMaxPerMinute;
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
        book: (id: widget.book.id, title: widget.book.title),
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
    if (tooltip == null && _portal.isShowing) {
      _afterLayout(() {
        if (_portal.isShowing && ref.read(readerControllerProvider) == null) _portal.hide();
      });
    }
    final highlights = ref.watch(highlightsProvider(widget.book.id)).valueOrNull ?? const <Highlight>[];
    if (!identical(highlights, _highlightsSeen)) {
      _highlightsSeen = highlights;
      unawaited(_resolveHighlightRects(highlights, _page ?? 1));
    }
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_page != null)
            Center(
              child: PageCounter(
                page: _page!,
                count: _controller.isReady ? _controller.pageCount : null,
                tooltip: t.goToPage,
                onGo: (p) => unawaited(_controller.goToPage(pageNumber: p)),
              ),
            ),
          BookmarkButton(
            marked: (ref.watch(bookmarksProvider(widget.book.id)).valueOrNull ?? const <Bookmark>[]).any((b) => b.page == (_page ?? 1)),
            onPressed: _page == null ? null : () => unawaited(_toggleBookmark()),
          ),
          IconButton(
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: t.readingSettings,
            onPressed: () => showReadingSettingsSheet(context),
          ),
          ReaderMoreMenu(
            onWords: () => context.push(Uri(path: '/vocabulary', queryParameters: {'book': '${widget.book.id}', 'title': widget.book.title}).toString()),
            onHighlights: _showHighlights,
            onBookmarks: () => showBookmarksSheet(
              context,
              bookId: widget.book.id,
              onJump: (b) => unawaited(_controller.goToPage(pageNumber: b.page)),
            ),
            onNote: () => unawaited(_makeCard(const CardDraft(kind: CardKind.idea))),
            onCards: () => context.push(deckRoute((bookId: widget.book.id, bookTitle: widget.book.title))),
          ),
        ],
      ),
      body: Stack(
        children: [
          PdfViewer.file(
            widget.filePath,
            key: _viewerKey,
            controller: _controller,
            initialPageNumber: widget.initialPage ?? widget.book.lastPage,
            params: PdfViewerParams(
              backgroundColor: c.paper,
              // Native scrolling (pdfrx's default flings stop short), with
              // hard flicks carried further.
              scrollPhysics: FlickBoostPhysics(parent: PdfViewerParams.getScrollPhysics(context)),
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
                unawaited(_resolveHighlightRects(_highlightsSeen, controller.pageNumber ?? 1));
                unawaited(_checkForTextLayer(doc.pages.length));
                unawaited(
                  ref.read(libraryProvider.notifier).touch(widget.book.id, pageCount: doc.pages.length),
                );
                setState(() => _page = controller.pageNumber);
                unawaited(_prefetch(controller.pageNumber ?? 1));
              },
              onPageChanged: (p) {
                if (p == null) return;
                setState(() => _page = p);
                unawaited(_reportProgress(p));
                unawaited(_prefetch(p));
                unawaited(_resolveHighlightRects(_highlightsSeen, p));
              },
              viewerOverlayBuilder: (ctx, size, _) => [
                for (final h in highlights)
                  for (final band in _highlightRects[h.id] ?? const <Rect>[])
                    Positioned.fromRect(
                      rect: _docToViewer(band).inflate(1.5),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: HighlightPalette.fill(h.color, brightness),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ...tooltipOverlays(context: ctx, tooltip: tooltip, link: _link, toLocal: _docToViewer),
              ],
            ),
          ),
          OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (ctx) => TooltipFollower(
              tooltip: tooltip,
              link: _link,
              anchorOnScreen: tooltip == null ? Rect.zero : _docToViewer(tooltip.anchor).shift(_viewerOrigin),
              bookId: widget.book.id,
              bookTitle: widget.book.title,
              onShowDetails: _showDetails,
              onSuggestion: _lookupTyped,
              onTranslateSentence: _translateSentence,
              highlightActions: HighlightActions(
                onSentenceColor: _selectionWords == null ? null : _highlightSelection,
              ),
              onMakeCard: (d) => unawaited(_makeCard(d)),
            ),
          ),
        ],
      ),
    );
  }

  void _translateSentence(WordTooltipState s) {
    _selectionWords = null; // the card's sentence isn't a placed selection
    _portal.show();
    ref.read(readerControllerProvider.notifier).showSentence(text: s.sentence, anchor: s.anchor, page: s.page);
  }
}
