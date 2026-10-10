// Reader for reflowable books (EPUB, and TXT, HTML, ODT, DOCX, FB2, RTF via
// ReflowBook): the chapter's blocks laid out as a scrolling column of
// text we paint ourselves, with the same word tooltip as the PDF and scan
// readers. Swipe between chapters; the Contents sheet jumps by title.
//
// The tooltip's document space is the tapped block's own coordinates: the
// highlight and LayerLink target sit inside that block's Stack, so they
// scroll with it, and the follower hangs off the target as usual.
//
// Highlighter: press and hold a word, drag to extend within the paragraph,
// release for the colour bar. Long-press an existing highlight to recolour or
// remove it. Highlights are anchored to (chapter, block, word range) and
// painted by the block's render object under the text.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:arth/app/dev_hooks.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:arth/core/formats/reflow_book.dart';
import 'package:arth/core/normalize.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/ads/interstitials.dart';
import 'package:arth/features/cards/card_editor.dart';
import 'package:arth/features/cards/deck_screen.dart';
import 'package:arth/features/epub/epub_paragraph.dart';
import 'package:arth/features/reader/bookmarks_sheet.dart';
import 'package:arth/features/reader/curl/book_pager.dart';
import 'package:arth/features/reader/details_sheet.dart';
import 'package:arth/features/reader/flick_physics.dart';
import 'package:arth/features/reader/highlights/highlight_bar.dart';
import 'package:arth/features/reader/highlights/highlight_colors.dart';
import 'package:arth/features/reader/highlights/highlights_sheet.dart';
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
import 'package:google_fonts/google_fonts.dart';

class EpubReaderScreen extends ConsumerStatefulWidget {
  const EpubReaderScreen({required this.book, required this.filePath, super.key, this.initialPlace});

  final Book book;

  /// Open here (a card's or bookmark's chapter and block) instead of where
  /// the reader left off.
  final BookPlace? initialPlace;

