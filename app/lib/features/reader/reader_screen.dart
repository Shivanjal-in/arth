// The PDF reader: pdfrx viewer + our tooltip layer.
//
// Tap a word → WordTooltip (local entry now, /context pinned when it lands).
// Long-press/drag (pdfrx's own selection) → SentenceTooltip (streamed
// translation), whose colour row saves the selection as a highlight. With
// AI lookup off, that same hold only opens the colour bar. The
// tooltip hangs off a LayerLink target that we place in the viewer overlay at
// the anchor's current on-screen rect, so it tracks scroll and zoom; the
// follower lives in an OverlayPortal above everything.
//
// Highlights are anchored to (page, word range) in the page's PageTextIndex
// and painted in the viewer overlay from rects resolved per page.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'package:arth/features/reader/curl/book_pager.dart';
import 'package:arth/features/reader/details_sheet.dart';
import 'package:arth/features/reader/flick_physics.dart';
import 'package:arth/features/reader/go_to_page.dart';
import 'package:arth/features/reader/highlights/highlight_bar.dart';
import 'package:arth/features/reader/highlights/highlight_colors.dart';
import 'package:arth/features/reader/highlights/highlights_sheet.dart';
import 'package:arth/features/reader/page_text_cache.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:arth/features/reader/reader_guide.dart';
import 'package:arth/features/reader/reader_menu.dart';
import 'package:arth/features/reader/reading_tracking.dart';
import 'package:arth/features/reader/search_sheet.dart';
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

class _ReaderScreenState extends ConsumerState<ReaderScreen> with AdBreakOnClose, ReadingTracking {
  @override
  int get trackedBookId => widget.book.id;

  final _controller = PdfViewerController();
  final _pager = BookPagerController();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  GlobalKey _viewerKey = GlobalKey();

  /// Which mode the viewer on screen was built for; a change builds a new one.
  late bool _modeShown = ref.read(settingsProvider).bookPages;
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
    unawaited(_loadZoom());
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

  Future<void> _saveSelectionHighlight(HighlightColor color) async {
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

  Future<void> _highlightSelection(SentenceTooltipState s, HighlightColor color) => _saveSelectionHighlight(color);

  Future<void> _highlightFromBar(HighlightBarState s, HighlightColor color) => _saveSelectionHighlight(color);

  /// Reading mode (page turns) ⇄ scrolling mode (an ordinary PDF reader).
  Future<void> _toggleMode() async {
    ref.read(readerControllerProvider.notifier).dismiss();
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
    Haptics.choose();
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(bookPages: !s.bookPages));
  }

  Future<void> _showSearch() async {
    final cache = _cache;
    if (cache == null || !_controller.isReady) return;
    ref.read(readerControllerProvider.notifier).dismiss();
    final t = ref.read(stringsProvider);
    final count = _controller.pageCount;
    await showSearchSheet(
      context,
      search: (query, add, cancelled) async {
        for (var p = 1; p <= count && !cancelled(); p++) {
          final idx = await cache.page(p);
          for (final hit in hitsIn(idx.fullText, query, label: t.pageLabel(p), page: p)) {
            add(hit);
          }
        }
      },
      onJump: (h) => unawaited(_goToPage(h.page)),
    );
  }

