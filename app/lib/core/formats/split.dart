// One long document → chapters, so the reader pages by chapter the way it
// does an EPUB and the contents sheet has somewhere to jump to.
//
// Chapters start at the document's chapter-level headings: the shallowest
// heading level used more than once (a lone <h1> is the book's title, the
// <h2>s under it are its chapters). A chapter that is still very long — a
// text file with no headings at all — is cut into sections at paragraph
// boundaries.

import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:arth/core/formats/plain_text.dart';

/// Roughly a chapter of a novel; long enough to read, short enough to lay out.
const _maxChapterChars = 40000;

/// Text before the first chapter heading shorter than this (a title line,
/// a dedication) opens chapter one rather than being a chapter of its own.
const _minFrontMatterChars = 400;

({List<List<EpubBlock>> chapters, List<EpubTocEntry> toc}) splitIntoChapters(List<EpubBlock> blocks) {
  final splitLevel = _chapterLevel(blocks);
  final minLevel = blocks.where((b) => b.kind == BlockKind.heading).fold(6, (m, b) => b.level < m ? b.level : m);
  final chapters = <List<EpubBlock>>[];
  final toc = <EpubTocEntry>[];
  var current = <EpubBlock>[];
  var chars = 0;
  // Whether [current] has anything but headings: consecutive headings (a
  // part title then its first chapter's) open one chapter, not two.
  var hasBody = false;
  // No chapter heading seen yet: what's in [current] is front matter.
  var inFrontMatter = true;

  void close() {
    if (current.isNotEmpty) chapters.add(current);
    current = [];
    chars = 0;
    hasBody = false;
  }

  for (final b in blocks) {
    final isSplit = splitLevel != null && b.kind == BlockKind.heading && b.level <= splitLevel;
    final tinyFrontMatter = inFrontMatter && chars < _minFrontMatterChars;
    if (isSplit && hasBody && !tinyFrontMatter) close();
    if (isSplit) inFrontMatter = false;
    if (!isSplit && chars >= _maxChapterChars) close();
    if (isSplit) {
      final label = b.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isNotEmpty) toc.add(EpubTocEntry(title: label, chapter: chapters.length, depth: b.level - minLevel));
    } else if (b.kind != BlockKind.heading) {
      hasBody = true;
    }
    current.add(b);
    chars += b.text.length;
  }
  close();
  return (chapters: chapters, toc: toc);
}

/// A document with no heading styles at all — "Chapter 1" typed as a bold
/// line — gets its chapter lines turned into headings. One that has headings
/// is trusted as it is.
List<EpubBlock> promoteChapterHeadings(List<EpubBlock> blocks) {
  if (blocks.any((b) => b.kind == BlockKind.heading)) return blocks;
  return [
    for (final b in blocks)
      if (b.kind == BlockKind.paragraph && isChapterHeading(b.text))
        EpubBlock(kind: BlockKind.heading, level: 2, runs: [for (final r in b.runs) InlineRun(r.text, italic: r.italic, bold: true)])
      else
        b,
  ];
}

/// The heading level chapters start at, or null when headings are too rare
/// to be chapters.
int? _chapterLevel(List<EpubBlock> blocks) {
  final counts = List.filled(7, 0);
  for (final b in blocks) {
    if (b.kind == BlockKind.heading) counts[b.level.clamp(1, 6)]++;
  }
  var total = 0;
  for (var level = 1; level <= 6; level++) {
    total += counts[level];
    if (total >= 2) return level;
  }
  return null;
}