  /// Absolute path, resolved against the documents directory at open time.
  final String filePath;

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

/// Which block the tooltip belongs to.
typedef _BlockRef = ({int chapter, int block});

/// A run of words in one block (inclusive).
typedef _WordRange = ({_BlockRef at, int start, int end});

const _pagePadding = EdgeInsets.fromLTRB(22, 20, 22, 120);

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> with AdBreakOnClose, ReadingTracking {
  @override
  int get trackedBookId => widget.book.id;

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  ReflowBook? _epub;
  bool _openFailed = false;
  PageController? _pager;
  int _chapter = 0;

  /// Scroll offset to restore when the chapter first builds, if it is the
  /// chapter the reader left off in.
  double _restoreOffset = 0;
  int? _restoreChapter;

  /// Block to scroll to when a chapter next builds (jump from Highlights).
  int? _jumpBlock;
  int? _jumpChapter;

  _BlockRef? _active;
  RenderParagraphBlock? _activeRender;

  /// The highlighter's selection while dragging and while its bar is up.
  _WordRange? _selection;
  int _selectionAnchor = 0;
  Highlight? _editing;

  /// Where the sentence a translation card shows sits, so it can be
  /// highlighted from the card.
  _WordRange? _sentenceRange;

  /// Mounted blocks of the current chapter (dev hooks, bookmarks).
  final Map<int, GlobalKey> _mounted = {};

  /// First and last block on screen, refreshed when scrolling settles: what
  /// the bookmark ribbon marks.
  ({int first, int last})? _visible;

  String get _posKey => 'epub_pos_${widget.book.id}';

  @override
  void initState() {
    super.initState();
    unawaited(_open());
    _registerDevHooks();
  }

  @override
  void dispose() {
    _pager?.dispose();
    unawaited(_epub?.close());
    DevHooks.off('tapWord');
    DevHooks.off('select');
    DevHooks.off('dismiss');
    DevHooks.off('state');
    super.dispose();
  }

  Future<void> _open() async {
    final ReflowBook epub;
    try {
      epub = await ReflowBook.open(widget.filePath);
    } on Exception {
      if (mounted) setState(() => _openFailed = true);
      return;
    }
    final saved = await ref.read(localStoreProvider).get(_posKey);
    if (!mounted) {
      await epub.close();
      return;
    }
    final place = widget.initialPlace;
    final chapter = ((place?.page ?? widget.book.lastPage) - 1).clamp(0, epub.chapterCount - 1);
    final parts = saved?.split(':');
    if (place != null) {
      _jumpChapter = chapter;
      _jumpBlock = place.block;
    } else if (parts != null && parts.length == 2 && int.tryParse(parts[0]) == chapter) {
      _restoreChapter = chapter;
      _restoreOffset = double.tryParse(parts[1]) ?? 0;
    }
    setState(() {
      _epub = epub;
      _chapter = chapter;
      _pager = PageController(initialPage: chapter);
    });
    unawaited(ref.read(libraryProvider.notifier).touch(widget.book.id, pageCount: epub.chapterCount));
  }

  void _registerDevHooks() {
    RenderParagraphBlock? renderOf(int block) {
      final r = _mounted[block]?.currentContext?.findRenderObject();
      return r is RenderParagraphBlock && r.hasSize ? r : null;
    }

    DevHooks.on('tapWord', (p) async {
      final key = normalizeWord(p['word'] ?? '');
      final nth = int.tryParse(p['nth'] ?? '') ?? 0;
      var seen = 0;
      for (final block in _mounted.keys.toList()..sort()) {
        final r = renderOf(block);
        if (r == null) continue;
        for (final w in r.index.words.where((w) => w.key == key)) {
          if (seen++ < nth) continue;
          await _openWord((chapter: _chapter, block: block), r, w);
          return {'ok': true, 'block': block, 'rect': w.rect.toString()};
        }
      }
      return {'ok': false, 'reason': 'word not in the visible blocks', 'visible': _mounted.length};
    });
    // Highlighter: select from..to (keys) in the first visible block holding both.
    DevHooks.on('select', (p) async {
      for (final block in _mounted.keys.toList()..sort()) {
        final r = renderOf(block);
        if (r == null) continue;
        final from = r.index.words.indexWhere((w) => w.key == normalizeWord(p['from'] ?? ''));
        final to = r.index.words.indexWhere((w) => w.key == normalizeWord(p['to'] ?? ''), math.max(from, 0));
        if (from < 0 || to < 0) continue;
        final at = (chapter: _chapter, block: block);
        _onPressStart(at, r, r.index.words[from].rect.center);
        _onPressMove(at, r, r.index.words[to].rect.center);
        _onPressEnd(at, r);
        final color = p['color'];
        if (color != null) {
          final s = ref.read(readerControllerProvider);
          if (s is HighlightBarState) await _pickColor(s, HighlightColor.values.byName(color));
        }
        return {'ok': true, 'block': block, 'from': from, 'to': to};
      }
      return {'ok': false, 'reason': 'words not in the visible blocks'};
    });
    DevHooks.on('dismiss', (_) async {
      _dismiss();
      return {'ok': true};
    });
    DevHooks.on('state', (_) async {
      final s = ref.read(readerControllerProvider);
      final highlights = ref.read(highlightsProvider(widget.book.id)).valueOrNull;
      return {
        'tooltip': s?.runtimeType.toString(),
        'chapter': _chapter + 1,
        'chapters': _epub?.chapterCount,
        'ready': _epub != null,
        'block': _active?.block,
        'selection': _selection == null ? null : {'block': _selection!.at.block, 'start': _selection!.start, 'end': _selection!.end},
        'highlights': highlights
            ?.map((h) => {'id': h.id, 'page': h.page, 'block': h.block, 'start': h.startWord, 'end': h.endWord, 'color': h.color.name, 'text': h.text})
            .toList(),
        if (s is WordTooltipState)
          'word': {
            'key': s.key,
            'sentence': s.sentence,
            'outcome': s.outcome?.runtimeType.toString(),
            'lemma': s.outcome is LookupFound ? (s.outcome! as LookupFound).lemma : null,
            'contextLoading': s.contextLoading,
            'context': s.context?.toJson(),
            'contextError': s.contextError,
          },
        if (s is SentenceTooltipState) 'sentence': {'text': s.text, 'hindi': s.hindi, 'error': s.error, 'done': s.done},
        if (s is HighlightBarState) 'bar': {'text': s.text, 'existing': s.existing?.id},
      };
    });
  }

  // ---- book mode ----

  final _bookPager = BookPagerController();

  /// The page showing in [_chapter], and the scroll offset it starts at (kept
  /// so a change of size can find the same place again).
  int _bookPage = 0;
  double _bookOffset = 0;
  final Map<int, _ChapterPages> _paging = {};
  String? _pagingKey;
  bool _pagingBusy = false;
  bool _bookPlaced = false;

  /// The area a page's text fills (the body less the space above and below).
  Size _viewport = Size.zero;

  bool get _bookMode => ref.read(settingsProvider).bookPages;

  /// Throws away the pages if the size or text scale they were cut for changed.
  void _syncPagingKey(Size viewport, TextScaler scaler) {
    _viewport = viewport;
    final key = '${viewport.width}x${viewport.height}@${scaler.scale(10)}';
    if (_pagingKey == key) return;
    _pagingKey = key;
    _paging.clear();
  }

  Future<_ChapterPages?> _pagesOf(int chapter) async {
    final epub = _epub;
    if (epub == null || _viewport.isEmpty) return null;
    final known = _paging[chapter];
    if (known != null) return known;
    final scaler = MediaQuery.textScalerOf(context);
    final c = context.colors;
    final viewport = _viewport;
    final key = _pagingKey;
    final blocks = await epub.chapter(chapter);
    // Measuring before the book font has loaded would use a stand-in's metrics.
    await GoogleFonts.pendingFonts();
    if (!mounted) return null;
    final pages = _paginate(blocks, width: viewport.width, height: viewport.height, scaler: scaler, c: c);
    // Don't keep pages cut for a size that has since changed.
    if (_pagingKey == key) _paging[chapter] = pages;
    return pages;
  }

  /// Cut the current chapter into pages (once the body has a size) and put
  /// the reader on the right one.
  void _ensurePaging() {
    if (_pagingBusy || _epub == null || _viewport.isEmpty || _paging[_chapter] != null) return;
    _pagingBusy = true;
    unawaited(() async {
      try {
        final chapter = _chapter;
        final pages = await _pagesOf(chapter);
        if (!mounted || pages == null || chapter != _chapter) return;
        final page = _bookPlaced ? pages.pageAt(_bookOffset) : await _firstBookPage(chapter, pages);
        _bookPlaced = true;
        setState(() {
          _bookPage = page;
          _bookOffset = pages.starts[page];
        });
      } finally {
        _pagingBusy = false;
      }
    }());
  }

  /// Where to open: a bookmark or highlight's block, or where the reader left off.
  Future<int> _firstBookPage(int chapter, _ChapterPages pages) async {
    final jump = _jumpChapter == chapter ? _jumpBlock : null;
    if (_jumpChapter == chapter) {
      _jumpChapter = null;
      _jumpBlock = null;
    }
    if (jump != null) return _pageOfBlock(chapter, jump, pages);
    if (_restoreChapter == chapter) return pages.pageAt(_restoreOffset);
    return 0;
  }

  Future<int> _pageOfBlock(int chapter, int block, _ChapterPages pages) async {
    final epub = _epub;
    if (epub == null) return 0;
    final scaler = MediaQuery.textScalerOf(context);
    final c = context.colors;
    final blocks = await epub.chapter(chapter);
    if (block >= blocks.length) return 0;
    final y = _offsetOfBlock(blocks, block, width: _viewport.width, scaler: scaler, c: c);
    return pages.pageAt(y + _styleFor(blocks[block], first: block == 0, c: c).padding.top + 1);
  }

  /// The page after (or before) the one showing, possibly in another chapter.
  Future<({int chapter, int page})?> _neighbourPage({required bool next}) async {
    final epub = _epub;
    final here = _paging[_chapter];
    if (epub == null || here == null) return null;
    if (next) {
      if (_bookPage + 1 < here.count) return (chapter: _chapter, page: _bookPage + 1);
      if (_chapter + 1 >= epub.chapterCount) return null;
      return (chapter: _chapter + 1, page: 0);
    }
    if (_bookPage > 0) return (chapter: _chapter, page: _bookPage - 1);
    if (_chapter == 0) return null;
    final before = await _pagesOf(_chapter - 1);
    return before == null ? null : (chapter: _chapter - 1, page: before.count - 1);
  }

  Future<void> _goToBookPage(int chapter, int page) async {
    _dismiss();
    final pages = await _pagesOf(chapter);
    if (!mounted || pages == null) return;
    final p = page.clamp(0, pages.count - 1);
    final changed = chapter != _chapter;
    setState(() {
      _chapter = chapter;
      _bookPage = p;
      _bookOffset = pages.starts[p];
      _visible = null;
    });
    if (changed) {
      _mounted.clear();
      _pager?.jumpToPage(chapter);
    }
    // Let the page be placed and painted before the curl lets go.
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted) _updateVisible();
  }

  Future<void> _turnBook({required bool next}) async {
    final target = await _neighbourPage(next: next);
    if (target != null) await _goToBookPage(target.chapter, target.page);
  }

