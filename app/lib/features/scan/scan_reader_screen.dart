// Reader for photographed pages: the image, OCR'd on the device, with the
// same word tooltip as the PDF reader. Tap a word; the word card's translate
// action handles sentences (no drag-selection on photos).

import 'dart:async';
import 'dart:io';

import 'package:arth/app/dev_hooks.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/normalize.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/ads/interstitials.dart';
import 'package:arth/features/cards/card_editor.dart';
import 'package:arth/features/cards/deck_screen.dart';
import 'package:arth/features/plans/paid_gate.dart';
import 'package:arth/features/reader/details_sheet.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:arth/features/reader/reader_menu.dart';
import 'package:arth/features/reader/tooltip/tooltip_layer.dart';
import 'package:arth/features/scan/scan_pages.dart';
import 'package:arth/features/settings/reading_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ScanReaderScreen extends ConsumerStatefulWidget {
  const ScanReaderScreen({required this.book, super.key, this.initialPage});

  final Book book;

  /// Open at this page (1-based) instead of where the reader left off.
  final int? initialPage;

  @override
  ConsumerState<ScanReaderScreen> createState() => _ScanReaderScreenState();
}

class _ScanReaderScreenState extends ConsumerState<ScanReaderScreen> with AdBreakOnClose {
  late List<String> _pages;
  late final PageController _pager;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pages = ref.read(scanPagesProvider).pagesOf(widget.book);
    _current = ((widget.initialPage ?? widget.book.lastPage) - 1).clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);
    _pager = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _addPage(ScanSource source) async {
    final t = ref.read(stringsProvider);
    if (!await ensurePaid(context, ref, title: t.scanTitlePaid, why: t.scanNeedsPlan)) return;
    final picked = await pickScanImage(source);
    if (picked == null || !mounted) return;
    await ref.read(scanPagesProvider).addPage(widget.book, picked);
    final pages = ref.read(scanPagesProvider).pagesOf(widget.book);
    await ref.read(libraryProvider.notifier).touch(widget.book.id, pageCount: pages.length);
    if (!mounted) return;
    setState(() => _pages = pages);
    unawaited(_pager.animateToPage(pages.length - 1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_pages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('${_current + 1} / ${_pages.length}', style: EnglishText.label(c.inkMuted))),
            ),
          PopupMenuButton<ScanSource>(
            icon: const Icon(Icons.add_a_photo_outlined),
            tooltip: t.addPage,
            onSelected: _addPage,
            itemBuilder: (_) => [
              PopupMenuItem(value: ScanSource.camera, child: Text(t.takePhoto)),
              PopupMenuItem(value: ScanSource.gallery, child: Text(t.chooseFromGallery)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: t.readingSettings,
            onPressed: () => showReadingSettingsSheet(context),
          ),
          const AiLookupButton(),
          ReaderMoreMenu(
            onWords: () => context.push(Uri(path: '/vocabulary', queryParameters: {'book': '${widget.book.id}', 'title': widget.book.title}).toString()),
            onNote: () => unawaited(makeScanCard(context, ref, widget.book, _current + 1, const CardDraft(kind: CardKind.idea))),
            onCards: () => context.push(deckRoute((bookId: widget.book.id, bookTitle: widget.book.title))),
          ),
        ],
      ),
      body: _pages.isEmpty
          ? Center(child: Text(t.scanEmpty, style: uiBody(hindi: t.isHindi, color: c.inkMuted)))
          : PageView.builder(
              controller: _pager,
              itemCount: _pages.length,
              onPageChanged: (i) {
                setState(() => _current = i);
                ref.read(readerControllerProvider.notifier).dismiss();
                // A scan is a few photographed pages, not a book to finish:
                // record progress, but no end-of-book recap.
                unawaited(ref.read(libraryProvider.notifier).reportProgress(widget.book.id, (i + 1) / _pages.length, lastPage: i + 1));
              },
              itemBuilder: (_, i) => _ScanPage(
                key: ValueKey(_pages[i]),
                imagePath: _pages[i],
                pageNumber: i + 1,
                book: widget.book,
              ),
            ),
    );
  }
}

class _ScanPage extends ConsumerStatefulWidget {
  const _ScanPage({required this.imagePath, required this.pageNumber, required this.book, super.key});

  final String imagePath;
  final int pageNumber;
  final Book book;

