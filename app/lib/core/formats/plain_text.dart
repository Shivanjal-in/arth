// Plain text → blocks. Most .txt books are Project Gutenberg files: prose
// hard-wrapped at ~70 columns, paragraphs separated by a blank line, chapter
// headings on a line of their own, `_underscores_` for italics, and a licence
// header and footer around the book.

import 'package:arth/core/epub/epub_html.dart';

final _gutenbergStart = RegExp(r'^\*{3}\s*START OF (THE|THIS) PROJECT GUTENBERG.*$', multiLine: true, caseSensitive: false);
final _gutenbergEnd = RegExp(r'^\*{3}\s*END OF (THE|THIS) PROJECT GUTENBERG.*$', multiLine: true, caseSensitive: false);
final _gutenbergTitle = RegExp(r'^Title:\s*(.+)$', multiLine: true);

// "Chapter 4", "CHAPTER IV.", "Book the First", "Part two: The Voyage".
final _chapterHeading = RegExp(
  r'^(chapter|book|part|volume|act|scene|stave|canto|letter)\s+'
  r'([0-9]+|[ivxlcdm]+|the \w+|(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|'
  r'sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|first|second|third|fourth|fifth|last)(-\w+)?)'
  r'(\s*[.:\-—].*)?$',
  caseSensitive: false,
);
final _namedHeading = RegExp(r'^(prologue|epilogue|preface|introduction|foreword|afterword)\.?$', caseSensitive: false);
final _romanHeading = RegExp(r'^[IVXLC]+\.?$');

/// Whether a line on its own reads as a chapter heading: "CHAPTER IV.",
/// "Chapter 2: The Visit", "Prologue", "XII".
bool isChapterHeading(String line) =>
    line.length <= 80 && (_chapterHeading.hasMatch(line) || _namedHeading.hasMatch(line) || _romanHeading.hasMatch(line));

final _italic = RegExp('_([^_]+)_');
final _blankLine = RegExp(r'\n[ \t]*\n');

({String? title, List<EpubBlock> blocks}) parsePlainText(String source) {
  var text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  String? title;
  final start = _gutenbergStart.firstMatch(text);
  if (start != null) {
    title = _gutenbergTitle.firstMatch(text.substring(0, start.start))?.group(1)?.trim();
    text = text.substring(start.end);
  }
  final end = _gutenbergEnd.firstMatch(text);
  if (end != null) text = text.substring(0, end.start);
  // A title line at the very top (outside Gutenberg's header too) names the
  // book; it isn't text to read.
  final leading = RegExp(r'^\s*Title:[ \t]*(.+)\n').firstMatch(text);
  if (leading != null) {
    title ??= leading.group(1)!.trim();
    text = text.substring(leading.end);
  }

  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).length;
  final paragraphs = _blankLine.allMatches(text).length;
  // No blank lines to speak of: the file puts one paragraph on each line.
  final lineParagraphs = paragraphs == 0 || (lines > 20 && paragraphs < lines / 20);
  final chunks = lineParagraphs ? text.split('\n') : text.split(_blankLine);

  final out = BlockBuilder();
  for (final chunk in chunks) {
    final trimmed = chunk.trim();
    if (trimmed.isEmpty) continue;
    final oneLine = !trimmed.contains('\n');
    if (oneLine && isChapterHeading(trimmed)) {
      out
        ..kind = BlockKind.heading
        ..level = 2
        ..write(trimmed, bold: true)
        ..flush()
        ..kind = BlockKind.paragraph
        ..level = 0;
      continue;
    }
    // Indented lines are verse or a letter's layout: keep the breaks.
    final verse = !oneLine && chunk.split('\n').where((l) => l.trim().isNotEmpty).every((l) => l.startsWith('  '));
    if (verse) {
      final lines = chunk.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) out.write('\n', pre: true);
        _writeInline(out, lines[i]);
      }
      out.flush();
      continue;
    }
    _writeInline(out, trimmed.replaceAll('\n', ' '));
    out.flush();
  }
  return (title: title, blocks: out.blocks);
}

/// Writes [text], turning `_this_` into italics.
void _writeInline(BlockBuilder out, String text) {
  var at = 0;
  for (final m in _italic.allMatches(text)) {
    out
      ..write(text.substring(at, m.start))
      ..write(m.group(1)!, italic: true);
    at = m.end;
  }
  out.write(text.substring(at));
}