  Future<void> _jumpToBook(int chapter, int? block) async {
    final pages = await _pagesOf(chapter);
    if (pages == null) return;
    await _goToBookPage(chapter, block == null ? 0 : await _pageOfBlock(chapter, block, pages));
  }

  /// A picture of the page next to this one, drawn the way the live page is.
  Future<ui.Image?> _bookSnapshot({required bool next, required Size size}) async {
    final epub = _epub;
    final target = await _neighbourPage(next: next);
    if (epub == null || target == null) return null;
    final pages = await _pagesOf(target.chapter);
    if (pages == null || !mounted) return null;
    final blocks = await epub.chapter(target.chapter);
    if (!mounted) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final c = context.colors;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(c.paper, BlendMode.src)
      ..scale(dpr);
    _paintPage(
      canvas,
      blocks: blocks,
      pages: pages,
      page: target.page,
      width: _viewport.width,
      origin: const Offset(0, _pageTopInset),
      scaler: MediaQuery.textScalerOf(context),
      c: c,
    );
    return recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
  }

  // ---- position ----

  void _savePosition(double offset) {
    unawaited(ref.read(localStoreProvider).set(_posKey, '$_chapter:${offset.toStringAsFixed(0)}'));
  }

  void _onChapterChanged(int i) {
    _dismiss();
    setState(() {
      _chapter = i;
      _visible = null;
    });
    _mounted.clear();
    _restoreChapter = null;
    _savePosition(0);
    unawaited(_reportProgress(0));
    _afterLayout(_updateVisible);
  }

  /// Progress through the book: whole chapters read plus how far down this
  /// one the reader has scrolled.
  Future<void> _reportProgress(double chapterFraction) async {
    final epub = _epub;
    if (epub == null || epub.chapterCount == 0) return;
    final progress = (_chapter + chapterFraction.clamp(0.0, 1.0)) / epub.chapterCount;
    final finished = await ref.read(libraryProvider.notifier).reportProgress(widget.book.id, progress, lastPage: _chapter + 1);
    if (finished && mounted) await showFinishedSheet(context, ref, widget.book);
  }

  void _onScrollEnd(ScrollMetrics m) {
    final pages = _bookMode ? _paging[_chapter] : null;
    if (pages != null) {
      final page = _bookPage.clamp(0, pages.count - 1);
      _savePosition(pages.starts[page]);
      unawaited(_reportProgress((page + 1) / pages.count));
    } else {
      _savePosition(m.pixels);
      unawaited(_reportProgress(m.maxScrollExtent <= 0 ? 1 : m.pixels / m.maxScrollExtent));
    }
    _updateVisible();
  }

