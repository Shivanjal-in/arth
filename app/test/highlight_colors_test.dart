import 'dart:ui';

import 'package:arth/features/reader/highlights/highlight_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('highlightBands merges words on a line and breaks on line changes', () {
    final bands = highlightBands([
      const Rect.fromLTWH(0, 0, 30, 20),
      const Rect.fromLTWH(35, 0, 40, 20),
      const Rect.fromLTWH(80, 0.5, 20, 20), // same line, sub-pixel top
      const Rect.fromLTWH(0, 30, 50, 20), // next line
      Rect.zero, // a synthesised break: skipped
      const Rect.fromLTWH(55, 30, 10, 20),
    ]);
    expect(bands, [const Rect.fromLTRB(0, 0, 100, 20.5), const Rect.fromLTRB(0, 30, 65, 50)]);
  });

  test('highlightBands of nothing is nothing', () {
    expect(highlightBands(const []), isEmpty);
    expect(highlightBands([Rect.zero]), isEmpty);
  });
}
