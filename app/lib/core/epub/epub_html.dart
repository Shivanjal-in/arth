// XHTML chapter → flat list of text blocks.
//
// An EPUB chapter is HTML; the reader only needs its paragraphs, in order,
// with enough styling to look like a book (headings, emphasis, quotes). Each
// block's text is what the tooltip pipeline sees, so whitespace is collapsed
// the way a browser would render it: one paragraph is one line of text with
// single spaces, and sentence segmentation never crosses a block.
//
// Pure Dart: runs in an isolate, no Flutter imports.

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

enum BlockKind { paragraph, heading, quote, pre, listItem }

/// A run of text with one style.
class InlineRun {
  const InlineRun(this.text, {this.italic = false, this.bold = false});

  final String text;
  final bool italic;
  final bool bold;
}

class EpubBlock {
  const EpubBlock({required this.kind, required this.runs, this.level = 0});

  final BlockKind kind;

  /// Heading level 1–6 for [BlockKind.heading]; 0 otherwise.
  final int level;
  final List<InlineRun> runs;

  String get text => runs.map((r) => r.text).join();
}

const _skipTags = {'script', 'style', 'head', 'title', 'svg', 'math', 'noscript', 'template', 'video', 'audio', 'iframe', 'object'};

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre', 'tr', 'dt', 'dd', 'figcaption', //
  'section', 'article', 'aside', 'header', 'footer', 'nav', 'table', 'thead', 'tbody', 'tfoot', 'ul', 'ol', 'dl',
  'figure', 'hr', 'address', 'details', 'summary', 'body', 'html', 'main', 'caption', 'center',
};

const _headings = {'h1': 1, 'h2': 2, 'h3': 3, 'h4': 4, 'h5': 5, 'h6': 6};

final _whitespace = RegExp(r'[ \t\r\n\f ]+');

/// Parses one chapter's XHTML bytes into blocks. Lenient: real-world EPUBs
/// have unclosed tags and undeclared entities, so this goes through the HTML5
/// parser rather than strict XML.
List<EpubBlock> parseChapterBytes(List<int> bytes) => parseChapterHtml(utf8.decode(bytes, allowMalformed: true));

List<EpubBlock> parseChapterHtml(String source) => parseHtmlDocument(source).blocks;

/// A whole HTML document: its `<title>` and body blocks.
({String? title, List<EpubBlock> blocks}) parseHtmlDocument(String source) {
  final doc = html.parse(source);
  final root = doc.body ?? doc.documentElement;
  final v = _HtmlVisitor();
  if (root != null) v.visit(root, italic: false, bold: false, pre: false);
  v.out.flush();
  final title = doc.querySelector('title')?.text.replaceAll(_whitespace, ' ').trim();
  return (title: title == null || title.isEmpty ? null : title, blocks: v.out.blocks);
}

class _HtmlVisitor {
  final out = BlockBuilder();

  void visit(Node node, {required bool italic, required bool bold, required bool pre}) {
    if (node is Text) {
      out.write(node.data, italic: italic, bold: bold, pre: pre);
      return;
    }
    if (node is! Element) return;
    final tag = node.localName ?? '';
    if (_skipTags.contains(tag)) return;
    switch (tag) {
      case 'br':
        out.write('\n', italic: italic, bold: bold, pre: true);
        return;
      case 'img':
      case 'image':
        return;
      case 'td':
      case 'th':
        out.write(' ', italic: italic, bold: bold);
    }
    if (_blockTags.contains(tag)) {
      out.flush();
      final wasKind = out.kind;
      final wasLevel = out.level;
      out
        ..kind = switch (tag) {
          'blockquote' => BlockKind.quote,
          'pre' => BlockKind.pre,
          'li' || 'dd' => BlockKind.listItem,
          _ when _headings.containsKey(tag) => BlockKind.heading,
          // A container inherits the kind it sits in (a <p> inside a quote).
          _ => wasKind == BlockKind.heading ? BlockKind.paragraph : wasKind,
        }
        ..level = _headings[tag] ?? 0;
      final childPre = pre || tag == 'pre';
      final childBold = bold || _headings.containsKey(tag);
      for (final child in node.nodes) {
        visit(child, italic: italic, bold: childBold, pre: childPre);
      }
      out
        ..flush()
        ..kind = wasKind
        ..level = wasLevel;
      return;
    }
    final childItalic = italic || tag == 'em' || tag == 'i' || tag == 'cite' || tag == 'dfn' || tag == 'var';
    final childBold = bold || tag == 'strong' || tag == 'b';
    for (final child in node.nodes) {
      visit(child, italic: childItalic, bold: childBold, pre: pre);
    }
  }
}

/// Accumulates styled text into blocks, collapsing whitespace the way a
/// browser renders it. Shared by every document format: a parser sets [kind]
/// and [level], [write]s the block's text, and [flush]es at its end.
class BlockBuilder {
  final blocks = <EpubBlock>[];
  final _runs = <InlineRun>[];
  final _buf = StringBuffer();
  bool _italic = false;
  bool _bold = false;

  /// The kind and level the next [flush] gives its block.
  BlockKind kind = BlockKind.paragraph;
  int level = 0;

  /// Whether the last character written was whitespace (for collapsing).
  bool _trailingSpace = true;

  /// Appends [raw] to the current block. Unless [pre], runs of whitespace
  /// collapse to one space; a `\n` written with `pre: true` is a line break.
  void write(String raw, {bool italic = false, bool bold = false, bool pre = false}) {
    String text;
    if (pre) {
      text = raw;
      if (text.isEmpty) return;
      _trailingSpace = _whitespace.hasMatch(text[text.length - 1]);
    } else {
      text = raw.replaceAll(_whitespace, ' ');
      if (text.isEmpty) return;
      if (_trailingSpace && text.startsWith(' ')) text = text.substring(1);
      if (text.isEmpty) return;
      _trailingSpace = text.endsWith(' ');
    }
    if (italic != _italic || bold != _bold) {
      _endRun();
      _italic = italic;
      _bold = bold;
    }
    _buf.write(text);
  }

  void _endRun() {
    if (_buf.isEmpty) return;
    _runs.add(InlineRun(_buf.toString(), italic: _italic, bold: _bold));
    _buf.clear();
  }

  /// Ends the current block; an empty one is dropped.
  void flush() {
    _endRun();
    if (_runs.isNotEmpty) {
      // Trim the block's edges; keep interior runs as they are.
      final first = _runs.first;
      _runs[0] = InlineRun(first.text.trimLeft(), italic: first.italic, bold: first.bold);
      final last = _runs.last;
      _runs[_runs.length - 1] = InlineRun(last.text.trimRight(), italic: last.italic, bold: last.bold);
      final runs = _runs.where((r) => r.text.isNotEmpty).toList();
      if (runs.isNotEmpty) blocks.add(EpubBlock(kind: kind, level: level, runs: runs));
    }
    _runs.clear();
    _trailingSpace = true;
  }
}