  /// Which blocks are on screen, from the mounted blocks' positions.
  void _updateVisible() {
    if (!mounted) return;
    var top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    var bottom = MediaQuery.sizeOf(context).height;
    final pages = _bookMode ? _paging[_chapter] : null;
    if (pages != null) {
      // Only the page's own window counts; the rest of the column is clipped.
      final page = _bookPage.clamp(0, pages.count - 1);
      top += _pageTopInset;
      bottom = top + pages.ends[page] - pages.starts[page];
    }
    int? first;
    int? last;
    for (final block in _mounted.keys.toList()..sort()) {
      final box = _mounted[block]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= top || y >= bottom) continue;
      first ??= block;
      last = block;
    }
    final visible = first == null ? null : (first: first, last: last!);
    if (visible != _visible) setState(() => _visible = visible);
  }

  List<Bookmark> _bookmarksHere(List<Bookmark> all) {
    final v = _visible;
    return [
      for (final b in all)
        if (b.page == _chapter + 1 && (v == null ? b.block == null : (b.block ?? 0) >= v.first && (b.block ?? 0) <= v.last)) b,
    ];
  }

  Future<void> _toggleBookmark() async {
    final epub = _epub;
    if (epub == null) return;
    final t = ref.read(stringsProvider);
    final notifier = ref.read(bookmarksProvider(widget.book.id).notifier);
    _updateVisible();
    final here = _bookmarksHere(ref.read(bookmarksProvider(widget.book.id)).valueOrNull ?? const []);
    if (here.isNotEmpty) {
      for (final b in here) {
        await notifier.remove(b.id);
      }
      return;
    }
    final block = _visible?.first;
    String? excerpt;
    if (block != null) {
      final blocks = await epub.chapter(_chapter);
      if (block < blocks.length) {
        final text = blocks[block].text;
        excerpt = text.length > 140 ? '${text.substring(0, 140)}…' : text;
      }
    }
    await notifier.add(page: _chapter + 1, block: block, label: epub.titleOf(_chapter) ?? t.section(_chapter + 1), excerpt: excerpt);
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.bookmarkAdded), duration: const Duration(seconds: 1)));
  }

  /// Jumps to a chapter and block (a bookmark, a highlight).
  void _jumpTo(int chapter, int? block) {
    _dismiss();
    if (_bookMode) {
      unawaited(_jumpToBook(chapter, block));
      return;
    }
    _jumpChapter = chapter;
    _jumpBlock = block;
    if (chapter != _chapter) {
      _pager?.jumpToPage(chapter);
    } else {
      setState(() {});
    }
  }

  Future<void> _makeCard(CardDraft draft) async {
    final epub = _epub;
    if (epub == null) return;
    _updateVisible();
    final at = _active ?? _sentenceRange?.at ?? _selection?.at;
    final chapter = at?.chapter ?? _chapter;
    final block = at?.block ?? _visible?.first;
    _dismiss();
    final t = ref.read(stringsProvider);
    final saved = await showCardEditor(
      context,
      draft: draft.at(
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        page: chapter + 1,
        block: block,
        location: epub.titleOf(chapter) ?? t.section(chapter + 1),
      ),
    );
    if (saved != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.cardSaved), duration: const Duration(seconds: 1)));
  }

  // ---- tooltip ----

  void _dismiss() {
    ref.read(readerControllerProvider.notifier).dismiss();
    if ((_active != null || _selection != null) && mounted) {
      setState(() {
        _active = null;
        _activeRender = null;
        _selection = null;
        _editing = null;
        _sentenceRange = null;
      });
    }
  }

  void _onBlockTap(_BlockRef at, RenderParagraphBlock render, Offset local) {
    final word = render.index.wordAt(local, margin: 3);
    if (word == null || word.key.isEmpty) {
      _dismiss();
      return;
    }
    unawaited(_openWord(at, render, word));
  }

  Future<void> _openWord(_BlockRef at, RenderParagraphBlock render, PageWord word) async {
    final idx = render.index;
    final span = idx.sentenceOf(word.index);
    final sentence = normalizeSentence(idx.rawSentence(span));
    final around = idx.tokensAround(word.index);
    final offset = word.index - around.index;
    setState(() {
      _active = at;
      _activeRender = render;
      _selection = null;
      _editing = null;
      _sentenceRange = (at: at, start: span.firstWord, end: span.lastWord);
    });
    _portal.show();
    await ref.read(readerControllerProvider.notifier).showWord(
          book: (id: widget.book.id, title: widget.book.title),
          word: word,
          page: at.chapter + 1,
          sentence: sentence,
          tokens: around.tokens,
          index: around.index,
          rectsForWindow: (start, count) => [
            for (var i = start; i < start + count; i++)
              if (i + offset >= 0 && i + offset < idx.words.length) idx.words[i + offset].rect,
          ],
        );
  }

  /// The tooltip's block scrolled out of the list and was disposed. That
  /// happens while the tree is locked, so the state change waits a tick.
  void _onActiveBlockUnmounted() {
    scheduleMicrotask(() {
      if (mounted && ref.read(readerControllerProvider) != null) _dismiss();
    });
  }

  Future<void> _lookupTyped(String word) async {
    // From a suggestion chip or a difficult-word chip: same tooltip, same anchor.
    final s = ref.read(readerControllerProvider);
    final at = _active;
    final render = _activeRender;
    if (s == null || at == null || render == null) return;
    final key = normalizeWord(word);
    final match = render.attached ? render.index.words.where((w) => w.key == key).firstOrNull : null;
    if (match != null) {
      await _openWord(at, render, match);
      return;
    }
    final sentence = switch (s) {
      WordTooltipState() => s.sentence,
      SentenceTooltipState() => s.text,
      HighlightBarState() => s.text,
    };
    await ref.read(readerControllerProvider.notifier).showWord(
          book: (id: widget.book.id, title: widget.book.title),
          word: PageWord(index: 0, start: 0, end: 0, text: word, rect: s.anchor),
          page: s.page,
          sentence: sentence,
          tokens: [key],
          index: 0,
          rectsForWindow: (_, _) => [s.anchor],
        );
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

  void _translateSentence(WordTooltipState s) {
    _portal.show();
    ref.read(readerControllerProvider.notifier).showSentence(text: s.sentence, anchor: s.anchor, page: s.page);
  }

  /// Scroll notifications can arrive from a layout-time correction, when
  /// neither setState nor the portal may be touched; wait for the frame then.
  void _afterLayout(VoidCallback fn) {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) fn();
      });
    } else {
      fn();
    }
  }

  Rect _anchorOnScreen(Rect anchor) {
    final r = _activeRender;
    if (r == null || !r.attached || !r.hasSize) return Rect.zero;
    return anchor.shift(r.localToGlobal(Offset.zero));
  }

  // ---- highlighter ----

  List<Highlight> get _highlights => ref.read(highlightsProvider(widget.book.id)).valueOrNull ?? const [];

  HighlightsNotifier get _highlighter => ref.read(highlightsProvider(widget.book.id).notifier);

  static Rect _rectOf(PageTextIndex idx, int start, int end) {
    var r = idx.words[start].rect;
    for (var i = start + 1; i <= end; i++) {
      r = r.expandToInclude(idx.words[i].rect);
    }
    return r;
  }

  static String _textOf(PageTextIndex idx, int start, int end) =>
      normalizeSentence(idx.fullText.substring(idx.words[start].start, idx.words[end].end));

  void _onPressStart(_BlockRef at, RenderParagraphBlock render, Offset local) {
    final word = render.index.wordAt(local, margin: 6);
    if (word == null) return;
    final existing = _highlights.where((h) => h.page == at.chapter + 1 && h.block == at.block && h.covers(word.index)).firstOrNull;
    Haptics.choose();
    ref.read(readerControllerProvider.notifier).dismiss();
    setState(() {
      _active = at;
      _activeRender = render;
      _editing = existing;
      _selectionAnchor = word.index;
      _selection = existing == null
          ? (at: at, start: word.index, end: word.index)
          : (at: at, start: existing.startWord, end: existing.endWord);
      _sentenceRange = null;
    });
    if (existing != null) _showBar(render, existing: existing);
  }

  void _onPressMove(_BlockRef at, RenderParagraphBlock render, Offset local) {
    final sel = _selection;
    if (_editing != null || sel == null || sel.at != at) return;
    final word = nearestWord(render.index, local);
    if (word == null) return;
    final start = math.min(_selectionAnchor, word.index);
    final end = math.max(_selectionAnchor, word.index);
    if (start == sel.start && end == sel.end) return;
    setState(() => _selection = (at: at, start: start, end: end));
  }

  void _onPressEnd(_BlockRef at, RenderParagraphBlock render) {
    final sel = _selection;
    if (_editing != null || sel == null || sel.at != at) return;
    _showBar(render);
  }

  void _showBar(RenderParagraphBlock render, {Highlight? existing}) {
    final sel = _selection;
    if (sel == null) return;
    final idx = render.index;
    _portal.show();
    ref.read(readerControllerProvider.notifier).showHighlightBar(
          anchor: _rectOf(idx, sel.start, sel.end),
          page: sel.at.chapter + 1,
          text: _textOf(idx, sel.start, sel.end),
          existing: existing,
        );
  }

  Future<void> _pickColor(HighlightBarState s, HighlightColor color) async {
    final existing = s.existing;
    final sel = _selection;
    final render = _activeRender;
    if (render != null && (existing != null || sel != null)) {
      await _highlighter.add(
        page: existing?.page ?? sel!.at.chapter + 1,
        block: existing?.block ?? sel!.at.block,
        startWord: existing?.startWord ?? sel!.start,
        endWord: existing?.endWord ?? sel!.end,
        color: color,
        textOf: (a, b) => _textOf(render.index, a, b),
        replacing: existing?.id,
      );
    }
    if (mounted) _dismiss();
  }

  Future<void> _removeHighlight(HighlightBarState s) async {
    if (s.existing != null) await _highlighter.remove(s.existing!.id);
    if (mounted) _dismiss();
  }

  /// One selected word gets its meaning card; more gets the translation.
  void _translateSelection(HighlightBarState s) {
    final sel = _selection;
    final render = _activeRender;
    if (isSingleWord(s.text) && sel != null && render != null && render.attached && sel.start == sel.end && sel.start < render.index.words.length) {
      unawaited(_openWord(sel.at, render, render.index.words[sel.start]));
      return;
    }
    _sentenceRange = _selection;
    _portal.show();
    ref.read(readerControllerProvider.notifier).showSentence(text: s.text, anchor: s.anchor, page: s.page);
  }

  Future<void> _highlightSentence(SentenceTooltipState s, HighlightColor color) async {
    final range = _sentenceRange;
    final render = _activeRender;
    if (range == null || render == null) return;
    await _highlighter.add(
      page: range.at.chapter + 1,
      block: range.at.block,
      startWord: range.start,
      endWord: range.end,
      color: color,
      textOf: (a, b) => _textOf(render.index, a, b),
    );
    if (mounted) _dismiss();
  }

  /// Reading mode (page turns) ⇄ scrolling mode, staying at the same place.
  Future<void> _toggleMode() async {
    _updateVisible();
    final chapter = _chapter;
    final block = _visible?.first;
    _dismiss();
    Haptics.choose();
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(bookPages: !s.bookPages));
    // Let the other layout be built, then go back to where the reader was.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) _jumpTo(chapter, block);
  }

  Future<void> _showSearch() async {
    final epub = _epub;
    if (epub == null) return;
    _dismiss();
    final t = ref.read(stringsProvider);
    await showSearchSheet(
      context,
      search: (query, add, cancelled) async {
        for (var ch = 0; ch < epub.chapterCount && !cancelled(); ch++) {
          final blocks = await epub.chapter(ch);
          final label = epub.titleOf(ch) ?? t.section(ch + 1);
          for (var b = 0; b < blocks.length && !cancelled(); b++) {
            for (final hit in hitsIn(blocks[b].text, query, label: label, page: ch + 1, block: b)) {
              add(hit);
            }
          }
        }
      },
      onJump: (h) => _jumpTo(h.page - 1, h.block),
    );
  }

  Future<void> _showHighlights() async {
    final epub = _epub;
    if (epub == null) return;
    final t = ref.read(stringsProvider);
    await showHighlightsSheet(
      context,
      bookId: widget.book.id,
      emptyText: t.highlightsEmpty,
      locationOf: (h) => epub.titleOf(h.page - 1) ?? t.section(h.page),
      onJump: (h) => _jumpTo(h.page - 1, h.block),
    );
  }

  // ---- contents ----

  Future<void> _showContents() async {
    final epub = _epub;
    if (epub == null) return;
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final entries = epub.toc.isNotEmpty
        ? epub.toc
        : [for (var i = 0; i < epub.chapterCount; i++) EpubTocEntry(title: t.section(i + 1), chapter: i)];
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, scroll) => ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
          itemCount: entries.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(t.contents, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: ref.read(settingsProvider).hindiScale)),
              );
            }
            final e = entries[i - 1];
            final current = e.chapter == _chapter;
            return ListTile(
              dense: e.depth > 0,
              contentPadding: EdgeInsets.only(left: 16.0 + 18 * e.depth, right: 16),
              title: Text(
                e.title,
                style: EnglishText.body(current ? c.accent : c.ink, size: e.depth > 0 ? 15 : 16.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(ctx, e.chapter),
            );
          },
        ),
      ),
    );
    if (picked != null && picked != _chapter) {
      if (_bookMode) {
        unawaited(_goToBookPage(picked, 0));
      } else {
        _pager?.jumpToPage(picked);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final tooltip = ref.watch(readerControllerProvider);
    final highlights = ref.watch(highlightsProvider(widget.book.id)).valueOrNull ?? const <Highlight>[];
    if (tooltip == null && _portal.isShowing) {
      _afterLayout(() {
        if (_portal.isShowing && ref.read(readerControllerProvider) == null) _portal.hide();
      });
    }
    final epub = _epub;
    final bookMode = ref.watch(settingsProvider.select((s) => s.bookPages));
    // A page for the habit log: a chapter's page when paged, else the chapter.
    if (epub != null) trackPage(bookMode ? _chapter * 100000 + _bookPage : _chapter);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (epub != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('${_chapter + 1} / ${epub.chapterCount}', style: EnglishText.label(c.inkMuted))),
            ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: t.search,
            onPressed: epub == null ? null : () => unawaited(_showSearch()),
          ),
          BookmarkButton(
            marked: _bookmarksHere(ref.watch(bookmarksProvider(widget.book.id)).valueOrNull ?? const []).isNotEmpty,
            onPressed: epub == null ? null : () => unawaited(_toggleBookmark()),
          ),
          IconButton(
            icon: const Icon(Icons.toc_rounded),
            tooltip: t.contents,
            onPressed: epub == null ? null : _showContents,
          ),
          IconButton(
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: t.readingSettings,
            onPressed: () => showReadingSettingsSheet(context),
          ),
          const AiLookupButton(),
          ReaderMoreMenu(
            onWords: () => context.push(Uri(path: '/vocabulary', queryParameters: {'book': '${widget.book.id}', 'title': widget.book.title}).toString()),
            onHighlights: epub == null ? null : _showHighlights,
            onBookmarks: epub == null
                ? null
                : () => showBookmarksSheet(context, bookId: widget.book.id, onJump: (b) => _jumpTo(b.page - 1, b.block)),
            onNote: () => unawaited(_makeCard(const CardDraft(kind: CardKind.idea))),
            onCards: () => context.push(deckRoute((bookId: widget.book.id, bookTitle: widget.book.title))),
            onToggleMode: epub == null ? null : () => unawaited(_toggleMode()),
          ),
        ],
      ),
      body: ReaderGuide(
        child: epub == null
          ? Center(
              child: _openFailed
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(t.epubOpenFailed, style: uiBody(hindi: t.isHindi, color: c.inkMuted), textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : LayoutBuilder(
              builder: (ctx, box) {
                if (bookMode) {
                  _syncPagingKey(Size(box.maxWidth, math.max(0, box.maxHeight - _pageTopInset - _pageBottomInset)), MediaQuery.textScalerOf(ctx));
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _ensurePaging();
                  });
                }
                final here = _paging[_chapter];
                final pageView =
                    NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollEndNotification && n.metrics.axis == Axis.vertical) _onScrollEnd(n.metrics);
                    // The follower's above/below decision tracks the anchor.
                    if (n is ScrollUpdateNotification && tooltip != null) _afterLayout(() => setState(() {}));
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pager,
                    physics: bookMode ? const NeverScrollableScrollPhysics() : null,
                    itemCount: epub.chapterCount,
                    onPageChanged: _onChapterChanged,
                    itemBuilder: (_, i) => _ChapterView(
                      key: ValueKey(i),
                      epub: epub,
                      chapter: i,
                      initialOffset: i == _restoreChapter ? _restoreOffset : 0,
                      jumpToBlock: !bookMode && i == _jumpChapter ? _jumpBlock : null,
                      onJumped: () {
                        _jumpChapter = null;
                        _jumpBlock = null;
                      },
                      active: _active?.chapter == i ? _active : null,
                      // An existing highlight shows itself; only a new selection needs the band.
                      selection: _editing == null && _selection?.at.chapter == i ? _selection : null,
                      highlights: [
                        for (final h in highlights)
                          if (h.page == i + 1 && h.block != null) h,
                      ],
                      tooltip: tooltip,
                      link: _link,
                      mounted: i == _chapter ? _mounted : null,
                      onTap: _onBlockTap,
                      onPressStart: _onPressStart,
                      onPressMove: _onPressMove,
                      onPressEnd: _onPressEnd,
                      onTapOutside: _dismiss,
                      onActiveUnmounted: _onActiveBlockUnmounted,
                      book: bookMode
                          ? (pages: _paging[i], page: i == _chapter ? _bookPage : 0, height: _viewport.height, onEdgeTap: ({required next}) => unawaited(_bookPager.turn(forward: next)))
                          : null,
                    ),
                  ),
                )
                ;
                return Stack(
                  children: [
                    if (bookMode)
                      BookPager(
                        controller: _bookPager,
                        enabled: here != null,
                        position: (_chapter, _bookPage),
                        hasNext: here != null && (_bookPage + 1 < here.count || _chapter + 1 < epub.chapterCount),
                        hasPrevious: here != null && (_bookPage > 0 || _chapter > 0),
                        paper: c.paper,
                        snapshot: _bookSnapshot,
                        onTurn: _turnBook,
                        canStart: () => _selection == null && _editing == null,
                        child: ColoredBox(
                          color: c.paper,
                          child: Padding(padding: const EdgeInsets.only(top: _pageTopInset, bottom: _pageBottomInset), child: pageView),
                        ),
                      )
                    else
                      pageView,
                OverlayPortal(
                  controller: _portal,
                  overlayChildBuilder: (_) => TooltipFollower(
                    tooltip: tooltip,
                    link: _link,
                    anchorOnScreen: tooltip == null ? Rect.zero : _anchorOnScreen(tooltip.anchor),
                    bookId: widget.book.id,
                    bookTitle: widget.book.title,
                    onShowDetails: _showDetails,
                    onSuggestion: _lookupTyped,
                    onTranslateSentence: _translateSentence,
                    highlightActions: HighlightActions(
                      onColor: _pickColor,
                      onRemove: _removeHighlight,
                      onTranslate: _translateSelection,
                      onCopied: (_) => _dismiss(),
                      onSentenceColor: _highlightSentence,
                    ),
                    onMakeCard: (d) => unawaited(_makeCard(d)),
                  ),
                ),
                  ],
                );
              },
            ),
      ),
    );
  }
}

