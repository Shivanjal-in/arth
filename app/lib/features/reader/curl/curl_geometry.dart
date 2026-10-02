// The shape of a page mid-turn: a flat page whose right part has been rolled
// up around a cylinder, like Google Play Books' page curl.
//
// Everything is driven by one number, the fold: the x where the page leaves
// the flat. Left of it the page lies as it was; right of it the page wraps a
// cylinder of radius r (front face showing until the roll is vertical), then
// passes over the top and lies back along the flat with its back face up.
//
//        fold f
//   flat ───┤╮ ← front face, curving up
//           │ ╲
//   ◄── back face, lying over the flat  ╯ (the page's free edge)
//
// PlayLikeCurl (the Android GL library this was modelled on) bends a mesh
// with a sine wave; a cylinder gives the same grid-of-strips idea a visible
// back face and a real edge.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// The roll's radius as a share of the page width.
const double kCurlRadiusFraction = 0.11;

class CurlGeometry {
  const CurlGeometry({required this.size, this.radiusFraction = kCurlRadiusFraction});

  final Size size;
  final double radiusFraction;

  double get radius => size.width * radiusFraction;

  /// The fold at which the whole page is flat again (nothing is curled).
  double get flat => size.width;

  /// The fold at which the roll has left the screen on the left.
  double get gone => -radius - 1;

  /// Where a point at x on the page ends up on screen, and how high it
  /// stands off the flat (z). `theta` is how far round the cylinder it is:
  /// 0 on the flat, up to π at the top of the roll, beyond that lying back.
  ({double x, double z, double theta}) fold(double x, double f) {
    final r = radius;
    final d = x - f;
    if (d <= 0) return (x: x, z: 0, theta: 0);
    if (d <= math.pi * r) {
      final t = d / r;
      return (x: f + r * math.sin(t), z: r * (1 - math.cos(t)), theta: t);
    }
    return (x: f - (d - math.pi * r), z: 2 * r, theta: math.pi);
  }

  /// The fold that puts the page's free edge at [edgeX], for a finger that
  /// carries the edge. Monotonic in the edge, so bisect.
  double foldForEdge(double edgeX) {
    var lo = gone;
    var hi = flat;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (fold(size.width, mid).x < edgeX) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// The strip columns for fold [f]: even across the page, with extra ones
  /// round the roll so it is smooth, and exact breaks at the fold, the
  /// quarter-turn (where the front face gives way to the back) and the top.
  List<double> columns(double f) {
    final r = radius;
    final xs = <double>{0, size.width};
    for (var i = 1; i < 16; i++) {
      xs.add(size.width * i / 16);
    }
    for (var j = 0; j <= 24; j++) {
      final x = f + j * math.pi * r / 24;
      if (x > 0 && x < size.width) xs.add(x);
    }
    if (f > 0 && f < size.width) xs.add(f);
    return xs.toList()..sort();
  }

  /// The mesh for the turning page at fold [f]; [imageSize] converts page
  /// positions to texture pixels. Front and back faces are separate, because
  /// the back is drawn last (it is on top).
  CurlMesh mesh(double f, Size imageSize) {
    final xs = columns(f);
    final h = size.height;
    final cx = size.width / 2;
    final cy = h / 2;
    // A gentle perspective: what stands off the page is nearer the eye.
    final eye = size.width * 3.2;
    final sx = imageSize.width / size.width;
    final sy = imageSize.height / h;

    final n = xs.length;
    final pos = Float32List(n * 4);
    final tex = Float32List(n * 4);
    final shadeFront = Int32List(n * 2);
    final shadeBack = Int32List(n * 2);
    final thetas = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final p = fold(xs[i], f);
      thetas[i] = p.theta;
      final s = eye / (eye - p.z);
      final px = cx + (p.x - cx) * s;
      final top = cy + (0 - cy) * s;
      final bottom = cy + (h - cy) * s;
      pos[i * 4] = px;
      pos[i * 4 + 1] = top;
      pos[i * 4 + 2] = px;
      pos[i * 4 + 3] = bottom;
      tex[i * 4] = xs[i] * sx;
      tex[i * 4 + 1] = 0;
      tex[i * 4 + 2] = xs[i] * sx;
      tex[i * 4 + 3] = h * sy;
      final front = _grey(1 - 0.30 * math.sin(math.min(p.theta, math.pi / 2)));
      shadeFront[i * 2] = front;
      shadeFront[i * 2 + 1] = front;
      // The back of the page: darkest where the roll turns over, brightening
      // as it comes to face the eye, then flat.
      final u = ((p.theta - math.pi / 2) / (math.pi / 2)).clamp(0.0, 1.0);
      final back = _grey(0.66 + 0.34 * math.sin(u * math.pi / 2));
      shadeBack[i * 2] = back;
      shadeBack[i * 2 + 1] = back;
    }

    final front = <int>[];
    final back = <int>[];
    for (var i = 0; i < n - 1; i++) {
      final mid = (thetas[i] + thetas[i + 1]) / 2;
      final target = mid > math.pi / 2 + 1e-6 ? back : front;
      final a = i * 2;
      final b = i * 2 + 1;
      final c = (i + 1) * 2;
      final d = (i + 1) * 2 + 1;
      target.addAll([a, b, c, b, d, c]);
    }
    return CurlMesh(
      positions: pos,
      textureCoordinates: tex,
      frontColors: shadeFront,
      backColors: shadeBack,
      frontIndices: Uint16List.fromList(front),
      backIndices: Uint16List.fromList(back),
      freeEdge: pos[(n - 1) * 4],
      rollRight: _rollRight(xs, pos, thetas),
    );
  }

  /// The right-most point of the roll on screen (where its shadow begins).
  double _rollRight(List<double> xs, Float32List pos, List<double> thetas) {
    var right = 0.0;
    for (var i = 0; i < xs.length; i++) {
      if (thetas[i] > 0 && pos[i * 4] > right) right = pos[i * 4];
    }
    return right;
  }

  static int _grey(double v) {
    final c = (v.clamp(0.0, 1.0) * 255).round();
    return 0xFF000000 | (c << 16) | (c << 8) | c;
  }
}

class CurlMesh {
  const CurlMesh({
    required this.positions,
    required this.textureCoordinates,
    required this.frontColors,
    required this.backColors,
    required this.frontIndices,
    required this.backIndices,
    required this.freeEdge,
    required this.rollRight,
  });

  /// Two vertices per column: top then bottom.
  final Float32List positions;
  final Float32List textureCoordinates;
  final Int32List frontColors;
  final Int32List backColors;
  final Uint16List frontIndices;
  final Uint16List backIndices;

  /// Screen x of the page's free edge.
  final double freeEdge;

  /// Screen x of the roll's right-most point.
  final double rollRight;
}
