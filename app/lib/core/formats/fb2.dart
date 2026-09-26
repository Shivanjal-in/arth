// FictionBook (.fb2, and .fb2.zip) → blocks. FB2 is one XML file built for
// books: `<body>` holds nested `<section>`s, each with a `<title>` and
// `<p>`aragraphs, plus poems, epigraphs and citations. A section's depth
// becomes its heading level. Footnotes live in a second `<body name="notes">`
// and are left out, as are the note references in the text.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:arth/core/formats/text_decode.dart';
import 'package:xml/xml.dart';

final _xmlEncoding = RegExp(r'''^<\?xml[^>]*encoding=["']([^"']+)["']''');

({String? title, List<EpubBlock> blocks}) parseFb2(List<int> bytes) {
  final head = latin1.decode(bytes.take(200).toList());
  final source = decodeWithCharset(bytes, _xmlEncoding.firstMatch(head.trimLeft())?.group(1));
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(source.startsWith('﻿') ? source.substring(1) : source, entityMapping: const XmlDefaultEntityMapping.html5());
  } on XmlException catch (e) {
    throw EpubFormatException('bad FB2 XML: $e');
  }
  final title = doc.findAllElements('book-title', namespaceUri: '*').firstOrNull?.innerText.trim();
  final w = _Walker();
  for (final body in doc.rootElement.childElements.where((e) => e.localName == 'body')) {
    if (body.getAttribute('name') == 'notes' || body.getAttribute('name') == 'comments') continue;
    w.section(body, 0);
  }
  return (title: title, blocks: w.out.blocks);
}

/// A zip holding one .fb2 file.
({String? title, List<EpubBlock> blocks}) parseFb2Zip(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } on Exception catch (e) {
    throw EpubFormatException('not a zip: $e');
  }
  final entry = zip.files.where((f) => f.isFile && f.name.toLowerCase().endsWith('.fb2')).firstOrNull;
  if (entry == null) throw EpubFormatException('no .fb2 in the zip');
  return parseFb2(entry.readBytes() ?? const []);
}

class _Walker {
  final out = BlockBuilder();

  /// A `<body>` or `<section>` at [depth] (body is 0; its sections are 1).
  void section(XmlElement s, int depth) {
    for (final child in s.childElements) {
      switch (child.localName) {
        case 'title':
          _title(child, depth);
        case 'section':
          section(child, depth + 1);
        case 'epigraph' || 'cite':
          _blocks(child, BlockKind.quote);
        default:
          _block(child, BlockKind.paragraph);
      }
    }
  }

  /// A title's lines ("Chapter 1", "The Beginning") make one heading, one
  /// line each. The body's own title is the book's: level 1, like a section.
  void _title(XmlElement t, int depth) {
    out
      ..flush()
      ..kind = BlockKind.heading
      ..level = depth.clamp(1, 6);
    var first = true;
    for (final p in t.childElements.where((e) => e.localName == 'p')) {
      if (!first) out.write('\n', bold: true, pre: true);
      first = false;
      _inline(p, italic: false, bold: true);
    }
    out
      ..flush()
      ..kind = BlockKind.paragraph
      ..level = 0;
  }

  /// The block-level children of an epigraph, cite or poem.
  void _blocks(XmlElement parent, BlockKind kind) {
    for (final child in parent.childElements) {
      _block(child, kind);
    }
  }

  void _block(XmlElement e, BlockKind kind) {
    switch (e.localName) {
      case 'p' || 'v' || 'text-author':
        _paragraph(e, kind, italic: e.localName == 'text-author');
      case 'subtitle':
        out
          ..flush()
          ..kind = BlockKind.heading
          ..level = 6;
        _inline(e, italic: false, bold: true);
        out
          ..flush()
          ..kind = BlockKind.paragraph
          ..level = 0;
      case 'poem' || 'stanza':
        // A stanza is one block, its verses on their own lines.
        if (e.localName == 'stanza') {
          _stanza(e, kind);
        } else {
          _blocks(e, kind == BlockKind.paragraph ? BlockKind.quote : kind);
        }
      case 'title':
        // A poem's or stanza's title.
        _paragraph(e, kind, bold: true);
      case 'epigraph' || 'cite':
        _blocks(e, BlockKind.quote);
      case 'table':
        for (final row in e.childElements) {
          _paragraph(row, kind);
        }
      // image, empty-line, annotation: nothing to read.
    }
  }

  void _stanza(XmlElement stanza, BlockKind kind) {
    out
      ..flush()
      ..kind = kind;
    var first = true;
    for (final v in stanza.childElements.where((e) => e.localName == 'v')) {
      if (!first) out.write('\n', pre: true);
      first = false;
      _inline(v, italic: false, bold: false);
    }
    out
      ..flush()
      ..kind = BlockKind.paragraph;
  }

  void _paragraph(XmlElement p, BlockKind kind, {bool italic = false, bool bold = false}) {
    out
      ..flush()
      ..kind = kind;
    _inline(p, italic: italic, bold: bold);
    out
      ..flush()
      ..kind = BlockKind.paragraph;
  }

  void _inline(XmlElement parent, {required bool italic, required bool bold}) {
    for (final node in parent.children) {
      if (node is XmlText || node is XmlCDATA) {
        out.write(node.value ?? '', italic: italic, bold: bold);
      } else if (node is XmlElement) {
        switch (node.localName) {
          case 'emphasis':
            _inline(node, italic: true, bold: bold);
          case 'strong':
            _inline(node, italic: italic, bold: true);
          case 'a' when node.getAttribute('type') == 'note':
            break; // a footnote marker: "[1]"
          case 'image':
            break;
          case 'td' || 'th':
            out.write(' ', italic: italic, bold: bold);
            _inline(node, italic: italic, bold: bold);
          default:
            _inline(node, italic: italic, bold: bold);
        }
      }
    }
  }
}