// ---- block styling (shared by the widgets and the jump-offset estimate) ----

typedef _BlockStyle = ({TextStyle base, EdgeInsets padding, TextAlign align});

_BlockStyle _styleFor(EpubBlock b, {required bool first, required ArthColors c}) {
  final body = BookText.body(c.ink);
  return switch (b.kind) {
    BlockKind.heading => (
        base: BookText.heading(c.ink, size: switch (b.level) { 1 => 26, 2 => 22, 3 => 19.5, _ => 18 }),
        padding: EdgeInsets.only(top: first ? 8 : 28, bottom: 12),
        align: b.level <= 2 ? TextAlign.center : TextAlign.start,
      ),
    BlockKind.quote => (
        base: body.copyWith(fontStyle: FontStyle.italic, fontSize: 16.5),
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 10),
        align: TextAlign.start,
      ),
    BlockKind.pre => (
        base: TextStyle(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier'], fontSize: 14, height: 1.5, color: c.ink),
        padding: const EdgeInsets.symmetric(vertical: 6),
        align: TextAlign.start,
      ),
    BlockKind.listItem => (base: body, padding: const EdgeInsets.only(left: 6, bottom: 6), align: TextAlign.start),
    BlockKind.paragraph => (base: body, padding: const EdgeInsets.only(bottom: 11), align: TextAlign.start),
  };
}

