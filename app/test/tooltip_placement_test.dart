import 'dart:ui';

import 'package:arth/features/reader/tooltip/tooltip_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = Size(400, 800);
  const size = Size(320, 200);

  test('goes below when there is room, centred on the anchor', () {
    final p = placeTooltip(
      anchor: const Rect.fromLTWH(150, 100, 60, 16),
      tooltipSize: size,
      screen: screen,
    );
    expect(p.above, isFalse);
    expect(p.offset.dy, 100 + 16 + 8);
    expect(p.offset.dx, 180 - 160);
    expect(p.maxHeight, 200);
  });

  test('flips above near the bottom', () {
    final p = placeTooltip(
      anchor: const Rect.fromLTWH(150, 700, 60, 16),
      tooltipSize: size,
      screen: screen,
    );
    expect(p.above, isTrue);
    expect(p.offset.dy, 700 - 8 - 200);
  });

  test('clamps 16px from the horizontal edges', () {
    final left = placeTooltip(
      anchor: const Rect.fromLTWH(0, 100, 20, 16),
      tooltipSize: size,
      screen: screen,
    );
    expect(left.offset.dx, 16);
    final right = placeTooltip(
      anchor: const Rect.fromLTWH(390, 100, 10, 16),
      tooltipSize: size,
      screen: screen,
    );
    expect(right.offset.dx, 400 - 16 - 320);
  });

  test('caps height at 45% of the screen', () {
    final p = placeTooltip(
      anchor: const Rect.fromLTWH(150, 50, 60, 16),
      tooltipSize: const Size(320, 900),
      screen: screen,
    );
    expect(p.maxHeight, 360);
  });

  test('narrow screens shrink the width', () {
    final p = placeTooltip(
      anchor: const Rect.fromLTWH(10, 50, 60, 16),
      tooltipSize: size,
      screen: const Size(300, 600),
    );
    expect(p.width, 300 - 32);
    expect(p.offset.dx, 16);
  });
}
