// Where to put the tooltip relative to the tapped word / selection rect.
//
// Pure geometry so it can be widget-tested without a PDF: prefer below the
// anchor, flip above when there is more room there, clamp [inset] from the
// screen edges, cap height at [maxHeightFraction] of the screen.

import 'dart:math' as math;
import 'dart:ui';

class TooltipPlacement {
  const TooltipPlacement({
    required this.offset,
    required this.above,
    required this.maxHeight,
    required this.width,
  });

  /// Top-left of the tooltip in the same coordinate space as the anchor.
  final Offset offset;

  /// True when the tooltip sits above the anchor (arrow points down).
  final bool above;

  /// Height available; the tooltip must scroll inside this.
  final double maxHeight;

  final double width;
}

TooltipPlacement placeTooltip({
  required Rect anchor,
  required Size tooltipSize,
  required Size screen,
  double inset = 16,
  double gap = 8,
  double maxHeightFraction = 0.45,
}) {
  final cap = screen.height * maxHeightFraction;
  final width = math.min(tooltipSize.width, screen.width - 2 * inset);
  final wanted = math.min(tooltipSize.height, cap);

  final roomBelow = screen.height - inset - (anchor.bottom + gap);
  final roomAbove = anchor.top - gap - inset;

  final above = roomBelow < wanted && roomAbove > roomBelow;
  final room = above ? roomAbove : roomBelow;
  final height = math.max(0, math.min(wanted, room)).toDouble();

  final top = above ? anchor.top - gap - height : anchor.bottom + gap;
  final left = (anchor.center.dx - width / 2)
      .clamp(inset, math.max(inset, screen.width - inset - width))
      .toDouble();

  return TooltipPlacement(
    offset: Offset(left, top),
    above: above,
    maxHeight: height,
    width: width,
  );
}
