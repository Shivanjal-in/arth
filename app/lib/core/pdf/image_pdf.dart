// A small PDF writer for pages made of pictures: each page places RGB images
// (Flate-compressed) and a line of ASCII footer text in Helvetica. Enough to
// turn widgets rendered by Flutter — which shapes Devanagari properly, where
// PDF text libraries don't — into a document any phone can open and print.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// An image to place: [rgb] is width × height × 3 bytes, top row first.
class PdfImage {
  PdfImage({required this.width, required this.height, required this.rgb});

  final int width;
  final int height;
  final Uint8List rgb;
}

/// An image placed on a page, in points from the page's top-left corner.
typedef PdfPlacement = ({PdfImage image, double x, double y, double w, double h});

class PdfPageSpec {
  PdfPageSpec({this.footer = ''});

  final List<PdfPlacement> placements = [];

  /// ASCII only (standard Helvetica); anything else is dropped.
  final String footer;
}

/// A4 in points.
const a4Width = 595.28;
const a4Height = 841.89;

Uint8List buildImagePdf(List<PdfPageSpec> pages, {String title = ''}) {
  final out = BytesBuilder(copy: false);
  final offsets = <int>[];
  void write(String s) => out.add(latin1.encode(s));
  void object(int n, void Function() body) {
    offsets.add(out.length);
    write('$n 0 obj\n');
    body();
    write('\nendobj\n');
  }

  void stream(String dict, List<int> data) {
    write('<< $dict /Length ${data.length} >>\nstream\n');
    out.add(data);
    write('\nendstream');
  }

  // Object numbers: 1 catalog, 2 page tree, 3 font, 4 info; then each image,
  // then each page and its content stream.
  final images = <PdfImage>[];
  final imageIds = <PdfImage, int>{};
  for (final page in pages) {
    for (final p in page.placements) {
      if (!imageIds.containsKey(p.image)) {
        images.add(p.image);
        imageIds[p.image] = 0;
      }
    }
  }
  var next = 5;
  for (final img in images) {
    imageIds[img] = next++;
  }
  final pageIds = [for (var i = 0; i < pages.length; i++) next + i * 2];

  write('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'); // the binary comment marks the file as binary
  object(1, () => write('<< /Type /Catalog /Pages 2 0 R >>'));
  object(2, () => write('<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] /Count ${pages.length} >>'));
  object(3, () => write('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'));
  object(4, () => write('<< /Title (${_pdfString(title)}) /Producer (Arth) >>'));
  for (final img in images) {
    object(imageIds[img]!, () {
      stream(
        '/Type /XObject /Subtype /Image /Width ${img.width} /Height ${img.height} '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode',
        zlib.encode(img.rgb),
      );
    });
  }
  for (final (i, page) in pages.indexed) {
    final id = pageIds[i];
    final names = <PdfImage, String>{};
    for (final p in page.placements) {
      names.putIfAbsent(p.image, () => 'Im${names.length + 1}');
    }
    final content = StringBuffer();
    for (final p in page.placements) {
      final y = a4Height - p.y - p.h;
      content.write('q ${_n(p.w)} 0 0 ${_n(p.h)} ${_n(p.x)} ${_n(y)} cm /${names[p.image]} Do Q\n');
    }
    final footer = _pdfString(page.footer);
    if (footer.isNotEmpty) {
      content.write('BT /F1 8 Tf 0.45 0.45 0.45 rg ${_n(40)} ${_n(24)} Td ($footer) Tj ET\n');
    }
    object(id, () {
      final xobjects = names.entries.map((e) => '/${e.value} ${imageIds[e.key]} 0 R').join(' ');
      write(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_n(a4Width)} ${_n(a4Height)}] '
        '/Resources << /Font << /F1 3 0 R >> /XObject << $xobjects >> >> /Contents ${id + 1} 0 R >>',
      );
    });
    object(id + 1, () => stream('', latin1.encode(content.toString())));
  }

  final xref = out.length;
  final count = offsets.length + 1;
  write('xref\n0 $count\n0000000000 65535 f \n');
  // Objects were written in number order, so offsets line up with 1..n.
  for (final o in offsets) {
    write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size $count /Root 1 0 R /Info 4 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.takeBytes();
}

String _n(double v) => v.toStringAsFixed(2);

/// Printable ASCII, with PDF string escapes.
String _pdfString(String s) => s
    .runes
    .where((r) => r >= 32 && r < 127)
    .map(String.fromCharCode)
    .join()
    .replaceAll(r'\', r'\\')
    .replaceAll('(', r'\(')
    .replaceAll(')', r'\)');