TextSpan _spanFor(EpubBlock b, TextStyle base) => TextSpan(
      style: base,
      children: [
        for (final r in b.runs)
          TextSpan(
            text: r.text,
            style: r.italic || r.bold
                ? TextStyle(
                    fontStyle: r.italic ? FontStyle.italic : null,
                    fontWeight: r.bold ? FontWeight.w600 : null,
                  )
                : null,
          ),
      ],
    );

/// Width the bullet column takes off a list item's text.
const _bulletWidth = 22.0;

/// The list offset of [target], by laying the blocks before it out the same
/// way the render objects will. Exact for the same width and text scale.
double _offsetOfBlock(List<EpubBlock> blocks, int target, {required double width, required TextScaler scaler, required ArthColors c}) {
  var y = _pagePadding.top;
  final painter = TextPainter(textDirection: TextDirection.ltr, textScaler: scaler);
  for (var i = 0; i < target && i < blocks.length; i++) {
    final b = blocks[i];
    final s = _styleFor(b, first: i == 0, c: c);
    painter
      ..text = _spanFor(b, s.base)
      ..textAlign = s.align
      ..layout(maxWidth: width - _pagePadding.horizontal - s.padding.horizontal - (b.kind == BlockKind.listItem ? _bulletWidth : 0));
    y += s.padding.vertical + painter.height;
  }
  painter.dispose();
  return y;
}


// ---- pages (book mode) ----
//
// Book mode cuts each chapter into screen-sized pages at line boundaries. A
// page is a window onto the chapter's own scrolling column: the column is
// moved (by jumping its scroll offset) to where the page starts and clipped
// where it ends, so everything built for scrolling — tapping words, the
// tooltip, highlights — works unchanged.

/// Where each page of a chapter starts and ends, as scroll offsets.
class _ChapterPages {
  const _ChapterPages(this.starts, this.ends);

  final List<double> starts;
  final List<double> ends;

  int get count => starts.length;

  /// The page showing scroll offset [y].
  int pageAt(double y) {
    var page = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] <= y + 0.5) page = i;
    }
    return page;
  }
}

/// Space above and below the text of a page.
const double _pageTopInset = 12;
const double _pageBottomInset = 24;

/// A page window is lifted this much so the first line's tallest letters
/// aren't clipped and none of the next line's show.
const double _windowLift = 1.5;

/// Each line of a laid-out painter: its line box (extra line height
/// included, so boxes tile exactly; for choosing where to break) and the
/// tight span of its glyphs (so a page window shows no sliver of the line
/// above or below).
typedef _Line = ({double top, double bottom, double inkTop, double inkBottom});

