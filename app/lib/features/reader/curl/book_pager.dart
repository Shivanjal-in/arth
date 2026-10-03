// Turns pages like a book. Wraps the live reader: while the reader sits still
// it is the reader, fully interactive. A horizontal drag lifts the page into
// a snapshot and curls it (curl_painter.dart); on release the page either
// turns over or settles back, the reader is moved to the new page underneath,
// and the snapshot goes.
//
// After PlayLikeCurl's flow (drag sets the curl position; release or fling
// animates it home in about 300 ms; three pages — previous, current, next —
// are kept ready), redrawn in Dart so it works on iOS too.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:arth/features/reader/curl/curl_geometry.dart';
import 'package:arth/features/reader/curl/curl_painter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A picture of the page after the current one ([next]) or before it, as the
/// reader would show it, [size] pixels; null if there is no such page.
typedef PageSnapshot = Future<ui.Image?> Function({required bool next, required Size size});

/// Pages are turned with a curl, a page at a time (no setting: always on).
const bool kBookPages = true;

class BookPagerController {
  _BookPagerState? _state;

  /// Turn to the next page (true) or the previous one with the curl.
  Future<void> turn({required bool forward}) async => _state?._turnBy(forward: forward);

  bool get busy => _state?._curl != null;
}

class BookPager extends StatefulWidget {
  const BookPager({
    required this.position,
    required this.hasNext,
    required this.hasPrevious,
    required this.snapshot,
    required this.onTurn,
    required this.paper,
    required this.child,
    super.key,
    this.controller,
    this.enabled = true,
    this.canStart,
  });

  /// Anything that changes whenever the reader shows a different page: the
  /// pictures of the pages either side are redrawn when it does.
  final Object position;
  final bool hasNext;
  final bool hasPrevious;

  /// A picture of the page next to the current one (for the page being
  /// turned to or from).
  final PageSnapshot snapshot;

  /// Called when a turn has been made: show the next (or previous) page in
  /// the reader. The pager keeps the curl on screen until the returned
  /// future completes.
  final Future<void> Function({required bool next}) onTurn;

  final Color paper;
  final Widget child;
  final BookPagerController? controller;
  final bool enabled;

  /// Asked when a swipe begins; false (a text selection is being dragged)
  /// leaves the swipe to the reader.
  final bool Function()? canStart;

  @override
  State<BookPager> createState() => _BookPagerState();
}

enum _Dir { forward, backward }

class _Curl {
  _Curl({required this.dir, required this.turning, required this.under, required this.fold});

  final _Dir dir;
  final ui.Image turning;
  final ui.Image under;
  double fold;

  void dispose() {
    turning.dispose();
    under.dispose();
  }
}

class _BookPagerState extends State<BookPager> with SingleTickerProviderStateMixin {
  final GlobalKey _boundary = GlobalKey();
  late final AnimationController _anim = AnimationController(vsync: this);

  _Curl? _curl;

  /// Images of neighbouring pages, ready before a drag starts.
  final Map<bool, ui.Image> _ready = {};
  Size? _readySize;
  Timer? _prefetchTimer;

  _Dir? _dir;
  bool _preparing = false;
  bool _animating = false;
  double _dx = 0;

