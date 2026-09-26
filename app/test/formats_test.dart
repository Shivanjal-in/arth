// ignore_for_file: leading_newlines_in_multiline_strings — XML fixtures start with their declaration.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:arth/core/formats/docx.dart';
import 'package:arth/core/formats/fb2.dart';
import 'package:arth/core/formats/odt.dart';
import 'package:arth/core/formats/plain_text.dart';
import 'package:arth/core/formats/reflow_book.dart';
import 'package:arth/core/formats/rtf.dart';
import 'package:arth/core/formats/split.dart';
import 'package:arth/core/formats/text_decode.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, text) => a.add(ArchiveFile.string(name, text)));
  return ZipEncoder().encode(a);
}

EpubBlock _p(String text, {BlockKind kind = BlockKind.paragraph, int level = 0}) =>
    EpubBlock(kind: kind, level: level, runs: [InlineRun(text)]);

String _styled(EpubBlock b) => b.runs.map((r) => r.italic ? '_${r.text}_' : r.bold ? '*${r.text}*' : r.text).join();

void main() {
  group('decodeText', () {
    test('code page tables cover 0x80–0xFF', () {
      final high = List.generate(128, (i) => 0x80 + i);
      expect(decodeSingleByte(high, 'windows-1252').length, 128);
      expect(decodeSingleByte(high, 'windows-1251').length, 128);
    });

    test('UTF-8, BOMs, and Windows-1252 smart quotes', () {
      expect(decodeText(utf8.encode('naïve “x”')), 'naïve “x”');
      expect(decodeText([0xEF, 0xBB, 0xBF, 0x68, 0x69]), 'hi');
      expect(decodeText([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]), 'hi');
      expect(decodeText([0x93, 0x68, 0x69, 0x94, 0x20, 0x97]), '“hi” —');
      expect(decodeWithCharset([0xCF, 0xF0, 0xE8], 'windows-1251'), 'При');
    });
  });

  group('splitIntoChapters', () {
    test('splits at the repeated heading level; a lone title joins the first chapter', () {
      final r = splitIntoChapters([
        _p('The Book', kind: BlockKind.heading, level: 1),
        _p('Chapter 1', kind: BlockKind.heading, level: 2),
        _p('one'),
        _p('Scene', kind: BlockKind.heading, level: 3),
        _p('still one'),
        _p('Chapter 2', kind: BlockKind.heading, level: 2),
        _p('two'),
      ]);
      expect(r.chapters.map((c) => c.map((b) => b.text).join('|')), ['The Book|Chapter 1|one|Scene|still one', 'Chapter 2|two']);
      expect(r.toc.map((e) => '${e.title}@${e.chapter}/${e.depth}'), ['The Book@0/0', 'Chapter 1@0/1', 'Chapter 2@1/1']);
    });

    test('promotes "Chapter N" paragraphs only when there are no real headings', () {
      final plain = promoteChapterHeadings([_p('Chapter One'), _p('text'), _p('Chapter Two'), _p('Chapter two was long.')]);
      expect(plain.map((b) => b.kind), [BlockKind.heading, BlockKind.paragraph, BlockKind.heading, BlockKind.paragraph]);
      final styled = [_p('Title', kind: BlockKind.heading, level: 1), _p('Chapter One')];
      expect(promoteChapterHeadings(styled), same(styled));
    });

    test('cuts a long headingless text into sections', () {
      final para = 'word ' * 200; // 1000 chars
      final r = splitIntoChapters(List.generate(100, (_) => _p(para)));
      expect(r.chapters.length, 3);
      expect(r.chapters.expand((c) => c).length, 100);
      expect(r.toc, isEmpty);
    });
  });

  group('plain text', () {
    test('Gutenberg: header/footer stripped, title, chapters, wrapped paragraphs, italics', () {
      final doc = parsePlainText('''The Project Gutenberg eBook of Pride and Prejudice\r
\r
Title: Pride and Prejudice\r
Author: Jane Austen\r
\r
*** START OF THE PROJECT GUTENBERG EBOOK PRIDE AND PREJUDICE ***\r
\r
CHAPTER I.\r
\r
It is a truth universally acknowledged, that a single man in\r
possession of a good fortune, must be in _want_ of a wife.\r
\r
Letter from home was on the table.\r
\r
Chapter 2: The Visit\r
\r
    Some verse here,\r
    and a second line.\r
\r
*** END OF THE PROJECT GUTENBERG EBOOK PRIDE AND PREJUDICE ***\r
licence text''');
      expect(doc.title, 'Pride and Prejudice');
      expect(doc.blocks.map((b) => '${b.kind.name}:${_styled(b)}'), [
        'heading:*CHAPTER I.*',
        'paragraph:It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in _want_ of a wife.',
        'paragraph:Letter from home was on the table.',
        'heading:*Chapter 2: The Visit*',
        'paragraph:Some verse here,\nand a second line.',
      ]);
    });

    test('a leading Title: line is the title, and short front matter opens chapter one', () {
      final book = parseDocument(utf8.encode('Title: The Keeper\n\nFor my father.\n\nCHAPTER I.\n\nThe light.\n\nCHAPTER II.\n\nThe storm.'), '.txt');
      expect(book.title, 'The Keeper');
      expect(book.chapterCount, 2);
      expect(book.chapters.first.map((b) => b.text), ['For my father.', 'CHAPTER I.', 'The light.']);
      expect(book.toc.map((e) => '${e.title}@${e.chapter}'), ['CHAPTER I.@0', 'CHAPTER II.@1']);
    });

    test('a short file with no blank lines is one paragraph per line', () {
      final doc = parsePlainText('Chapter One\nFirst paragraph.\nSecond paragraph.');
      expect(doc.blocks.map((b) => '${b.kind.name}:${b.text}'), ['heading:Chapter One', 'paragraph:First paragraph.', 'paragraph:Second paragraph.']);
    });

    test('one paragraph per line when there are no blank lines', () {
      final doc = parsePlainText(List.generate(30, (i) => 'Paragraph $i.').join('\n'));
      expect(doc.blocks.length, 30);
      expect(doc.blocks.first.text, 'Paragraph 0.');
    });
  });

  group('HTML', () {
    test('title and blocks from a whole document', () {
      final doc = parseHtmlDocument('<html><head><title> My  Page </title></head><body><h1>Hi</h1><p>A <em>b</em></p></body></html>');
      expect(doc.title, 'My Page');
      expect(doc.blocks.map(_styled), ['*Hi*', 'A _b_']);
    });
  });

  group('ODT', () {
    List<int> odt() => _zip({
          'mimetype': 'application/vnd.oasis.opendocument.text',
          'meta.xml': '''<?xml version="1.0"?>
<office:document-meta xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
<office:meta><dc:title>Odt Book</dc:title></office:meta></office:document-meta>''',
          'styles.xml': '''<?xml version="1.0"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0">
<office:styles>
  <style:style style:name="Heading_20_2" style:display-name="Heading 2" style:family="paragraph" style:default-outline-level="2"/>
  <style:style style:name="Quotations" style:family="paragraph"/>
  <style:style style:name="Emphasis" style:family="text"><style:text-properties fo:font-style="italic"/></style:style>
</office:styles></office:document-styles>''',
          'content.xml': '''<?xml version="1.0"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0">
<office:automatic-styles>
  <style:style style:name="T1" style:family="text"><style:text-properties fo:font-weight="bold"/></style:style>
  <style:style style:name="P1" style:family="paragraph" style:parent-style-name="Heading_20_2"/>
</office:automatic-styles>
<office:body><office:text>
<text:h text:outline-level="1">Part One</text:h>
<text:p text:style-name="P1">Chapter 1</text:p>
<text:p>It was a <text:span text:style-name="T1">dark</text:span> and<text:s text:c="3"/><text:span text:style-name="Emphasis">stormy</text:span> night.<text:note><text:note-citation>1</text:note-citation><text:note-body><text:p>A note.</text:p></text:note-body></text:note></text:p>
<text:p text:style-name="Quotations">Quoted<text:line-break/>line two</text:p>
<text:list><text:list-item><text:p>First item</text:p></text:list-item></text:list>
<table:table><table:table-row><table:table-cell><text:p>Cell text</text:p></table:table-cell></table:table-row></table:table>
<text:section><text:p>In a section</text:p></text:section>
</office:text></office:body></office:document-content>''',
        });

    test('headings, emphasis via styles, quotes, lists, tables; footnotes dropped', () {
      final doc = parseOdt(odt());
      expect(doc.title, 'Odt Book');
      expect(doc.blocks.map((b) => '${b.kind.name}${b.level}:${_styled(b)}'), [
        'heading1:*Part One*',
        'heading2:*Chapter 1*',
        'paragraph0:It was a *dark* and   _stormy_ night.',
        'quote0:Quoted\nline two',
        'listItem0:First item',
        'paragraph0:Cell text',
        'paragraph0:In a section',
      ]);
    });

    test('parseDocument makes a book', () {
      final book = parseDocument(odt(), '.odt');
      expect(book.title, 'Odt Book');
      expect(book.chapterCount, 1);
      // Part One and Chapter 1 are both chapter-level; with nothing between
      // them they open the same chapter.
      expect(book.toc.map((e) => '${e.title}@${e.chapter}'), ['Part One@0', 'Chapter 1@0']);
    });

    test('garbage is a format error', () {
      expect(() => parseDocument(utf8.encode('not a zip'), '.odt'), throwsA(isA<EpubFormatException>()));
    });
  });

  group('DOCX', () {
    const w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
    List<int> docx() => _zip({
          'docProps/core.xml': '''<?xml version="1.0"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Word Book</dc:title></cp:coreProperties>''',
          'word/styles.xml': '''<?xml version="1.0"?>
<w:styles $w>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>
  <w:style w:type="paragraph" w:styleId="MyChapter"><w:name w:val="My Chapter"/><w:basedOn w:val="Heading1"/></w:style>
  <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:rPr><w:i/></w:rPr></w:style>
  <w:style w:type="character" w:styleId="Strong"><w:name w:val="Strong"/><w:rPr><w:b/></w:rPr></w:style>
</w:styles>''',
          'word/document.xml': '''<?xml version="1.0"?>
<w:document $w><w:body>
<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Chapter One</w:t></w:r></w:p>
<w:p><w:r><w:t xml:space="preserve">It was </w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>very</w:t></w:r><w:r><w:rPr><w:rStyle w:val="Strong"/></w:rPr><w:t xml:space="preserve"> dark</w:t></w:r><w:del><w:r><w:delText>deleted</w:delText></w:r></w:del><w:ins><w:r><w:t>.</w:t></w:r></w:ins></w:p>
<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText>HYPERLINK "x"</w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:hyperlink><w:r><w:t>a link</w:t></w:r></w:hyperlink><w:r><w:fldChar w:fldCharType="end"/></w:r><w:r><w:br/><w:t>next line</w:t></w:r></w:p>
<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr><w:r><w:t>Quoted</w:t></w:r><w:r><w:rPr><w:i w:val="0"/></w:rPr><w:t xml:space="preserve"> plain</w:t></w:r></w:p>
<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Item</w:t></w:r></w:p>
<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:pPr><w:pStyle w:val="MyChapter"/></w:pPr><w:r><w:t>Chapter Two</w:t></w:r></w:p>
<w:sectPr/>
</w:body></w:document>''',
        });

    test('styles, runs, fields, tracked changes, lists, tables', () {
      final doc = parseDocx(docx());
      expect(doc.title, 'Word Book');
      expect(doc.blocks.map((b) => '${b.kind.name}${b.level}:${_styled(b)}'), [
        'heading1:*Chapter One*',
        'paragraph0:It was _very_* dark*.',
        'paragraph0:a link\nnext line',
        'quote0:_Quoted_ plain',
        'listItem0:Item',
        'paragraph0:Cell',
        'heading1:*Chapter Two*',
      ]);
      final book = parseDocument(docx(), '.docx');
      expect(book.chapterCount, 2);
      expect(book.titleOf(1), 'Chapter Two');
    });
  });

  group('FB2', () {
    const fb2 = '''<?xml version="1.0" encoding="windows-1251"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><book-title>Fb Book</book-title></title-info></description>
<body>
  <section>
    <title><p>Chapter 1</p><p>The Start</p></title>
    <epigraph><p>An epigraph.</p><text-author>Someone</text-author></epigraph>
    <p>Some <emphasis>styled</emphasis> <strong>text</strong><a l:href="#n1" type="note">[1]</a>.</p>
    <empty-line/>
    <poem><stanza><v>Line one</v><v>Line two</v></stanza></poem>
    <section><title><p>Part A</p></title><p>Nested.</p></section>
  </section>
  <section><title><p>Chapter 2</p></title><p>Mир</p></section>
</body>
<body name="notes"><section id="n1"><p>Footnote text.</p></section></body>
</FictionBook>''';

    List<int> bytes() {
      // Encode as Windows-1251, as the declaration says.
      final out = <int>[];
      for (final r in fb2.runes) {
        if (r < 0x80) {
          out.add(r);
        } else if (r >= 0x410 && r <= 0x44F) {
          out.add(r - 0x410 + 0xC0);
        } else {
          throw StateError('fixture char $r');
        }
      }
      return out;
    }

    test('sections, titles, epigraphs, poems; notes dropped; declared encoding honoured', () {
      final doc = parseFb2(bytes());
      expect(doc.title, 'Fb Book');
      expect(doc.blocks.map((b) => '${b.kind.name}${b.level}:${_styled(b)}'), [
        'heading1:*Chapter 1\nThe Start*',
        'quote0:An epigraph.',
        'quote0:_Someone_',
        'paragraph0:Some _styled_ *text*.',
        'quote0:Line one\nLine two',
        'heading2:*Part A*',
        'paragraph0:Nested.',
        'heading1:*Chapter 2*',
        'paragraph0:Mир',
      ]);
      final book = parseDocument(bytes(), '.fb2');
      expect(book.chapterCount, 2);
      expect(book.toc.map((e) => e.title), ['Chapter 1 The Start', 'Chapter 2']);
    });

    test('.fb2.zip', () {
      final zip = ZipEncoder().encode(Archive()..add(ArchiveFile.bytes('book.fb2', bytes())));
      expect(parseFb2Zip(zip).title, 'Fb Book');
      expect(reflowExtensionOf('/x/My.Book.FB2.zip'), '.fbz');
    });
  });

  group('RTF', () {
    test('paragraphs, emphasis, headings by stylesheet and outline level, escapes, unicode', () {
      const rtf = r'''{\rtf1\ansi\ansicpg1252\deff0
{\fonttbl{\f0 Times New Roman;}}
{\colortbl;\red0\green0\blue0;}
{\stylesheet{\ql Normal;}{\s1\ql heading 1;}{\*\cs10 Default Paragraph Font;}}
{\info{\title Rtf Book}{\author Me}}
{\header Page header\par}
\pard\s1 Chapter One\par
\pard Plain {\b bold} and {\i italic}\i0  text\par
Quotes: \ldblquote hi\rdblquote \'96 caf\'e9 \u8364?\u-3913?  {\field{\*\fldinst HYPERLINK "x"}{\fldrslt link}}\par
Line\line break\tab tab \{braces\}\par
{\*\unknowndest secret}{\footnote note text}
\pard\outlinelevel0 Chapter Two\par
\pard After\par
}''';
      final doc = parseRtf(latin1.encode(rtf));
      expect(doc.title, 'Rtf Book');
      expect(doc.blocks.map((b) => '${b.kind.name}${b.level}:${_styled(b)}'), [
        'heading1:*Chapter One*',
        'paragraph0:Plain *bold* and _italic_ text',
        // A control word's delimiting space isn't text: `\\rdblquote \\'96` is “”–”.
        'paragraph0:Quotes: “hi”– café €${String.fromCharCode(65536 - 3913)} link',
        'paragraph0:Line\nbreak tab {braces}',
        'heading1:*Chapter Two*',
        'paragraph0:After',
      ]);
    });

    test('not RTF', () {
      expect(() => parseRtf(utf8.encode('hello')), throwsA(isA<EpubFormatException>()));
    });
  });
}
