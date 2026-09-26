// A reflowable book: chapters of text blocks the EPUB reader lays out to the
// screen. EPUB reads its chapters from the zip on demand; the other formats
// (TXT, HTML, ODT, DOCX, FB2, RTF) are one document each, parsed whole off
// the main isolate and cut into chapters at their headings.

import 'dart:io';
import 'dart:isolate';

import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:arth/core/formats/docx.dart';
import 'package:arth/core/formats/fb2.dart';
import 'package:arth/core/formats/odt.dart';
import 'package:arth/core/formats/plain_text.dart';
import 'package:arth/core/formats/rtf.dart';
import 'package:arth/core/formats/split.dart';
import 'package:arth/core/formats/text_decode.dart';
import 'package:path/path.dart' as p;

/// File extensions (lower case, with the dot) the reflow reader opens.
const reflowExtensions = {'.epub', '.txt', '.html', '.htm', '.xhtml', '.odt', '.docx', '.fb2', '.fbz', '.rtf'};

/// The extension a file is recognised by: `.fb2.zip` counts as `.fbz`.
String reflowExtensionOf(String path) {
  final name = p.basename(path).toLowerCase();
  if (name.endsWith('.fb2.zip')) return '.fbz';
  return p.extension(name);
}

abstract class ReflowBook {
  /// The title from the file's own metadata; `'Untitled'` when it has none.
  String get title;
  List<EpubTocEntry> get toc;
  int get chapterCount;

  /// The blocks of chapter [i] (0-based).
  Future<List<EpubBlock>> chapter(int i);

  Future<void> close();

  /// The chapter's title from the table of contents, if it has one.
  String? titleOf(int chapter) => toc.where((e) => e.chapter == chapter).firstOrNull?.title;

  /// Opens [path] by its extension. Throws [EpubFormatException] when the
  /// file can't be read as that format.
  static Future<ReflowBook> open(String path) async {
    final ext = reflowExtensionOf(path);
    if (ext == '.epub') return EpubBook.open(path);
    final bytes = await File(path).readAsBytes();
    try {
      return await Isolate.run(() => parseDocument(bytes, ext));
    } on EpubFormatException {
      rethrow;
    } on Exception catch (e) {
      throw EpubFormatException('unreadable $ext: $e');
    }
  }
}

/// A whole document already parsed into chapters.
class DocumentBook extends ReflowBook {
  DocumentBook({required this.title, required this.chapters, required this.toc});

  @override
  final String title;
  final List<List<EpubBlock>> chapters;
  @override
  final List<EpubTocEntry> toc;

  @override
  int get chapterCount => chapters.length;

  @override
  Future<List<EpubBlock>> chapter(int i) async => chapters[i];

  @override
  Future<void> close() async {}
}

/// Parses a non-EPUB document from its bytes. Synchronous: callers run it in
/// an isolate.
DocumentBook parseDocument(List<int> bytes, String ext) {
  final doc = switch (ext) {
    '.txt' => parsePlainText(decodeText(bytes)),
    '.html' || '.htm' || '.xhtml' => parseHtmlDocument(decodeText(bytes)),
    '.odt' => parseOdt(bytes),
    '.docx' => parseDocx(bytes),
    '.fb2' => parseFb2(bytes),
    '.fbz' => parseFb2Zip(bytes),
    '.rtf' => parseRtf(bytes),
    _ => throw EpubFormatException('unsupported format $ext'),
  };
  if (doc.blocks.isEmpty) throw EpubFormatException('no text in $ext');
  final split = splitIntoChapters(promoteChapterHeadings(doc.blocks));
  final title = doc.title?.trim();
  return DocumentBook(title: title == null || title.isEmpty ? 'Untitled' : title, chapters: split.chapters, toc: split.toc);
}