List<_Line> _lineBoxes(TextPainter painter) {
  final metrics = painter.computeLineMetrics();
  final length = painter.text?.toPlainText().length ?? 0;
  final out = <_Line>[];
  var pos = 0;
  while (pos < length) {
    final end = math.min(math.max(painter.getLineBoundary(TextPosition(offset: pos)).end, pos + 1), length);
    final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: pos, extentOffset: end), boxHeightStyle: ui.BoxHeightStyle.max);
    pos = end;
    if (boxes.isEmpty) continue;
    var top = double.infinity;
    var bottom = -double.infinity;
    for (final box in boxes) {
      top = math.min(top, box.top);
      bottom = math.max(bottom, box.bottom);
    }
    final i = out.length;
    final m = i < metrics.length ? metrics[i] : null;
    out.add((top: top, bottom: bottom, inkTop: m == null ? top : m.baseline - m.ascent, inkBottom: m == null ? bottom : m.baseline + m.descent));
  }
  if (out.isEmpty) return [(top: 0, bottom: painter.height, inkTop: 0, inkBottom: painter.height)];
  final first = out.first;
  final last = out.last;
  // The block's first line starts at its top and its last ends at its bottom.
  out[0] = (top: 0, bottom: first.bottom, inkTop: math.min(first.inkTop, 0), inkBottom: first.inkBottom);
  out[out.length - 1] = (top: last.top, bottom: painter.height, inkTop: last.inkTop, inkBottom: math.max(last.inkBottom, painter.height));
  return out;
}

/// Cuts [blocks] into pages of [height], at the top of the first line that
/// doesn't fit. Lays the text out as the render objects will.
_ChapterPages _paginate(List<EpubBlock> blocks, {required double width, required double height, required TextScaler scaler, required ArthColors c}) {
  final starts = <double>[0];
  final ends = <double>[];
  var y = _pagePadding.top;
  var lastInkBottom = y;
  final painter = TextPainter(textDirection: TextDirection.ltr, textScaler: scaler);
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final s = _styleFor(b, first: i == 0, c: c);
    painter
      ..text = _spanFor(b, s.base)
      ..textAlign = s.align
      ..layout(maxWidth: width - _pagePadding.horizontal - s.padding.horizontal - (b.kind == BlockKind.listItem ? _bulletWidth : 0));
    final top = y + s.padding.top;
    for (final line in _lineBoxes(painter)) {
      if (top + line.bottom > starts.last + height + 0.5 && top + line.top > starts.last + 0.5) {
        ends.add(lastInkBottom - _windowLift);
        starts.add(top + line.inkTop - _windowLift);
      }
      lastInkBottom = top + line.inkBottom;
    }
    y = top + painter.height + s.padding.bottom;
  }
  painter.dispose();
  ends.add(math.min(math.max(lastInkBottom, y - 1), starts.last + height));
  return _ChapterPages(starts, ends);
}

/// Draws page [page] of a chapter the way the live column shows it, for the
/// curl's picture of a page that isn't on screen. [origin] is where the
/// viewport sits in the picture.
void _paintPage(
  Canvas canvas, {
  required List<EpubBlock> blocks,
  required _ChapterPages pages,
  required int page,
  required double width,
  required Offset origin,
  required TextScaler scaler,
  required ArthColors c,
}) {
  final start = pages.starts[page];
  final end = pages.ends[page];
  canvas
    ..save()
    ..clipRect(Rect.fromLTWH(origin.dx, origin.dy, width, end - start));
  var y = _pagePadding.top;
  final painter = TextPainter(textDirection: TextDirection.ltr, textScaler: scaler);
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final s = _styleFor(b, first: i == 0, c: c);
    final bullet = b.kind == BlockKind.listItem ? _bulletWidth : 0.0;
    painter
      ..text = _spanFor(b, s.base)
      ..textAlign = s.align
      ..layout(maxWidth: width - _pagePadding.horizontal - s.padding.horizontal - bullet);
    final top = y;
    y += s.padding.vertical + painter.height;
    if (y < start) continue;
    if (top > end) break;
    final dy = origin.dy + top + s.padding.top - start;
    painter.paint(canvas, Offset(origin.dx + _pagePadding.left + s.padding.left + bullet, dy));
    if (bullet > 0) {
      TextPainter(text: TextSpan(text: '•', style: s.base), textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout()
        ..paint(canvas, Offset(origin.dx + _pagePadding.left + s.padding.left, dy))
        ..dispose();
    }
  }
  painter.dispose();
  canvas.restore();
}

class _PageClip extends CustomClipper<Rect> {
  const _PageClip(this.height);

  final double height;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, height);

  @override
  bool shouldReclip(_PageClip old) => old.height != height;
}

/// What the chapter view needs to show a page rather than a scrolling column.
typedef _BookView = ({_ChapterPages? pages, int page, double height, void Function({required bool next}) onEdgeTap});

class _ChapterView extends ConsumerStatefulWidget {
  const _ChapterView({
    required this.epub,
    required this.chapter,
    required this.initialOffset,
    required this.jumpToBlock,
    required this.onJumped,
    required this.active,
    required this.selection,
    required this.highlights,
    required this.tooltip,
    required this.link,
    required this.mounted,
    required this.onTap,
    required this.onPressStart,
    required this.onPressMove,
    required this.onPressEnd,
    required this.onTapOutside,
    required this.onActiveUnmounted,
    required this.book,
    super.key,
  });

  /// Non-null in book mode.
  final _BookView? book;
  final ReflowBook epub;
  final int chapter;
  final double initialOffset;
  final int? jumpToBlock;
  final VoidCallback onJumped;
  final _BlockRef? active;
  final _WordRange? selection;
  final List<Highlight> highlights;
  final ReaderTooltip? tooltip;
  final LayerLink link;
  final Map<int, GlobalKey>? mounted;
  final void Function(_BlockRef at, RenderParagraphBlock render, Offset local) onTap;
  final void Function(_BlockRef at, RenderParagraphBlock render, Offset local) onPressStart;
  final void Function(_BlockRef at, RenderParagraphBlock render, Offset local) onPressMove;
  final void Function(_BlockRef at, RenderParagraphBlock render) onPressEnd;
  final VoidCallback onTapOutside;
  final VoidCallback onActiveUnmounted;

  @override
  ConsumerState<_ChapterView> createState() => _ChapterViewState();
}

class _ChapterViewState extends ConsumerState<_ChapterView> {
  late final ScrollController _scroll = ScrollController(initialScrollOffset: widget.book == null ? widget.initialOffset : 0);
  List<EpubBlock>? _blocks;
  bool _failed = false;