  @override
  ConsumerState<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<_ScanPage> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _transform = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();
  Size? _imageSize;
  PageTextIndex? _index;
  bool _ocrFailed = false;
  bool _ocrEmpty = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    unawaited(_load());
    DevHooks.on('tapWord', (p) async {
      final idx = _index;
      if (idx == null) return {'ok': false, 'reason': 'not indexed'};
      final key = normalizeWord(p['word'] ?? '');
      final matches = idx.words.where((w) => w.key == key).toList();
      if (matches.isEmpty) return {'ok': false, 'reason': 'word not on page', 'words': idx.words.length};
      await _openWord(idx, matches.first, _fitScale(context.size?.width ?? 400));
      return {'ok': true, 'words': idx.words.length};
    });
    DevHooks.on('state', (_) async {
      final s = ref.read(readerControllerProvider);
      return {
        'tooltip': s?.runtimeType.toString(),
        'words': _index?.words.length,
        'text': _index?.fullText.substring(0, _index!.fullText.length.clamp(0, 120)),
        if (s is WordTooltipState) 'word': {'key': s.key, 'outcome': s.outcome?.runtimeType.toString(), 'context': s.context?.toJson()},
      };
    });
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  void _onTransform() {
    if (mounted && ref.read(readerControllerProvider) != null) setState(() {});
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final size = Size(decoded.width.toDouble(), decoded.height.toDouble());
      decoded.dispose();
      final page = await ref.read(ocrProvider).recognize(widget.imagePath, imageSize: size);
      if (!mounted) return;
      setState(() {
        _imageSize = size;
        _index = page.index();
        _ocrEmpty = page.wordCount == 0;
      });
    } on Exception {
      if (mounted) setState(() => _ocrFailed = true);
    }
  }

  // ---- geometry: image pixels → page-local (fit to width) → screen ----

  double _fitScale(double viewportWidth) => _imageSize == null ? 1 : viewportWidth / _imageSize!.width;

  Rect _toLocal(Rect imageRect, double scale) => Rect.fromLTRB(
        imageRect.left * scale,
        imageRect.top * scale,
        imageRect.right * scale,
        imageRect.bottom * scale,
      );

  Rect _toScreen(Rect localRect) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    return MatrixUtils.transformRect(_transform.value, localRect).shift(origin);
  }

  // ---- taps ----

  Future<void> _onTapUp(TapUpDetails d, double scale) async {
    final idx = _index;
    final rc = ref.read(readerControllerProvider.notifier);
    if (idx == null) return;
    final point = Offset(d.localPosition.dx / scale, d.localPosition.dy / scale);
    final word = idx.wordAt(point, margin: 4);
    if (word == null || word.key.isEmpty) {
      rc.dismiss();
      return;
    }
    await _openWord(idx, word, scale);
  }

  Future<void> _openWord(PageTextIndex idx, PageWord word, double scale) async {
    final span = idx.sentenceOf(word.index);
    final sentence = normalizeSentence(idx.rawSentence(span));
    final around = idx.tokensAround(word.index);
    final offset = word.index - around.index;
    _portal.show();
    await ref.read(readerControllerProvider.notifier).showWord(
          book: (id: widget.book.id, title: widget.book.title),
          word: PageWord(index: word.index, start: word.start, end: word.end, text: word.text, rect: _toLocal(word.rect, scale)),
          page: widget.pageNumber,
          sentence: sentence,
          tokens: around.tokens,
          index: around.index,
          rectsForWindow: (start, count) => [
            for (var i = start; i < start + count; i++)
              if (i + offset >= 0 && i + offset < idx.words.length) _toLocal(idx.words[i + offset].rect, scale),
          ],
        );
  }

  Future<void> _lookupTyped(String word) async {
    final s = ref.read(readerControllerProvider);
    final idx = _index;
    if (s == null || idx == null) return;
    final key = normalizeWord(word);
    final match = idx.words.where((w) => w.key == key).firstOrNull;
    final scale = _fitScale(context.size?.width ?? 400);
    if (match != null) {
      await _openWord(idx, match, scale);
      return;
    }
    final sentence = s is WordTooltipState ? s.sentence : (s as SentenceTooltipState).text;
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final tooltip = ref.watch(readerControllerProvider);
    if (tooltip == null && _portal.isShowing) _portal.hide();
    final size = _imageSize;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (size == null) {
          return Center(
            child: _ocrFailed
                ? Text(t.ocrFailed, style: uiBody(hindi: t.isHindi, color: c.inkMuted))
                : const CircularProgressIndicator(),
          );
        }
        final scale = _fitScale(constraints.maxWidth);
        final localSize = Size(size.width * scale, size.height * scale);
        return Stack(
          children: [
            InteractiveViewer(
              key: _viewerKey,
              transformationController: _transform,
              constrained: false,
              minScale: 1,
              maxScale: 4,
              boundaryMargin: EdgeInsets.only(bottom: constraints.maxHeight / 2),
              child: SizedBox(
                width: localSize.width,
                height: localSize.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _onTapUp(d, scale),
                        child: Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 2200),
                      ),
                    ),
                    ...tooltipOverlays(context: ctx, tooltip: tooltip, link: _link, toLocal: (r) => r),
                  ],
                ),
              ),
            ),
            if (_ocrEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Material(
                  color: c.card,
                  shape: RoundedRectangleBorder(side: BorderSide(color: c.ink, width: 2)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(t.ocrEmpty, style: uiBody(hindi: t.isHindi, color: c.ink)),
                  ),
                ),
              ),
            OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (_) => TooltipFollower(
                tooltip: tooltip,
                link: _link,
                anchorOnScreen: tooltip == null ? Rect.zero : _toScreen(tooltip.anchor),
                bookId: widget.book.id,
                bookTitle: widget.book.title,
                onShowDetails: _showDetails,
                onSuggestion: _lookupTyped,
                onTranslateSentence: _translateSentence,
                onMakeCard: (d) {
                  ref.read(readerControllerProvider.notifier).dismiss();
                  unawaited(makeScanCard(context, ref, widget.book, widget.pageNumber, d));
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Opens the card editor for a draft made on page [page] of a scan.
Future<void> makeScanCard(BuildContext context, WidgetRef ref, Book book, int page, CardDraft draft) async {
  final t = ref.read(stringsProvider);
  final saved = await showCardEditor(
    context,
    draft: draft.at(bookId: book.id, bookTitle: book.title, page: page, location: t.pageLabel(page)),
  );
  if (saved != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.cardSaved), duration: const Duration(seconds: 1)));
  }
}
