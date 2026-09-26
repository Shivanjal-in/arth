// One block of an EPUB chapter, painted by its own TextPainter so the word
// rects handed to the tooltip are exactly where the glyphs were drawn.
//
// The block is the unit of text for tapping: PageTextIndex over its plain
// text, rects in the block's own coordinate space (origin top-left).

import 'package:arth/core/text/page_text_index.dart';
import 'package:arth/features/reader/highlights/highlight_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A run of words to paint under the text: a saved highlight, or the
/// selection while the highlighter is dragging.
@immutable
class PaintedRange {
  const PaintedRange({required this.startWord, required this.endWord, required this.color});

  final int startWord;
  final int endWord;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is PaintedRange && other.startWord == startWord && other.endWord == endWord && other.color == color;

  @override
  int get hashCode => Object.hash(startWord, endWord, color);
}

class ParagraphText extends LeafRenderObjectWidget {
  const ParagraphText({
    required this.span,
    required this.textScaler,
    this.textAlign = TextAlign.start,
    this.ranges = const [],
    super.key,
  });

  final TextSpan span;
  final TextScaler textScaler;
  final TextAlign textAlign;
  final List<PaintedRange> ranges;

  @override
  RenderParagraphBlock createRenderObject(BuildContext context) => RenderParagraphBlock(
        span: span,
        textScaler: textScaler,
        textAlign: textAlign,
        textDirection: Directionality.of(context),
        ranges: ranges,
      );

  @override
  void updateRenderObject(BuildContext context, RenderParagraphBlock renderObject) {
    renderObject
      ..span = span
      ..textScaler = textScaler
      ..textAlign = textAlign
      ..textDirection = Directionality.of(context)
      ..ranges = ranges;
  }
}

class RenderParagraphBlock extends RenderBox {
  RenderParagraphBlock({
    required TextSpan span,
    required TextScaler textScaler,
    required TextAlign textAlign,
    required TextDirection textDirection,
    List<PaintedRange> ranges = const [],
  })  : _painter = TextPainter(text: span, textScaler: textScaler, textAlign: textAlign, textDirection: textDirection),
        _ranges = ranges;

  final TextPainter _painter;
  PageTextIndex? _index;
  List<PaintedRange> _ranges;

  List<PaintedRange> get ranges => _ranges;
  set ranges(List<PaintedRange> v) {
    if (listEquals(v, _ranges)) return;
    _ranges = v;
    markNeedsPaint();
  }

  TextSpan get span => _painter.text! as TextSpan;
  set span(TextSpan v) {
    if (identical(v, _painter.text) || v == _painter.text) return;
    _painter.text = v;
    _invalidate();
  }

  TextScaler get textScaler => _painter.textScaler;
  set textScaler(TextScaler v) {
    if (v == _painter.textScaler) return;
    _painter.textScaler = v;
    _invalidate();
  }

  TextAlign get textAlign => _painter.textAlign;
  set textAlign(TextAlign v) {
    if (v == _painter.textAlign) return;
    _painter.textAlign = v;
    _invalidate();
  }

  TextDirection get textDirection => _painter.textDirection!;
  set textDirection(TextDirection v) {
    if (v == _painter.textDirection) return;
    _painter.textDirection = v;
    _invalidate();
  }

  void _invalidate() {
    _index = null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    _painter.layout(maxWidth: constraints.maxWidth);
    _index = null;
    size = constraints.constrain(Size(constraints.maxWidth, _painter.height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _painter.layout(maxWidth: constraints.maxWidth);
    _index = null;
    return constraints.constrain(Size(constraints.maxWidth, _painter.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_ranges.isNotEmpty) {
      final words = index.words;
      final paint = Paint();
      for (final r in _ranges) {
        final from = r.startWord.clamp(0, words.length);
        final to = r.endWord.clamp(-1, words.length - 1);
        paint.color = r.color;
        for (final band in highlightBands([for (var i = from; i <= to; i++) words[i].rect])) {
          context.canvas.drawRRect(
            RRect.fromRectAndRadius(band.inflate(1.5).shift(offset), const Radius.circular(3)),
            paint,
          );
        }
      }
    }
    _painter.paint(context.canvas, offset);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  /// Words and sentences of this block, with rects in local coordinates.
  /// Built lazily after layout and dropped on relayout.
  PageTextIndex get index => _index ??= _build();

  PageTextIndex _build() {
    final text = _painter.plainText;
    final rects = List<Rect>.filled(text.length, Rect.zero);
    for (final m in _nonSpace.allMatches(text)) {
      final boxes = _painter.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
      if (boxes.length == 1) {
        final r = boxes.first.toRect();
        for (var i = m.start; i < m.end; i++) {
          rects[i] = r;
        }
      } else {
        // The word wrapped (or mixed directions): rect each character so the
        // highlight follows the line break instead of spanning the column.
        for (var i = m.start; i < m.end; i++) {
          final b = _painter.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
          rects[i] = b.isEmpty ? Rect.zero : b.first.toRect();
        }
      }
    }
    return PageTextIndex.build(text, rects);
  }

  static final RegExp _nonSpace = RegExp(r'\S+');
}