  /// Book mode: the offset the column has been moved to, and whether the
  /// first page has been placed yet (until then nothing shows).
  double? _placedAt;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final blocks = await widget.epub.chapter(widget.chapter);
      if (mounted) setState(() => _blocks = blocks);
    } on Exception {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _jump(List<EpubBlock> blocks, int block, double width) {
    widget.onJumped();
    final c = context.colors;
    final scaler = MediaQuery.textScalerOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final y = _offsetOfBlock(blocks, block, width: width, scaler: scaler, c: c) - 24;
      _scroll.jumpTo(y.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  /// Book mode: move the column so [page] is at the top.
  void _place(_ChapterPages pages, int page) {
    final target = pages.starts[page];
    if (_placedAt == target) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
        setState(() {}); // not laid out yet: look again next frame
        return;
      }
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
      setState(() {
        _placedAt = target;
        _revealed = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final blocks = _blocks;
    if (blocks == null) {
      return Center(
        child: _failed ? Text(t.epubChapterFailed, style: uiBody(hindi: t.isHindi, color: c.inkMuted)) : const CircularProgressIndicator(),
      );
    }
    if (blocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t.epubChapterEmpty, style: uiBody(hindi: t.isHindi, color: c.inkMuted), textAlign: TextAlign.center),
        ),
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    final brightness = Theme.of(context).brightness;
    final sel = widget.selection;
    final book = widget.book;

    Widget blockAt(int i) {
      final at = (chapter: widget.chapter, block: i);
      final isActive = widget.active == at;
      final ranges = [
        for (final h in widget.highlights)
          if (h.block == i) PaintedRange(startWord: h.startWord, endWord: h.endWord, color: HighlightPalette.fill(h.color, brightness)),
        if (sel != null && sel.at == at) PaintedRange(startWord: sel.start, endWord: sel.end, color: c.highlight),
      ];
      return _Block(
        key: ValueKey(i),
        block: blocks[i],
        first: i == 0,
        textScaler: scaler,
        ranges: ranges,
        tooltip: isActive ? widget.tooltip : null,
        link: widget.link,
        registry: widget.mounted,
        registryIndex: i,
        onTap: (render, local) => widget.onTap(at, render, local),
        onPressStart: (render, local) => widget.onPressStart(at, render, local),
        onPressMove: (render, local) => widget.onPressMove(at, render, local),
        onPressEnd: (render) => widget.onPressEnd(at, render),
        onUnmounted: isActive ? widget.onActiveUnmounted : null,
      );
    }

    return LayoutBuilder(
      builder: (_, constraints) {
        if (book != null) {
          // A page at a time: the whole column is built (so its extents are
          // exact), moved to the page's start and clipped at its end.
          final pages = book.pages;
          final page = pages == null ? 0 : book.page.clamp(0, pages.count - 1);
          if (pages != null) _place(pages, page);
          final window = pages == null ? book.height : pages.ends[page] - pages.starts[page];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Empty space beside the text turns the page; the middle lets go.
            onTapUp: (d) {
              final x = d.localPosition.dx / constraints.maxWidth;
              if (x < 0.22) {
                book.onEdgeTap(next: false);
              } else if (x > 0.78) {
                book.onEdgeTap(next: true);
              } else {
                widget.onTapOutside();
              }
            },
            child: Opacity(
              opacity: _revealed ? 1 : 0,
              child: ClipRect(
                clipper: _PageClip(window),
                child: SingleChildScrollView(
                  controller: _scroll,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(_pagePadding.left, _pagePadding.top, _pagePadding.right, book.height),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < blocks.length; i++) blockAt(i)]),
                ),
              ),
            ),
          );
        }
        final jump = widget.jumpToBlock;
        if (jump != null) _jump(blocks, jump, constraints.maxWidth);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTapOutside,
          child: ListView.builder(
            controller: _scroll,
            physics: const FlickBoostPhysics(),
            padding: _pagePadding,
            itemCount: blocks.length,
            itemBuilder: (_, i) => blockAt(i),
          ),
        );
      },
    );
  }
}

class _Block extends StatefulWidget {
  const _Block({
    required this.block,
    required this.first,
    required this.textScaler,
    required this.ranges,
    required this.tooltip,
    required this.link,
    required this.registry,
    required this.registryIndex,
    required this.onTap,
    required this.onPressStart,
    required this.onPressMove,
    required this.onPressEnd,
    required this.onUnmounted,
    super.key,
  });

  final EpubBlock block;
  final bool first;
  final TextScaler textScaler;
  final List<PaintedRange> ranges;

  /// Non-null only for the block the tooltip is on.
  final ReaderTooltip? tooltip;
  final LayerLink link;
  final Map<int, GlobalKey>? registry;
  final int registryIndex;
  final void Function(RenderParagraphBlock render, Offset local) onTap;
  final void Function(RenderParagraphBlock render, Offset local) onPressStart;
  final void Function(RenderParagraphBlock render, Offset local) onPressMove;
  final void Function(RenderParagraphBlock render) onPressEnd;
  final VoidCallback? onUnmounted;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.registry?[widget.registryIndex] = _key;
  }

  @override
  void didUpdateWidget(_Block old) {
    super.didUpdateWidget(old);
    if (old.registry != widget.registry) {
      if (old.registry?[widget.registryIndex] == _key) old.registry?.remove(widget.registryIndex);
      widget.registry?[widget.registryIndex] = _key;
    }
  }

  @override
  void dispose() {
    if (widget.registry?[widget.registryIndex] == _key) widget.registry?.remove(widget.registryIndex);
    widget.onUnmounted?.call();
    super.dispose();
  }

  RenderParagraphBlock? get _render {
    final r = _key.currentContext?.findRenderObject();
    return r is RenderParagraphBlock && r.hasSize ? r : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = widget.block;
    final s = _styleFor(b, first: widget.first, c: c);

    Widget text = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final r = _render;
        if (r != null) widget.onTap(r, d.localPosition);
      },
      onLongPressStart: (d) {
        final r = _render;
        if (r != null) widget.onPressStart(r, d.localPosition);
      },
      onLongPressMoveUpdate: (d) {
        final r = _render;
        if (r != null) widget.onPressMove(r, d.localPosition);
      },
      onLongPressEnd: (_) {
        final r = _render;
        if (r != null) widget.onPressEnd(r);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ParagraphText(key: _key, span: _spanFor(b, s.base), textScaler: widget.textScaler, textAlign: s.align, ranges: widget.ranges),
          ...tooltipOverlays(context: context, tooltip: widget.tooltip, link: widget.link, toLocal: (r) => r),
        ],
      ),
    );
    if (b.kind == BlockKind.listItem) {
      text = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: _bulletWidth, child: Text('•', style: s.base)),
          Expanded(child: text),
        ],
      );
    }
    return Padding(padding: s.padding, child: text);
  }
}
