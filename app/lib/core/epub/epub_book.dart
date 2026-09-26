// An EPUB on disk: the zip, its OPF spine (reading order) and table of
// contents. Chapters are read and parsed on demand — a novel is a few MB of
// XHTML and nobody reads it all at once.
//
// Pure Dart. The zip stays open for the life of the book; call [close].

import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:arth/core/formats/reflow_book.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class EpubFormatException implements Exception {
  EpubFormatException(this.message);

  final String message;

  @override
  String toString() => 'EpubFormatException: $message';
}

/// One table-of-contents entry, pointing at a spine position.
class EpubTocEntry {
  const EpubTocEntry({required this.title, required this.chapter, this.depth = 0});

  final String title;

  /// Index into the spine.
  final int chapter;
  final int depth;
}

class EpubBook extends ReflowBook {
  EpubBook._(this._archive, this._input, this.title, this._spine, this.toc);

  /// Opens from bytes (tests).
  factory EpubBook.fromBytes(List<int> bytes) => EpubBook._load(ZipDecoder().decodeBytes(bytes), null);

  factory EpubBook._load(Archive archive, InputFileStream? input) {
    String read(String name) {
      final f = _find(archive, name);
      if (f == null) throw EpubFormatException('missing $name');
      return utf8.decode(f.readBytes() ?? const [], allowMalformed: true);
    }

    final container = XmlDocument.parse(read('META-INF/container.xml'));
    final opfPath = container.findAllElements('rootfile', namespaceUri: '*').firstOrNull?.getAttribute('full-path');
    if (opfPath == null) throw EpubFormatException('container.xml has no rootfile');
    final opfDir = p.posix.dirname(opfPath);
    String resolve(String href) {
      final clean = Uri.decodeFull(href.split('#').first);
      return p.posix.normalize(opfDir == '.' ? clean : p.posix.join(opfDir, clean));
    }

    final opf = XmlDocument.parse(read(opfPath));
    final title = opf.findAllElements('title', namespaceUri: '*').firstOrNull?.innerText.trim();

    final manifest = <String, ({String href, String type, String props})>{};
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (href: resolve(href), type: item.getAttribute('media-type') ?? '', props: item.getAttribute('properties') ?? '');
    }

    final spine = <String>[];
    final spineIndex = <String, int>{};
    for (final ref in opf.findAllElements('itemref', namespaceUri: '*')) {
      // linear="no" marks covers and the like: not part of the reading order.
      if (ref.getAttribute('linear') == 'no') continue;
      final item = manifest[ref.getAttribute('idref')];
      if (item == null || _find(archive, item.href) == null) continue;
      spineIndex[item.href] = spine.length;
      spine.add(item.href);
    }
    if (spine.isEmpty) throw EpubFormatException('empty spine');