  Future<void> _showHighlights() async {
    final t = ref.read(stringsProvider);
    await showHighlightsSheet(
      context,
      bookId: widget.book.id,
      emptyText: t.highlightsEmptyPdf,
      locationOf: (h) => t.page(h.page, _controller.isReady ? _controller.pageCount : h.page),
      onJump: (h) => unawaited(_goToPage(h.page)),
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

  // ---- book mode ----

  /// Pages in a row, each far enough from the next that neighbours never show
  /// beside the one being read.
  static PdfPageLayout _bookLayout(List<PdfPage> pages, PdfViewerParams params) {
    final height = pages.fold<double>(0, (m, p) => math.max(m, p.height));
    // Wide enough that no neighbour shows however the phone is held: in
    // landscape the view is several page-widths across.
    final gap = 5 * pages.fold<double>(0, (m, p) => math.max(m, p.width));
    final layouts = <Rect>[];
    var x = 0.0;
    for (final page in pages) {
      layouts.add(Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height));
      x += page.width + gap;
    }
    return PdfPageLayout(pageLayouts: layouts, documentSize: Size(math.max(0, x - gap), height));
  }

  static double? _fitPage(PdfDocument document, PdfViewerController controller, double fitZoom, double coverZoom) => fitZoom;

  /// pdfrx reports ready a beat before its pages are laid out.
  PdfPageLayout? get _layoutOrNull {
    if (!_controller.isReady) return null;
    try {
      return _controller.layout;
    // pdfrx's null-check TypeError is how it says "not laid out yet".
    // ignore: avoid_catching_errors
    } on TypeError {
      return null;
    }
  }

  /// Pages are read one at a time and turned with a curl.
  bool get _bookMode => _modeShown;

  /// A tap in the margin beside the text turns the page.
  bool _turnFromEdge(Offset docPos) {
    if (!_bookMode || _layoutOrNull == null) return false;
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final x = MatrixUtils.transformPoint(_controller.value, docPos).dx;
    final w = box.size.width;
    if (x > w * 0.14 && x < w * 0.86) return false;
    unawaited(_pager.turn(forward: x >= w / 2));
    return true;
  }

  // ---- book view ----
  //
  // In book mode the page's white sheet is dropped (a colour filter maps white
  // to the paper and black to the ink) and each page is zoomed to its text, so
  // the words fill the screen like a reflowed book. The same placement is used
  // for the curl's pictures of the neighbouring pages.

  /// Per page: where its text sits, in page points (null: no text).
  final Map<int, Rect?> _textBoxes = {};
  ({double width, double centerX})? _bookRef;
  bool _bookViewSet = false;

  /// The reader's own zoom, on top of the zoom that fits the text to the
  /// screen. Kept across pages, rotation and sessions until zoomed out.
  static const _zoomSteps = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
  static const _zoomKey = 'reader_zoom';
  double _userZoom = 1;

  Future<void> _loadZoom() async {
    final saved = double.tryParse(await ref.read(localStoreProvider).get(_zoomKey) ?? '');
    if (!mounted || saved == null || saved <= 1 || !_zoomSteps.contains(saved)) return;
    setState(() => _userZoom = saved);
    if (_page != null) unawaited(_applyBookView(_page!));
  }

  void _stepZoom({required bool inward}) {
    final i = _zoomSteps.indexOf(_userZoom);
    final next = _zoomSteps[(i + (inward ? 1 : -1)).clamp(0, _zoomSteps.length - 1)];
    if (next == _userZoom) return;
    Haptics.choose();
    ref.read(readerControllerProvider.notifier).dismiss();
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
    setState(() => _userZoom = next);
    unawaited(ref.read(localStoreProvider).set(_zoomKey, next == 1 ? null : '$next'));
    if (_page != null) unawaited(_applyBookView(_page!));
  }

  /// White → paper, black → ink, in both themes.
  ColorFilter _paperFilter(ArthColors c) {
    List<double> row(int channel, Color paper, Color ink) {
      final p = [paper.r, paper.g, paper.b][channel] * 255;
      final i = [ink.r, ink.g, ink.b][channel] * 255;
      final out = List<double>.filled(5, 0);
      out[channel] = (p - i) / 255;
      out[4] = i;
      return out;
    }

    return ColorFilter.matrix([
      ...row(0, c.paper, c.ink),
      ...row(1, c.paper, c.ink),
      ...row(2, c.paper, c.ink),
      0, 0, 0, 1, 0, //
    ]);
  }

  /// The block of text on [page], in page points; null on a page without text.
  /// Waits up to [wait] for the page to load (long PDFs load their pages
  /// progressively); null then, and nothing is remembered about it.
  Future<Rect?> _textBoxOf(int page, {Duration wait = const Duration(seconds: 2)}) async {
    if (_textBoxes.containsKey(page)) return _textBoxes[page];
    final layout = _layoutOrNull;
    if (layout == null) return null;
    final pdfPage = _controller.pages[page - 1];
    final loaded = pdfPage.isLoaded && wait == Duration.zero ? pdfPage : await pdfPage.waitForLoaded(timeout: wait);
    if (loaded == null) return null;
    final text = await loaded.loadStructuredText();
    final origin = layout.pageLayouts[page - 1].topLeft;
    final lefts = <double>[];
    final rights = <double>[];
    var top = double.infinity;
    var bottom = -double.infinity;
    for (final r in text.charRects) {
      if (r.isEmpty) continue;
      final d = _controller.calcRectForRectInsidePage(pageNumber: page, rect: r).shift(-origin);
      if (d.isEmpty) continue;
      lefts.add(d.left);
      rights.add(d.right);
      top = math.min(top, d.top);
      bottom = math.max(bottom, d.bottom);
    }
    Rect? box;
    if (lefts.length >= 20) {
      lefts.sort();
      rights.sort();
      // Leave out the odd stray mark in a margin.
      box = Rect.fromLTRB(lefts[(lefts.length * 0.01).floor()], top, rights[(rights.length * 0.99).ceil() - 1], bottom);
    }
    return _textBoxes[page] = box;
  }

  /// How wide a column of text usually is in this book, and where it sits:
  /// the median over a spread of pages, so zoom is the same on every page.
  /// Uses only pages that are already loaded; it never waits, so a jump deep
  /// into a long PDF isn't held up. Remembered once enough pages back it.
  Future<({double width, double centerX})?> _bookRefOf() async {
    final known = _bookRef;
    if (known != null) return known;
    final n = _controller.pageCount;
    final sample = {for (var i = 0; i < 9; i++) 1 + (n - 1) * i ~/ 8, _page ?? 1};
    final boxes = <Rect>[];
    for (final page in sample) {
      if (!_textBoxes.containsKey(page) && !_controller.pages[page - 1].isLoaded) continue;
      final box = await _textBoxOf(page, wait: Duration.zero);
      if (box != null) boxes.add(box);
    }
    if (boxes.isEmpty) return null;
    double median(List<double> v) => (v..sort())[v.length ~/ 2];
    final ref = (width: median([for (final b in boxes) b.width]), centerX: median([for (final b in boxes) b.center.dx]));
    if (boxes.length >= math.min(sample.length, 5)) _bookRef = ref;
    return ref;
  }

  /// The zoom, and the point of the page (in page points) at the middle of the
  /// view, that put [page]'s text across a [view]-sized screen.
  Future<({double zoom, Offset center})> _bookViewOf(int page, Size view, {Duration wait = const Duration(seconds: 2)}) async {
    final pdfPage = _controller.document.pages[page - 1];
    final box = await _textBoxOf(page, wait: wait);
    final ref = await _bookRefOf();
    if (box == null || ref == null) {
      final zoom = math.min(view.width / pdfPage.width, view.height / pdfPage.height) * _userZoom;
      return (zoom: zoom, center: Offset(pdfPage.width / 2, pdfPage.height / 2));
    }
    const side = 20.0; // logical px kept clear either side of the text
    const top = 16.0;
    final byColumn = (view.width - 2 * side) / ref.width;
    final byThisPage = math.min((view.width - 2 * side) / box.width, (view.height - top - 12) / box.height);
    final zoom = math.min(byColumn, byThisPage) * _userZoom;
    final half = view.width / (2 * zoom);
    final low = box.right + side / zoom - half;
    final high = box.left - side / zoom + half;
    final cx = low <= high ? ref.centerX.clamp(low, high) : box.center.dx;
    return (zoom: zoom, center: Offset(cx, box.top - top / zoom + view.height / (2 * zoom)));
  }

  /// Put [page]'s text across the screen.
  Future<void> _applyBookView(int page, {int attempt = 0}) async {
    final layout = _layoutOrNull;
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (layout == null || box == null || !box.hasSize) {
      // pdfrx isn't laid out yet: try again shortly, and show the page as it
      // is rather than stay hidden if it never is.
      if (attempt < 20) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (mounted) await _applyBookView(page, attempt: attempt + 1);
      } else if (mounted && !_bookViewSet) {
        setState(() => _bookViewSet = true);
      }
      return;
    }
    if (page < 1 || page > _controller.pageCount) return;
    try {
      final v = await _bookViewOf(page, box.size);
      if (!mounted) return;
      final at = layout.pageLayouts[page - 1].topLeft + v.center;
      await _controller.goTo(_controller.calcMatrixFor(at, zoom: v.zoom, viewSize: box.size), duration: Duration.zero);
      // A page that hadn't loaded yet was placed to fit; once its text is
      // there, place it properly if the reader is still on it.
      if (!_textBoxes.containsKey(page)) unawaited(_refineBookView(page));
    } finally {
      // Never leave the reader hidden, whatever went wrong placing the text.
      if (mounted && !_bookViewSet) setState(() => _bookViewSet = true);
    }
  }

