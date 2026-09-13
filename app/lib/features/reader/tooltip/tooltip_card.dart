// The tooltip's shell: card, arrow, scroll inside the height cap.

import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';

class TooltipCard extends StatelessWidget {
  const TooltipCard({
    required this.child,
    required this.width,
    required this.maxHeight,
    required this.above,
    super.key,
  });

  final Widget child;
  final double width;
  final double maxHeight;
  final bool above;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final arrow = CustomPaint(
      size: const Size(18, 9),
      painter: _ArrowPainter(color: c.card, up: !above),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!above) arrow,
        Material(
          color: c.card,
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight - 9, maxWidth: width),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
              child: DefaultTextHeightBehavior(
                // Keep ascenders/descenders of the first and last Hindi lines.
                textHeightBehavior: const TextHeightBehavior(
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                child: child,
              ),
            ),
          ),
        ),
        if (above) arrow,
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.color, required this.up});

  final Color color;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (up) {
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color || old.up != up;
}
