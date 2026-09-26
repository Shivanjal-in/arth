// Word (.docx) → blocks. The file is a zip; the text is `word/document.xml`:
// `<w:p>` paragraphs of `<w:r>` runs of `<w:t>` text. Headings are
// paragraphs whose style (in `word/styles.xml`) is "heading N" or carries an
// outline level; bold and italic come from the run, its character style, or
// the paragraph's style, nearest first.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:xml/xml.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

({String? title, List<EpubBlock> blocks}) parseDocx(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } on Exception catch (e) {
    throw EpubFormatException('not a zip: $e');
  }
  XmlDocument? xml(String name) {
    final f = zip.find(name);
    if (f == null || !f.isFile) return null;
    return XmlDocument.parse(utf8.decode(f.readBytes() ?? const [], allowMalformed: true));
  }

  final doc = xml('word/document.xml');
  if (doc == null) throw EpubFormatException('missing word/document.xml');
  final body = doc.findAllElements('body', namespaceUri: _w).firstOrNull;
  if (body == null) throw EpubFormatException('no w:body');
  final title = xml('docProps/core.xml')?.findAllElements('title', namespaceUri: '*').firstOrNull?.innerText.trim();
  final w = _Walker(_Styles(xml('word/styles.xml')))..container(body);
  return (title: title, blocks: w.out.blocks);
}

String? _val(XmlElement? e) => e?.getAttribute('val', namespaceUri: _w);

XmlElement? _child(XmlElement? e, String name) => e?.findElements(name, namespaceUri: _w).firstOrNull;

/// A `<w:b/>`-style toggle: present means on unless `w:val` says otherwise.
bool? _toggle(XmlElement? props, String name) {
  final e = _child(props, name);
  if (e == null) return null;
  final v = _val(e);
  return v == null || !(v == '0' || v == 'false' || v == 'off');
}

class _Style {
  _Style({this.basedOn, this.name = '', this.bold, this.italic, this.outline});

  final String? basedOn;
  final String name;
  final bool? bold;
  final bool? italic;

  /// 0-based, as Word stores it.
  final int? outline;
}

class _Styles {
  _Styles(XmlDocument? doc) {
    if (doc == null) return;
    for (final s in doc.findAllElements('style', namespaceUri: _w)) {
      final id = s.getAttribute('styleId', namespaceUri: _w);
      if (id == null) continue;
      final rPr = _child(s, 'rPr');
      _byId[id] = _Style(
        basedOn: _val(_child(s, 'basedOn')),
        name: (_val(_child(s, 'name')) ?? id).toLowerCase(),
        bold: _toggle(rPr, 'b'),
        italic: _toggle(rPr, 'i'),
        outline: int.tryParse(_val(_child(_child(s, 'pPr'), 'outlineLvl')) ?? ''),
      );
    }
  }

  final _byId = <String, _Style>{};

  T? resolve<T>(String? styleId, T? Function(_Style s) pick) {
    var id = styleId;
    for (var i = 0; id != null && i < 10; i++) {
      final s = _byId[id];
      if (s == null) return null;
      final v = pick(s);
      if (v != null) return v;
      id = s.basedOn;
    }
    return null;
  }
}

final _headingName = RegExp(r'^heading (\d)$');

class _Walker {
  _Walker(this.styles);

  final _Styles styles;
  final out = BlockBuilder();

  void container(XmlElement parent) {
    for (final child in parent.childElements) {
      if (child.namespaceUri != _w) continue;
      switch (child.localName) {
        case 'p':
          _paragraph(child);
        case 'tbl' || 'tr' || 'tc' || 'sdt' || 'sdtContent' || 'customXml':
          container(child);
      }
    }
  }

  void _paragraph(XmlElement p) {
    final pPr = _child(p, 'pPr');
    final styleId = _val(_child(pPr, 'pStyle'));
    // A custom style ("Chapter Title") is usually based on a built-in one.
    bool derives(bool Function(String name) test) => styles.resolve(styleId, (s) => test(s.name) ? true : null) ?? false;
    final heading = styles.resolve(styleId, (s) => int.tryParse(_headingName.firstMatch(s.name)?.group(1) ?? ''));
    final outline = int.tryParse(_val(_child(pPr, 'outlineLvl')) ?? '') ?? styles.resolve(styleId, (s) => s.outline);
    final (kind, level) = switch (heading) {
      final h? => (BlockKind.heading, h.clamp(1, 6)),
      // 9 is Word's "body text" outline level.
      _ when outline != null && outline < 9 => (BlockKind.heading, (outline + 1).clamp(1, 6)),
      _ when derives((n) => n == 'title') => (BlockKind.heading, 1),
      _ when derives((n) => n == 'subtitle') => (BlockKind.heading, 2),
      _ when derives((n) => n.contains('quote')) => (BlockKind.quote, 0),
      _ when _child(pPr, 'numPr') != null || derives((n) => n.startsWith('list')) => (BlockKind.listItem, 0),
      _ => (BlockKind.paragraph, 0),
    };
    out
      ..flush()
      ..kind = kind
      ..level = level;
    final pBold = (styles.resolve(styleId, (s) => s.bold) ?? false) || kind == BlockKind.heading;
    final pItalic = styles.resolve(styleId, (s) => s.italic) ?? false;
    _runs(p, bold: pBold, italic: pItalic);
    out
      ..flush()
      ..kind = BlockKind.paragraph
      ..level = 0;
  }

  /// Runs, including those inside hyperlinks, insertions and simple fields.
  /// A complex field's instruction runs hold only `w:instrText`, which
  /// [_run] skips; its result runs are ordinary text.
  void _runs(XmlElement parent, {required bool bold, required bool italic}) {
    for (final child in parent.childElements) {
      if (child.namespaceUri != _w) continue;
      switch (child.localName) {
        case 'r':
          _run(child, bold: bold, italic: italic);
        case 'hyperlink' || 'ins' || 'smartTag' || 'fldSimple' || 'customXml' || 'sdt' || 'sdtContent':
          _runs(child, bold: bold, italic: italic);
        // w:del (deleted text), w:pPr, bookmarks, comments: not shown.
      }
    }
  }

  void _run(XmlElement r, {required bool bold, required bool italic}) {
    final rPr = _child(r, 'rPr');
    final charStyle = _val(_child(rPr, 'rStyle'));
    final b = _toggle(rPr, 'b') ?? styles.resolve(charStyle, (s) => s.bold) ?? bold;
    final i = _toggle(rPr, 'i') ?? styles.resolve(charStyle, (s) => s.italic) ?? italic;
    for (final e in r.childElements) {
      if (e.namespaceUri != _w) continue;
      switch (e.localName) {
        case 't':
          out.write(e.innerText, bold: b, italic: i);
        case 'tab':
          out.write(' ', bold: b, italic: i);
        case 'br' || 'cr':
          // A page or column break isn't a line break in reflowed text.
          final type = e.getAttribute('type', namespaceUri: _w);
          if (type == null || type == 'textWrapping') out.write('\n', bold: b, italic: i, pre: true);
        case 'noBreakHyphen':
          out.write('-', bold: b, italic: i);
        case 'sym':
          final code = int.tryParse(e.getAttribute('char', namespaceUri: _w) ?? '', radix: 16);
          // Symbol-font code points (F000–F0FF) have no meaning outside the font.
          if (code != null && (code < 0xF000 || code > 0xF0FF)) out.write(String.fromCharCode(code), bold: b, italic: i);
      }
      // w:instrText, w:delText, drawings, footnote references: skipped.
    }
  }
}
