// OpenDocument text (.odt) → blocks. The file is a zip; the text is
// `content.xml`, as `<text:h>` headings and `<text:p>` paragraphs holding
// `<text:span>`s. Bold and italic live in styles, not in the markup: the
// automatic styles in content.xml and the named ones in styles.xml, each of
// which may inherit from a parent.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:xml/xml.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';

({String? title, List<EpubBlock> blocks}) parseOdt(List<int> bytes) {
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

  final content = xml('content.xml');
  if (content == null) throw EpubFormatException('missing content.xml');
  final styles = _Styles()
    ..addAll(xml('styles.xml'))
    ..addAll(content);
  final title = xml('meta.xml')?.findAllElements('title', namespaceUri: '*').firstOrNull?.innerText.trim();

  final body = content.findAllElements('text', namespaceUri: _officeNs).firstOrNull;
  if (body == null) throw EpubFormatException('no office:text body');
  final w = _Walker(styles)..container(body, BlockKind.paragraph);
  return (title: title, blocks: w.out.blocks);
}

class _Style {
  _Style({this.parent, this.italic, this.bold, this.outlineLevel, this.displayName});

  final String? parent;
  final bool? italic;
  final bool? bold;
  final int? outlineLevel;
  final String? displayName;
}

class _Styles {
  final _byName = <String, _Style>{};

  void addAll(XmlDocument? doc) {
    if (doc == null) return;
    for (final s in doc.findAllElements('style', namespaceUri: _styleNs)) {
      final name = s.getAttribute('name', namespaceUri: _styleNs);
      if (name == null) continue;
      final props = s.findElements('text-properties', namespaceUri: _styleNs).firstOrNull;
      final style = props?.getAttribute('font-style', namespaceUri: _foNs);
      final weight = props?.getAttribute('font-weight', namespaceUri: _foNs);
      _byName[name] = _Style(
        parent: s.getAttribute('parent-style-name', namespaceUri: _styleNs),
        italic: style == null ? null : style == 'italic' || style == 'oblique',
        bold: weight == null ? null : weight == 'bold' || (int.tryParse(weight) ?? 400) >= 600,
        outlineLevel: int.tryParse(s.getAttribute('default-outline-level', namespaceUri: _styleNs) ?? ''),
        displayName: s.getAttribute('display-name', namespaceUri: _styleNs) ?? name,
      );
    }
  }

  /// Walks `styleName` and its ancestors; the first non-null [pick] wins.
  T? resolve<T>(String? styleName, T? Function(_Style s) pick) {
    var name = styleName;
    for (var i = 0; name != null && i < 10; i++) {
      final s = _byName[name];
      if (s == null) return null;
      final v = pick(s);
      if (v != null) return v;
      name = s.parent;
    }
    return null;
  }

  /// Whether a paragraph style is, or derives from, one whose name mentions
  /// [word] ("Quotations", "Preformatted Text", "Title").
  bool named(String? name, String word) =>
      resolve(name, (s) => (s.displayName ?? '').toLowerCase().contains(word) ? true : null) ?? false;
}

class _Walker {
  _Walker(this.styles);

  final _Styles styles;
  final out = BlockBuilder();

  /// Block-level children: paragraphs, headings, lists, tables, sections.
  void container(XmlElement parent, BlockKind kind) {
    for (final child in parent.childElements) {
      final ns = child.namespaceUri;
      final name = child.localName;
      if (ns == _textNs && name == 'h') {
        final level = int.tryParse(child.getAttribute('outline-level', namespaceUri: _textNs) ?? '') ?? 1;
        _paragraph(child, BlockKind.heading, level.clamp(1, 6));
      } else if (ns == _textNs && name == 'p') {
        final style = child.getAttribute('style-name', namespaceUri: _textNs);
        final outline = styles.resolve(style, (s) => s.outlineLevel);
        if (outline != null && outline > 0) {
          _paragraph(child, BlockKind.heading, outline.clamp(1, 6));
        } else if (styles.named(style, 'subtitle')) {
          _paragraph(child, BlockKind.heading, 2);
        } else if (styles.named(style, 'title')) {
          _paragraph(child, BlockKind.heading, 1);
        } else if (styles.named(style, 'quot')) {
          _paragraph(child, BlockKind.quote, 0);
        } else if (styles.named(style, 'preformatted')) {
          _paragraph(child, BlockKind.pre, 0);
        } else {
          _paragraph(child, kind, 0);
        }
      } else if (ns == _textNs && name == 'list') {
        for (final item in child.childElements.where((e) => e.localName == 'list-item' || e.localName == 'list-header')) {
          container(item, BlockKind.listItem);
        }
      } else if ((ns == _textNs && name == 'section') || (ns == _tableNs && const {'table', 'table-row', 'table-cell', 'table-rows', 'table-header-rows'}.contains(name))) {
        container(child, kind);
      }
      // Everything else (drawings, tracked changes, indexes' source data) is skipped.
    }
  }

  void _paragraph(XmlElement p, BlockKind kind, int level) {
    out
      ..flush()
      ..kind = kind
      ..level = level;
    final style = p.getAttribute('style-name', namespaceUri: _textNs);
    _inline(
      p,
      italic: styles.resolve(style, (s) => s.italic) ?? false,
      bold: (styles.resolve(style, (s) => s.bold) ?? false) || kind == BlockKind.heading,
      pre: kind == BlockKind.pre,
    );
    out
      ..flush()
      ..kind = BlockKind.paragraph
      ..level = 0;
  }

  void _inline(XmlElement parent, {required bool italic, required bool bold, required bool pre}) {
    for (final node in parent.children) {
      if (node is XmlText || node is XmlCDATA) {
        out.write(node.value ?? '', italic: italic, bold: bold, pre: pre);
        continue;
      }
      if (node is! XmlElement || node.namespaceUri != _textNs) continue;
      switch (node.localName) {
        case 's':
          final n = int.tryParse(node.getAttribute('c', namespaceUri: _textNs) ?? '') ?? 1;
          out.write(' ' * n, italic: italic, bold: bold, pre: true);
        case 'tab':
          out.write(' ', italic: italic, bold: bold);
        case 'line-break':
          out.write('\n', italic: italic, bold: bold, pre: true);
        case 'span':
          final style = node.getAttribute('style-name', namespaceUri: _textNs);
          _inline(
            node,
            italic: styles.resolve(style, (s) => s.italic) ?? italic,
            bold: styles.resolve(style, (s) => s.bold) ?? bold,
            pre: pre,
          );
        case 'note' || 'bookmark' || 'bookmark-start' || 'bookmark-end' || 'soft-page-break' || 'tracked-changes' || 'change' || 'change-start' || 'change-end':
          break; // footnotes and markers: not part of the running text
        default:
          // a, meta, sequence, date, page-number…: their text is what shows.
          _inline(node, italic: italic, bold: bold, pre: pre);
      }
    }
  }
}
