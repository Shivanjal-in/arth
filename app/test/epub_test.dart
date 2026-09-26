// ignore_for_file: leading_newlines_in_multiline_strings — XML fixtures start with their declaration.

import 'package:archive/archive.dart';
import 'package:arth/core/epub/epub_book.dart';
import 'package:arth/core/epub/epub_html.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _epub({bool nav = true, bool ncx = false}) {
  final a = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..add(
      ArchiveFile.string(
        'META-INF/container.xml',
        '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
      ),
    )
    ..add(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" version="3.0">
  <metadata><dc:title>A Little Book</dc:title></metadata>
  <manifest>
    <item id="c1" href="text/ch%201.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    ${nav ? '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' : ''}
    ${ncx ? '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' : ''}
  </manifest>
  <spine ${ncx ? 'toc="ncx"' : ''}><itemref idref="nav" linear="no"/><itemref idref="c1"/><itemref idref="c2"/><itemref idref="missing"/></spine>
</package>''',
      ),
    )
    ..add(
      ArchiveFile.string(
        'OEBPS/text/ch 1.xhtml',
        '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>ignored</title></head><body>
<h1>Chapter   One</h1>
<p>It was a <em>bright</em> cold day in April, and the clocks were striking&nbsp;thirteen.
   Winston Smith slipped quickly through the glass doors.</p>
<p><img src="x.png"/> </p>
<blockquote><p>Quoted <b>bold</b> line.</p></blockquote>
<ul><li>first</li><li>second</li></ul>
<pre>keep   this
as is</pre>
</body></html>''',
      ),
    )
    ..add(ArchiveFile.string('OEBPS/text/ch2.xhtml', '<html><body><p>Second chapter.</p></body></html>'));
  if (nav) {
    a.add(
      ArchiveFile.string(
        'OEBPS/nav.xhtml',
        '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol>
  <li><a href="text/ch%201.xhtml">One</a><ol><li><a href="text/ch%201.xhtml#part">One, later</a></li></ol></li>
  <li><a href="text/ch2.xhtml">Two</a></li>
</ol></nav></body></html>''',
      ),
    );
  }
  if (ncx) {
    a.add(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
  <navPoint><navLabel><text>Uno</text></navLabel><content src="text/ch%201.xhtml"/>
    <navPoint><navLabel><text>Uno b</text></navLabel><content src="text/ch%201.xhtml#p"/></navPoint>
  </navPoint>
  <navPoint><navLabel><text>Dos</text></navLabel><content src="text/ch2.xhtml"/></navPoint>
</navMap></ncx>''',
      ),
    );
  }
  return ZipEncoder().encode(a);
}

void main() {
  group('parseChapterHtml', () {
    test('collapses whitespace, keeps emphasis runs, skips images', () {
      final blocks = parseChapterHtml('''<body>
<h2>Title  here</h2>
<p>It was a <em>bright</em> cold day,
   and the clocks&nbsp;struck.</p>
<p><img src="a.png"/></p>
<div>Loose <strong>text</strong> in a div</div>
</body>''');
      expect(blocks.map((b) => b.text), ['Title here', 'It was a bright cold day, and the clocks struck.', 'Loose text in a div']);
      expect(blocks[0].kind, BlockKind.heading);
      expect(blocks[0].level, 2);
      expect(blocks[0].runs.single.bold, isTrue);
      final runs = blocks[1].runs;
      expect(runs.map((r) => r.text), ['It was a ', 'bright', ' cold day, and the clocks struck.']);
      expect(runs[1].italic, isTrue);
      expect(runs[0].italic, isFalse);
    });

    test('quotes, list items, pre and br', () {
      final blocks = parseChapterHtml('''<body>
<blockquote><p>Quoted.</p></blockquote>
<ul><li>one</li><li><p>two</p></li></ul>
<pre>a   b
c</pre>
<p>line one<br/>line two</p>
</body>''');
      expect(blocks.map((b) => b.kind), [BlockKind.quote, BlockKind.listItem, BlockKind.listItem, BlockKind.pre, BlockKind.paragraph]);
      expect(blocks[3].text, 'a   b\nc');
      expect(blocks[4].text, 'line one\nline two');
    });

    test('tolerates broken markup and empty documents', () {
      expect(parseChapterHtml('<p>unclosed <i>italic <p>next').map((b) => b.text), ['unclosed italic', 'next']);
      expect(parseChapterHtml(''), isEmpty);
      expect(parseChapterHtml('<body>   </body>'), isEmpty);
    });
  });

  group('EpubBook', () {
    test('reads spine, title and EPUB 3 nav toc', () async {
      final book = EpubBook.fromBytes(_epub());
      expect(book.title, 'A Little Book');
      expect(book.chapterCount, 2, reason: 'missing and linear="no" spine items dropped');
      expect(book.toc.map((e) => (e.title, e.chapter, e.depth)), [('One', 0, 0), ('One, later', 0, 1), ('Two', 1, 0)]);
      expect(book.titleOf(1), 'Two');

      final ch1 = await book.chapter(0);
      expect(ch1.first.text, 'Chapter One');
      expect(ch1[1].text, 'It was a bright cold day in April, and the clocks were striking thirteen. Winston Smith slipped quickly through the glass doors.');
      expect(ch1.map((b) => b.kind), [
        BlockKind.heading,
        BlockKind.paragraph,
        BlockKind.quote,
        BlockKind.listItem,
        BlockKind.listItem,
        BlockKind.pre,
      ]);
      expect((await book.chapter(1)).single.text, 'Second chapter.');
      expect(identical(await book.chapter(0), ch1), isTrue, reason: 'parsed once');
    });

    test('falls back to NCX toc', () {
      final book = EpubBook.fromBytes(_epub(nav: false, ncx: true));
      expect(book.toc.map((e) => (e.title, e.chapter, e.depth)), [('Uno', 0, 0), ('Uno b', 0, 1), ('Dos', 1, 0)]);
    });

    test('no toc at all is fine', () {
      final book = EpubBook.fromBytes(_epub(nav: false));
      expect(book.toc, isEmpty);
      expect(book.titleOf(0), isNull);
    });

    test('rejects non-epub zips and non-zips', () {
      final zip = ZipEncoder().encode(Archive()..add(ArchiveFile.string('hello.txt', 'hi')));
      expect(() => EpubBook.fromBytes(zip), throwsA(isA<EpubFormatException>()));
      expect(() => EpubBook.fromBytes([1, 2, 3]), throwsA(isA<Exception>()));
    });
  });
}