  int _settleGeneration = 0;

  /// After the view changes size (a rotation): pdfrx lays the pages out
  /// again on its own schedule, after this is told, so place the page again
  /// as the new size settles rather than once.
  void _settleBookView() {
    if (!_bookMode || _page == null) return;
    final generation = ++_settleGeneration;
    for (final ms in const [0, 250, 700, 1500]) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (mounted && generation == _settleGeneration && _bookMode && _page != null) unawaited(_applyBookView(_page!));
      });
    }
  }

  Future<void> _refineBookView(int page) async {
    if (await _textBoxOf(page, wait: const Duration(seconds: 30)) == null) return;
    if (mounted && _bookMode && _page == page) unawaited(_applyBookView(page));
  }

  /// Go to [page]: in book mode by placing its text, else as pdfrx does.
  Future<void> _goToPage(int page) => _bookMode ? _applyBookView(page) : _controller.goToPage(pageNumber: page);

  /// A picture of [page] as the book view shows it, for the page curl: the
  /// text where the live view would put it, on the paper.
  Future<ui.Image?> _snapshotPage(int page, Size pixels) async {
    final layout = _layoutOrNull;
    if (layout == null || page < 1 || page > _controller.pageCount) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final c = context.colors;
    final view = Size(pixels.width / dpr, pixels.height / dpr);
    final v = await _bookViewOf(page, view);
    final pdfPage = _controller.document.pages[page - 1];
    final px = v.zoom * dpr;
    final topLeft = Offset(v.center.dx - view.width / (2 * v.zoom), v.center.dy - view.height / (2 * v.zoom));
    final visible = Rect.fromLTWH(topLeft.dx, topLeft.dy, view.width / v.zoom, view.height / v.zoom).intersect(Rect.fromLTWH(0, 0, pdfPage.width, pdfPage.height));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(c.paper, BlendMode.src);
    if (!visible.isEmpty) {
      final rendered = await pdfPage.render(
        x: (visible.left * px).floor(),
        y: (visible.top * px).floor(),
        width: (visible.width * px).ceil(),
        height: (visible.height * px).ceil(),
        fullWidth: pdfPage.width * px,
        fullHeight: pdfPage.height * px,
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered != null) {
        final raw = await rendered.createImage();
        rendered.dispose();
        canvas.drawImageRect(
          raw,
          Rect.fromLTWH(0, 0, raw.width.toDouble(), raw.height.toDouble()),
          Rect.fromLTWH((visible.left - topLeft.dx) * px, (visible.top - topLeft.dy) * px, visible.width * px, visible.height * px),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = _paperFilter(c),
        );
        raw.dispose();
      }
    }
    return recorder.endRecording().toImage(pixels.width.toInt(), pixels.height.toInt());
  }

  Future<void> _showTurnedPage(int page) async {
    ref.read(readerControllerProvider.notifier).dismiss();
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
    await _applyBookView(page);
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
      if (!_turnFromEdge(docPos)) rc.dismiss();
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
      if (!_turnFromEdge(docPos)) rc.dismiss();
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
      final open = ref.read(readerControllerProvider);
      if (open is SentenceTooltipState || open is HighlightBarState) rc.dismiss();
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

    // Holding text to highlight it must not spend an AI call. The colour
    // bar still offers translate, for when they actually want it.
    if (!ref.read(settingsProvider).aiLookup) {
      _portal.show();
      ref.read(readerControllerProvider.notifier).showHighlightBar(
            anchor: anchor!,
            page: page,
            text: text,
          );
      return;
    }

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
    final settings = ref.read(settingsProvider);
    if (!settings.prefetch || !settings.aiLookup) return;
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
        if (rank != null && rank <= kAiOnRequestRank) continue;
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
    final bookMode = ref.watch(settingsProvider.select((s) => s.bookPages));
    if (bookMode != _modeShown) {
      // Reading mode and scrolling mode lay the pages out differently: start a
      // fresh viewer on the page the reader is on.
      _modeShown = bookMode;
      _viewerKey = GlobalKey();
      _cache = null;
      _bookViewSet = false;
      _textBoxes.clear();
      _bookRef = null;
      _settleGeneration++;
    }

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
                onGo: (p) => unawaited(_goToPage(p)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: t.search,
            onPressed: _cache == null ? null : () => unawaited(_showSearch()),
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
          const AiLookupButton(),
          ReaderMoreMenu(
            onWords: () => context.push(Uri(path: '/vocabulary', queryParameters: {'book': '${widget.book.id}', 'title': widget.book.title}).toString()),
            onHighlights: _showHighlights,
            onBookmarks: () => showBookmarksSheet(
              context,
              bookId: widget.book.id,
              onJump: (b) => unawaited(_goToPage(b.page)),
            ),
            onNote: () => unawaited(_makeCard(const CardDraft(kind: CardKind.idea))),
            onCards: () => context.push(deckRoute((bookId: widget.book.id, bookTitle: widget.book.title))),
            onToggleMode: () => unawaited(_toggleMode()),
          ),
        ],
      ),
      body: ReaderGuide(
        child: Stack(
        children: [
          BookPager(
            controller: _pager,
            enabled: bookMode && _page != null && _layoutOrNull != null,
            position: _page ?? 1,
            hasNext: (_page ?? 1) < (_controller.isReady ? _controller.pageCount : 1),
            hasPrevious: (_page ?? 1) > 1,
            paper: c.paper,
            snapshot: ({required next, required size}) => _snapshotPage((_page ?? 1) + (next ? 1 : -1), size),
            onTurn: ({required next}) => _showTurnedPage((_page ?? 1) + (next ? 1 : -1)),
            // Zoomed in, a drag pans the page; zoom out to turn it by swiping.
            canStart: () => _userZoom == 1 && !_controller.textSelectionDelegate.hasSelectedText,
            child: _BookFilter(
              enabled: bookMode,
              filter: _paperFilter(c),
              ready: _bookViewSet,
              child: PdfViewer.file(
                widget.filePath,
                key: _viewerKey,
                controller: _controller,
                initialPageNumber: _page ?? widget.initialPage ?? widget.book.lastPage,
                params: PdfViewerParams(
                  // Book mode: a page's text fills the view and the pager turns it,
                  // so the viewer neither pans nor zooms by itself. White pages
                  // go through the paper filter, which turns the white to paper.
                  backgroundColor: bookMode ? Colors.white : c.paper,
                  boundaryMargin: bookMode ? const EdgeInsets.all(100000) : null,
                  onViewSizeChanged: (_, _, _) => _settleBookView(),
                  margin: bookMode ? 0 : 8,
                  layoutPages: bookMode ? _bookLayout : null,
                  sizeDelegateProvider: bookMode ? const PdfViewerSizeDelegateProviderLegacy(calculateInitialZoom: _fitPage) : null,
                  pageDropShadow: bookMode ? null : const BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 2, offset: Offset(2, 2)),
                  panEnabled: !bookMode || _userZoom > 1,
                  scaleEnabled: !bookMode,
                  // Native scrolling (pdfrx's default flings stop short), with
                  // hard flicks carried further.
                  scrollPhysics: bookMode ? null : FlickBoostPhysics(parent: PdfViewerParams.getScrollPhysics(context)),
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
                    if (controller.pageNumber != null) trackPage(controller.pageNumber!);
                    unawaited(_prefetch(controller.pageNumber ?? 1));
                  },
                  onPageChanged: (p) {
                    if (p == null) return;
                    setState(() => _page = p);
                    trackPage(p);
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
            ),
          ),
          if (bookMode && _page != null)
            Positioned(
              right: 12,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: _ZoomControls(
                zoom: _userZoom,
                canIn: _userZoom < _zoomSteps.last,
                canOut: _userZoom > 1,
                onIn: () => _stepZoom(inward: true),
                onOut: () => _stepZoom(inward: false),
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
                onColor: _highlightFromBar,
                onTranslate: _translateSelection,
                onCopied: (_) => _releaseSelection(),
                onSentenceColor: _selectionWords == null ? null : _highlightSelection,
              ),
              onMakeCard: (d) => unawaited(_makeCard(d)),
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _translateSentence(WordTooltipState s) {
    _selectionWords = null; // the card's sentence isn't a placed selection
    _portal.show();
    ref.read(readerControllerProvider.notifier).showSentence(text: s.sentence, anchor: s.anchor, page: s.page);
  }

  void _releaseSelection() {
    unawaited(_controller.textSelectionDelegate.clearTextSelection());
    ref.read(readerControllerProvider.notifier).dismiss();
  }

  /// One selected word gets its meaning card; more gets the translation.
  Future<void> _translateSelection(HighlightBarState s) async {
    final words = _selectionWords;
    final cache = _cache;
    if (isSingleWord(s.text) && words != null && cache != null) {
      final idx = await cache.page(words.page);
      if (!mounted) return;
      if (words.start == words.end && words.start < idx.words.length) {
        await _openWord(cache, words.page, idx, idx.words[words.start]);
        return;
      }
    }
    _portal.show();
    ref.read(readerControllerProvider.notifier).showSentence(text: s.text, anchor: s.anchor, page: s.page);
  }
}

/// Zoom in / out, floating over the page; the level shows between them.
class _ZoomControls extends ConsumerWidget {
  const _ZoomControls({required this.zoom, required this.canIn, required this.canOut, required this.onIn, required this.onOut});

  final double zoom;
  final bool canIn;
  final bool canOut;
  final VoidCallback onIn;
  final VoidCallback onOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    return Material(
      color: c.card,
      elevation: 2,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: t.zoomOut,
            icon: const Icon(Icons.remove_rounded),
            color: c.accent,
            onPressed: canOut ? onOut : null,
          ),
          if (zoom > 1) Text('${(zoom * 100).round()}%', style: EnglishText.label(c.ink, size: 12)),
          IconButton(
            tooltip: t.zoomIn,
            icon: const Icon(Icons.add_rounded),
            color: c.accent,
            onPressed: canIn ? onIn : null,
          ),
        ],
      ),
    );
  }
}

/// Book mode's look: the viewer's white pages become the paper (see
/// _paperFilter), hidden until the first page has been placed.
class _BookFilter extends StatelessWidget {
  const _BookFilter({required this.enabled, required this.filter, required this.ready, required this.child});

  final bool enabled;
  final ColorFilter filter;
  final bool ready;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Opacity(opacity: ready ? 1 : 0, child: ColorFiltered(colorFilter: filter, child: child));
  }
}
