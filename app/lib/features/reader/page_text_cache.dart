// Lazily builds a PageTextIndex per page, in document coordinates, and
// stitches sentences that run across page boundaries.

import 'dart:async';
import 'dart:ui';

import 'package:arth/core/normalize.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:pdfrx/pdfrx.dart';

class PageTextCache {
  PageTextCache(this.controller);

  final PdfViewerController controller;
  final Map<int, Future<PageTextIndex>> _pages = {};

  static const _pageBreak = '';

  Future<PageTextIndex> page(int pageNumber) => _pages.putIfAbsent(pageNumber, () async {
        final idx = await _build(pageNumber);
        // An empty page may only mean it wasn't loaded yet: ask again next
        // time rather than remembering it as blank.
        if (idx.words.isEmpty) unawaited(_pages.remove(pageNumber));
        return idx;
      });

  Future<PageTextIndex> _build(int pageNumber) async {
    // Long PDFs load progressively: until a page is really loaded pdfrx
    // gives empty text and guessed page sizes, with no error.
    final page = await controller.pages[pageNumber - 1].waitForLoaded(timeout: const Duration(seconds: 15));
    if (page == null) return PageTextIndex.build('', const []);
    final text = await page.loadStructuredText();
    final rects = <Rect>[
      for (final r in text.charRects)
        r.isEmpty
            ? Rect.zero
            : controller.calcRectForRectInsidePage(pageNumber: pageNumber, rect: r),
    ];
    return PageTextIndex.build(text.fullText, rects);
  }

  /// Which page a document-space point falls on (1-based), or null.
  int? pageAt(Offset documentPosition) {
    final layouts = controller.layout.pageLayouts;
    for (var i = 0; i < layouts.length; i++) {
      if (layouts[i].contains(documentPosition)) return i + 1;
    }
    return null;
  }

  /// The normalized sentence containing [word], joined across the previous /
  /// next page when the sentence runs over the page edge.
  Future<String> sentenceFor(int pageNumber, PageTextIndex idx, PageWord word) async {
    final span = idx.sentenceOf(word.index);
    var raw = idx.rawSentence(span);
    final isFirst = span.firstWord == 0;
    final isLast = span.lastWord == idx.words.length - 1;
    if (isFirst && idx.startsMidSentence && pageNumber > 1) {
      final prev = await page(pageNumber - 1);
      if (prev.words.isNotEmpty && prev.endsMidSentence) {
        raw = '${prev.rawSentence(prev.sentences.last)}$_pageBreak$raw';
      }
    }
    if (isLast && idx.endsMidSentence && pageNumber < controller.pageCount) {
      final next = await page(pageNumber + 1);
      if (next.words.isNotEmpty && next.startsMidSentence) {
        raw = '$raw$_pageBreak${next.rawSentence(next.sentences.first)}';
      }
    }
    return normalizeSentence(raw);
  }

  /// The sentence before the one containing [word], for pronoun context.
  Future<String?> previousSentence(int pageNumber, PageTextIndex idx, PageWord word) async {
    final span = idx.sentenceOf(word.index);
    final i = idx.sentences.indexOf(span);
    if (i > 0) return normalizeSentence(idx.rawSentence(idx.sentences[i - 1]));
    if (pageNumber > 1) {
      final prev = await page(pageNumber - 1);
      if (prev.sentences.isNotEmpty) {
        return normalizeSentence(prev.rawSentence(prev.sentences.last));
      }
    }
    return null;
  }
}
