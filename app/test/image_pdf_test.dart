import 'dart:convert';
import 'dart:typed_data';

import 'package:arth/core/pdf/image_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a two-page PDF with a shared image has a sound cross-reference table', () {
    final img = PdfImage(width: 2, height: 1, rgb: Uint8List.fromList([255, 0, 0, 0, 0, 255]));
    final one = PdfPageSpec(footer: 'Made with Arth  1 / 2')..placements.add((image: img, x: 40, y: 40, w: 100, h: 50));
    final two = PdfPageSpec(footer: 'Made with Arth — 2 / 2')..placements.add((image: img, x: 40, y: 40, w: 100, h: 50));
    final bytes = buildImagePdf([one, two], title: 'Emma (cards)');
    final text = latin1.decode(bytes);

    expect(text, startsWith('%PDF-1.4'));
    expect(text.trimRight(), endsWith('%%EOF'));
    expect(RegExp('/Subtype /Image').allMatches(text), hasLength(1)); // written once, used twice
    expect(text, contains('/Count 2'));
    expect(text, contains(r'(Emma \(cards\))'));
    expect(text, contains('(Made with Arth  2 / 2)')); // non-ASCII dropped

    // Every offset in the xref table points at the start of its object.
    final xrefAt = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!);
    final table = text.substring(xrefAt).split('\n');
    final count = int.parse(table[1].split(' ')[1]);
    for (var n = 1; n < count; n++) {
      final offset = int.parse(table[2 + n].substring(0, 10));
      expect(text.substring(offset), startsWith('$n 0 obj'), reason: 'object $n');
    }
  });
}
