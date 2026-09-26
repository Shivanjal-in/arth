// The highlighter's four inks: soft enough to read through on paper, and a
// little more opaque on the dark theme so they still register.

import 'package:arth/data/local_store.dart';
import 'package:flutter/material.dart';

class HighlightPalette {
  HighlightPalette._();

  /// The solid swatch shown in the colour picker and the highlights list.
  static Color swatch(HighlightColor c) => switch (c) {
        HighlightColor.yellow => const Color(0xFFF0C330),
        HighlightColor.green => const Color(0xFF7DC47A),
        HighlightColor.blue => const Color(0xFF74B2E6),
        HighlightColor.pink => const Color(0xFFF097B3),
      };

  /// The translucent fill painted under the words.
  static Color fill(HighlightColor c, Brightness brightness) =>
      swatch(c).withValues(alpha: brightness == Brightness.dark ? 0.42 : 0.45);

  static Color fillOf(HighlightColor c, BuildContext context) => fill(c, Theme.of(context).brightness);
}

/// Merges consecutive word rects on the same line into one band per line, so
/// a highlight reads as a stroke rather than a row of boxes.
List<Rect> highlightBands(Iterable<Rect> wordRects) {
  final bands = <Rect>[];
  for (final r in wordRects) {
    if (r.isEmpty) continue;
    if (bands.isNotEmpty && (bands.last.top - r.top).abs() < 2 && r.left >= bands.last.left) {
      bands[bands.length - 1] = bands.last.expandToInclude(r);
    } else {
      bands.add(r);
    }
  }
  return bands;
}