  // Raw pointer tracking (see build): one finger, horizontal, soon after it lands.
  int? _pointer;
  Offset _down = Offset.zero;
  Duration _downAt = Duration.zero;
  bool _engaged = false;
  VelocityTracker? _velocity;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _schedulePrefetch();
  }

  @override
  void didUpdateWidget(BookPager old) {
    super.didUpdateWidget(old);
    widget.controller?._state = this;
    if (old.position != widget.position) {
      // The pages either side are different pages now.
      _clearReady();
      _schedulePrefetch();
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _prefetchTimer?.cancel();
    _anim.dispose();
    _curl?.dispose();
    _clearReady();
    super.dispose();
  }

  // ---- images ----

  Size? get _pixels {
    final box = _boundary.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Size((box.size.width * dpr).roundToDouble(), (box.size.height * dpr).roundToDouble());
  }

  void _clearReady() {
    for (final i in _ready.values) {
      i.dispose();
    }
    _ready.clear();
  }

  /// Once the reader has settled, draw the pages either side so a drag
  /// doesn't wait for them.
  void _schedulePrefetch() {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || _curl != null || !widget.enabled) return;
      final size = _pixels;
      if (size == null) return;
      if (_readySize != size) {
        _clearReady();
        _readySize = size;
      }
      final at = widget.position;
      for (final next in [true, false]) {
        if (!(next ? widget.hasNext : widget.hasPrevious) || _ready.containsKey(next)) continue;
        final image = await widget.snapshot(next: next, size: size);
        // The reader moved on while this was drawing: it's the wrong page.
        if (!mounted || widget.position != at || _ready.containsKey(next)) {
          image?.dispose();
          if (!mounted || widget.position != at) return;
          continue;
        }
        if (image != null) _ready[next] = image;
      }
    });
  }

  Future<ui.Image?> _neighbour({required bool next, required Size size}) async {
    final cached = _ready.remove(next);
    if (cached != null && cached.width == size.width.toInt() && cached.height == size.height.toInt()) return cached;
    cached?.dispose();
    return widget.snapshot(next: next, size: size);
  }

  Future<ui.Image?> _captureCurrent() async {
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return null;
    return box.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
  }

  // ---- gestures ----

  static const double _slop = 18;

  void _onPointerDown(PointerDownEvent e) {
    if (_pointer != null) {
      // A second finger: this is a pinch or a hold, not a page turn.
      _cancelTracking();
      return;
    }
    if (!widget.enabled || _animating || _curl != null) return;
    _pointer = e.pointer;
    _down = e.position;
    _downAt = e.timeStamp;
    _engaged = false;
    _velocity = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    final total = e.position - _down;
    if (!_engaged) {
      if (total.distance < _slop) return;
      // Mostly sideways, and soon after landing: a long press that then drags
      // is selecting text.
      final quick = e.timeStamp - _downAt < const Duration(milliseconds: 600);
      if (total.dx.abs() < total.dy.abs() * 1.6 || !quick || !(widget.canStart?.call() ?? true)) {
        _cancelTracking();
        return;
      }
      final dir = total.dx < 0 ? _Dir.forward : _Dir.backward;
      if (!_canGo(dir)) {
        _cancelTracking();
        return;
      }
      _engaged = true;
      _dir = dir;
      unawaited(_prepare(dir));
    }
    _dx = total.dx;
    final curl = _curl;
    if (curl != null) setState(() => curl.fold = _foldFor(curl.dir, _dx));
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final engaged = _engaged;
    final v = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0;
    _cancelTracking(keepDir: true);
    if (engaged) _release(v);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    final engaged = _engaged;
    _cancelTracking(keepDir: true);
    if (engaged && _curl != null && !_animating) unawaited(_finish(commit: false));
  }

  void _cancelTracking({bool keepDir = false}) {
    _pointer = null;
    _engaged = false;
    _velocity = null;
    if (!keepDir) _dir = null;
  }

  bool _canGo(_Dir dir) => dir == _Dir.forward ? widget.hasNext : widget.hasPrevious;

  void _release(double velocityX) {
    final dir = _dir;
    _dir = null;
    if (dir == null) return;
    final curl = _curl;
    if (curl == null) {
      // Let go before the pictures were ready: a quick flick still turns.
      if (velocityX.abs() > 600) unawaited(_turnBy(forward: dir == _Dir.forward));
      return;
    }
    final geo = _geo;
    final progress = dir == _Dir.forward ? (geo.flat - curl.fold) / geo.flat : (curl.fold - geo.gone) / (geo.flat - geo.gone);
    final flicked = dir == _Dir.forward ? velocityX < -700 : velocityX > 700;
    final back = dir == _Dir.forward ? velocityX > 700 : velocityX < -700;
    unawaited(_finish(commit: !back && (flicked || progress > 0.4)));
  }

  CurlGeometry get _geo => CurlGeometry(size: context.size ?? const Size(1, 1));

  /// The fold for a drag of [dx]: forward, the page's edge goes where the
  /// finger goes; backward, the roll does.
  double _foldFor(_Dir dir, double dx) {
    final geo = _geo;
    if (dir == _Dir.forward) {
      return math.min(geo.flat, geo.foldForEdge(geo.size.width + dx));
    }
    return math.min(geo.flat, geo.gone + dx * 1.25);
  }

  Future<void> _prepare(_Dir dir) async {
    if (_preparing) return;
    _preparing = true;
    try {
      final size = _pixels;
      if (size == null) return;
      final here = await _captureCurrent();
      final other = await _neighbour(next: dir == _Dir.forward, size: size);
      if (!mounted || here == null || other == null) {
        here?.dispose();
        other?.dispose();
        return;
      }
      final geo = _geo;
      final curl = dir == _Dir.forward
          ? _Curl(dir: dir, turning: here, under: other, fold: geo.flat)
          : _Curl(dir: dir, turning: other, under: here, fold: geo.gone);
      if (_dir == null && !_animating) {
        // Dropped before it began.
        curl.dispose();
        return;
      }
      setState(() {
        _curl = curl;
        curl.fold = _foldFor(dir, _dx);
      });
    } finally {
      _preparing = false;
    }
  }

  /// A turn that isn't a drag: the tap or button.
  Future<void> _turnBy({required bool forward}) async {
    final dir = forward ? _Dir.forward : _Dir.backward;
    if (_animating || _curl != null || !_canGo(dir) || !widget.enabled) return;
    _dir = dir;
    _dx = 0;
    await _prepare(dir);
    _dir = null;
    if (_curl == null) {
      // No pictures: just move.
      await widget.onTurn(next: forward);
      return;
    }
    await _finish(commit: true);
  }

  Future<void> _finish({required bool commit}) async {
    final curl = _curl;
    if (curl == null || _animating) return;
    _animating = true;
    final geo = _geo;
    final forward = curl.dir == _Dir.forward;
    final target = commit ? (forward ? geo.gone : geo.flat) : (forward ? geo.flat : geo.gone);
    final from = curl.fold;
    final distance = (target - from).abs() / (geo.flat - geo.gone);
    _anim
      ..stop()
      ..duration = Duration(milliseconds: (220 + 260 * distance).round());
    void tick() => setState(() => curl.fold = ui.lerpDouble(from, target, Curves.easeOutCubic.transform(_anim.value))!);
    _anim.addListener(tick);
    await _anim.forward(from: 0);
    _anim.removeListener(tick);
    if (!mounted) return;
    setState(() => curl.fold = target);
    if (commit) {
      _clearReady();
      await widget.onTurn(next: forward);
      // Let the reader paint the new page before the picture goes.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (!mounted) return;
    setState(() {
      _curl = null;
      curl.dispose();
    });
    _animating = false;
    if (!commit) _schedulePrefetch();
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final curl = _curl;
    final pager = Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (curl != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CurlPainter(turning: curl.turning, under: curl.under, fold: curl.fold, paper: widget.paper),
              ),
            ),
          ),
      ],
    );
    // Raw pointers rather than a drag recognizer: the reader's own gesture
    // recognizers sit below and would otherwise win the arena on a fast swipe.
    // Always wrapped, even when off, so the reader below keeps its state.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: pager,
    );
  }
}
