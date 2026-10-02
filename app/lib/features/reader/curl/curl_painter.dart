// Draws a page turn: the page underneath, the turning page rolled up round a
// cylinder, and the soft shadows between them.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:arth/features/reader/curl/curl_geometry.dart';
import 'package:flutter/rendering.dart';

class CurlPainter extends CustomPainter {
  CurlPainter({required this.turning, required this.under, required this.fold, required this.paper, this.shadow = const Color(0xFF000000)});

  /// The page being turned, as it looks flat.
  final ui.Image turning;

  /// The page it uncovers.
  final ui.Image under;

  /// Where the page leaves the flat (see [CurlGeometry.fold]).
  final double fold;

  /// The colour of the back of a page.
  final Color paper;

  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = CurlGeometry(size: size);
    final bounds = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(bounds);
    _flat(canvas, under, bounds);

    // Fully flat (or fully gone): no mesh, just the page.
    if (fold >= geo.flat - 0.5) {
      _flat(canvas, turning, bounds);
      canvas.restore();
      return;
    }
    if (fold <= geo.gone) {
      canvas.restore();
      return;
    }

    final mesh = geo.mesh(fold, Size(turning.width.toDouble(), turning.height.toDouble()));
    final r = geo.radius;

    // The turning page throws a shadow on what it uncovers.
    _band(
      canvas,
      bounds,
      from: mesh.rollRight,
      to: mesh.rollRight + r * 3.2,
      begin: shadow.withValues(alpha: 0.24),
      end: shadow.withValues(alpha: 0),
    );

    final shader = ui.ImageShader(turning, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);
    final facePaint = Paint()
      ..shader = shader
      ..filterQuality = FilterQuality.medium;
    canvas.drawVertices(_vertices(mesh, mesh.frontIndices, mesh.frontColors, textured: true), BlendMode.modulate, facePaint);

    // The edge of the folded-back part shades the page it lies on.
    if (mesh.backIndices.isNotEmpty) {
      _band(
        canvas,
        bounds,
        from: mesh.freeEdge,
        to: mesh.freeEdge - r * 2.4,
        begin: shadow.withValues(alpha: 0.20),
        end: shadow.withValues(alpha: 0),
      );
      // The back: the page seen through its own paper, so the print shows
      // faintly, reversed.
      canvas.drawVertices(_vertices(mesh, mesh.backIndices, mesh.backColors, textured: true), BlendMode.modulate, facePaint);
      final tint = Paint()..color = paper;
      canvas.drawVertices(
        _vertices(mesh, mesh.backIndices, _tinted(mesh.backColors, paper, 0.80), textured: false),
        BlendMode.srcOver,
        tint,
      );
    }
    canvas.restore();
  }

  void _flat(Canvas canvas, ui.Image image, Rect bounds) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bounds,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// A horizontal fade between two x positions, over the full height.
  void _band(Canvas canvas, Rect bounds, {required double from, required double to, required Color begin, required Color end}) {
    final left = from < to ? from : to;
    final right = from < to ? to : from;
    final rect = Rect.fromLTRB(left, bounds.top, right, bounds.bottom).intersect(bounds);
    if (rect.isEmpty) return;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(from, 0),
          Offset(to, 0),
          [begin, end],
        ),
    );
  }

  ui.Vertices _vertices(CurlMesh mesh, Uint16List indices, Int32List colors, {required bool textured}) => ui.Vertices.raw(
        ui.VertexMode.triangles,
        mesh.positions,
        textureCoordinates: textured ? mesh.textureCoordinates : null,
        colors: colors,
        indices: indices,
      );

  /// The shading colours, tinted toward [paper] by [amount] (as alpha).
  Int32List _tinted(Int32List shade, Color paper, double amount) {
    final out = Int32List(shade.length);
    for (var i = 0; i < shade.length; i++) {
      final g = (shade[i] & 0xFF) / 255;
      final a = (amount * 255).round();
      out[i] = (a << 24) |
          (((paper.r * 255 * g).round().clamp(0, 255)) << 16) |
          (((paper.g * 255 * g).round().clamp(0, 255)) << 8) |
          ((paper.b * 255 * g).round().clamp(0, 255));
    }
    return out;
  }

  @override
  bool shouldRepaint(CurlPainter old) => old.fold != fold || old.turning != turning || old.under != under || old.paper != paper;
}
