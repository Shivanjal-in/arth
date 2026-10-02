import 'dart:io';
import 'dart:ui' as ui;

import 'package:arth/features/reader/curl/curl_geometry.dart';
import 'package:arth/features/reader/curl/curl_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page-like picture: paper, ruled lines, a title and a page number.
Future<ui.Image> _page(Size size, String label, Color paper) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..drawRect(Offset.zero & size, Paint()..color = paper);
  final line = Paint()..color = const Color(0xFF445555)..strokeWidth = 3;
  for (var y = 160.0; y < size.height - 80; y += 46) {
    c.drawLine(Offset(60, y), Offset(size.width - 60 - (y % 5) * 14, y), line);
  }
  TextPainter(
    text: TextSpan(text: label, style: const TextStyle(fontSize: 64, color: Color(0xFF10201D), fontWeight: FontWeight.bold)),
    textDirection: TextDirection.ltr,
  )
    ..layout()
    ..paint(c, const Offset(60, 60));
  return rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
}

void main() {
  test('fold math: flat, cylinder, laid back', () {
    const g = CurlGeometry(size: Size(1000, 1600));
    final r = g.radius;
    expect(g.fold(300, 500).x, 300); // left of the fold: untouched
    expect(g.fold(500, 500).z, 0);
    final top = g.fold(500 + 3.14159265 * r, 500);
    expect(top.x, closeTo(500, 0.01)); // the top of the roll is back above the fold
    expect(top.z, closeTo(2 * r, 0.01));
    final back = g.fold(500 + 3.14159265 * r + 100, 500);
    expect(back.x, closeTo(400, 0.01)); // laid back toward the spine
    // the edge-tracking solve inverts the fold
    for (final e in [900.0, 600.0, 200.0, -100.0]) {
      final f = g.foldForEdge(e);
      expect(g.fold(1000, f).x, closeTo(e, 0.01));
    }
    expect(g.fold(1000, g.gone).x, lessThan(0.5)); // gone: off the left edge
  });

  test('renders frames', () async {
    const size = Size(540, 960);
    final a = await _page(size, 'Page 5', const Color(0xFFF7F7F2));
    final b = await _page(size, 'Page 6', const Color(0xFFEFEFE6));
    const g = CurlGeometry(size: size);
    final dir = Directory('${Directory.systemTemp.path}/curl_frames')..createSync(recursive: true);
    for (final entry in {'a_flat': g.flat, 'b_early': 470.0, 'c_mid': 300.0, 'd_late': 120.0, 'e_gone': g.gone + 20}.entries) {
      final rec = ui.PictureRecorder();
      CurlPainter(turning: a, under: b, fold: entry.value, paper: const Color(0xFFF7F7F2)).paint(Canvas(rec), size);
      final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/${entry.key}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