    // Table of contents: EPUB 3 nav document, else EPUB 2 NCX.
    var toc = <EpubTocEntry>[];
    final nav = manifest.values.where((m) => m.props.split(' ').contains('nav')).firstOrNull;
    if (nav != null) {
      final navDir = p.posix.dirname(nav.href);
      toc = _parseNav(read(nav.href), (href) => spineIndex[p.posix.normalize(p.posix.join(navDir, Uri.decodeFull(href.split('#').first)))]);
    }
    if (toc.isEmpty) {
      final ncxId = opf.findAllElements('spine', namespaceUri: '*').firstOrNull?.getAttribute('toc');
      final ncx = manifest[ncxId] ?? manifest.values.where((m) => m.type == 'application/x-dtbncx+xml').firstOrNull;
      if (ncx != null && _find(archive, ncx.href) != null) {
        final ncxDir = p.posix.dirname(ncx.href);
        toc = _parseNcx(read(ncx.href), (src) => spineIndex[p.posix.normalize(p.posix.join(ncxDir, Uri.decodeFull(src.split('#').first)))]);
      }
    }
    return EpubBook._(archive, input, title == null || title.isEmpty ? 'Untitled' : title, spine, toc);
  }

  final Archive _archive;
  final InputFileStream? _input;
  @override
  final String title;

  /// Zip entry names in reading order.
  final List<String> _spine;
  @override
  final List<EpubTocEntry> toc;
  final Map<int, Future<List<EpubBlock>>> _chapters = {};

  @override
  int get chapterCount => _spine.length;

  /// Opens the file. Throws [EpubFormatException] if it isn't an EPUB.
  static Future<EpubBook> open(String path) async {
    final input = InputFileStream(path);
    try {
      return EpubBook._load(ZipDecoder().decodeStream(input), input);
    } on EpubFormatException {
      await input.close();
      rethrow;
    } on Exception catch (e) {
      await input.close();
      throw EpubFormatException('not a zip: $e');
    }
  }

  static ArchiveFile? _find(Archive archive, String name) {
    final exact = archive.find(name);
    if (exact != null && exact.isFile) return exact;
    // Some packagers disagree with their own manifest about case.
    final lower = name.toLowerCase();
    return archive.files.where((f) => f.isFile && f.name.toLowerCase() == lower).firstOrNull;
  }

  static List<EpubTocEntry> _parseNav(String source, int? Function(String href) chapterOf) {
    final entries = <EpubTocEntry>[];
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(source, entityMapping: const XmlDefaultEntityMapping.html5());
    } on XmlException {
      return entries;
    }
    final navs = doc.findAllElements('nav', namespaceUri: '*');
    final toc = navs.where((n) => n.attributes.any((a) => a.name.local == 'type' && a.value == 'toc')).firstOrNull ?? navs.firstOrNull;
    if (toc == null) return entries;
    void walk(XmlElement list, int depth) {
      for (final li in list.findElements('li', namespaceUri: '*')) {
        final a = li.findElements('a', namespaceUri: '*').firstOrNull ?? li.findElements('span', namespaceUri: '*').firstOrNull;
        final href = a?.getAttribute('href');
        final chapter = href == null ? null : chapterOf(href);
        final label = a?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        if (chapter != null && label.isNotEmpty) entries.add(EpubTocEntry(title: label, chapter: chapter, depth: depth));
        for (final sub in li.findElements('ol', namespaceUri: '*')) {
          walk(sub, depth + 1);
        }
      }
    }
    for (final ol in toc.findElements('ol', namespaceUri: '*')) {
      walk(ol, 0);
    }
    return entries;
  }

  static List<EpubTocEntry> _parseNcx(String source, int? Function(String src) chapterOf) {
    final entries = <EpubTocEntry>[];
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(source);
    } on XmlException {
      return entries;
    }
    void walk(XmlElement parent, int depth) {
      for (final point in parent.findElements('navPoint', namespaceUri: '*')) {
        final label = point.findElements('navLabel', namespaceUri: '*').firstOrNull?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        final src = point.findElements('content', namespaceUri: '*').firstOrNull?.getAttribute('src');
        final chapter = src == null ? null : chapterOf(src);
        if (chapter != null && label.isNotEmpty) entries.add(EpubTocEntry(title: label, chapter: chapter, depth: depth));
        walk(point, depth + 1);
      }
    }
    final map = doc.findAllElements('navMap', namespaceUri: '*').firstOrNull;
    if (map != null) walk(map, 0);
    return entries;
  }

  /// The blocks of chapter [i] (0-based), parsed once. Inflating the entry is
  /// quick; the HTML parse runs off the main isolate.
  @override
  Future<List<EpubBlock>> chapter(int i) => _chapters.putIfAbsent(i, () async {
        final bytes = _find(_archive, _spine[i])?.readBytes();
        if (bytes == null) return const [];
        return _parseOffMain(bytes);
      });

  // A separate function so the isolate closure captures only the bytes, not
  // `this` (the zip and the futures map are not sendable).
  static Future<List<EpubBlock>> _parseOffMain(List<int> bytes) => Isolate.run(() => parseChapterBytes(bytes));

  @override
  Future<void> close() async {
    await _input?.close();
  }
}
