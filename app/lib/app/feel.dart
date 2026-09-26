// How the app answers a touch: haptics, motion timings, and a pressable
// surface that gives under the finger.
//
// Haptics have a small vocabulary so they mean something:
//   choose   — picking one of several (a tab, a chip, a colour)       selection tick
//   open     — opening something (a word, a book, a card)             light tap
//   commit   — keeping something (save a card, bookmark, "got it")    medium tap
//   finish   — finishing a book                                       medium, then heavy
// All of it is off when the reader turns haptics off in the You tab.
//
// Motion is short and answers an action; the one orchestrated moment is
// the library's covers settling in. Everything respects the system's
// reduce-motion setting.

import 'dart:async';

import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class Haptics {
  /// Mirrors the setting; set by the app when settings load or change.
  static bool enabled = true;

  static void choose() {
    if (enabled) unawaited(HapticFeedback.selectionClick());
  }

  static void open() {
    if (enabled) unawaited(HapticFeedback.lightImpact());
  }

  static void commit() {
    if (enabled) unawaited(HapticFeedback.mediumImpact());
  }

  static Future<void> finish() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await HapticFeedback.heavyImpact();
  }
}

/// Durations and curves, named for what they do.
abstract final class Motion {
  /// A control answering a press.
  static const press = Duration(milliseconds: 110);

  /// Something small appearing or changing state (a chip, a ribbon).
  static const quick = Duration(milliseconds: 180);

  /// A surface arriving (a card, a sheet's content, a page).
  static const settle = Duration(milliseconds: 320);

  /// The library's covers, one after another.
  static const stagger = Duration(milliseconds: 55);

  /// Decelerates hard: arrivals.
  static const Curve arrive = Cubic(0.05, 0.7, 0.1, 1);

  /// Symmetric, for state changes.
  static const Curve change = Curves.easeInOutCubic;

  /// Whether to skip decorative motion (the system's reduce-motion setting).
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or nothing when motion is reduced.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

/// A surface that sinks a little under the finger and springs back, with
/// an optional haptic. Wrap tiles and cards that open something.
class Pressable extends StatefulWidget {
  const Pressable({required this.child, super.key, this.onTap, this.onLongPress, this.haptic = Haptics.open, this.scale = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Played on tap; null for none.
  final void Function()? haptic;

  /// How far it sinks.
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              widget.haptic?.call();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              Haptics.commit();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.of(context, Motion.press),
        curve: Motion.change,
        child: widget.child,
      ),
    );
  }
}

/// A child that fades and rises into place [delay] after it first builds —
/// used once, for the library's covers. Instant with reduced motion.
class SettleIn extends StatefulWidget {
  const SettleIn({required this.child, super.key, this.delay = Duration.zero, this.from = const Offset(0, 0.04), this.fromScale = 1.03});

  final Widget child;
  final Duration delay;

  /// Starting offset, as a fraction of the child's size.
  final Offset from;
  final double fromScale;

  @override
  State<SettleIn> createState() => _SettleInState();
}

class _SettleInState extends State<SettleIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.settle);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Motion.arrive);
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _timer != null) return;
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) unawaited(_c.forward());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _t.value,
          child: FractionalTranslation(
            translation: Offset.lerp(widget.from, Offset.zero, _t.value)!,
            child: Transform.scale(scale: 1 + (widget.fromScale - 1) * (1 - _t.value), child: child),
          ),
        ),
      );
}

/// How far through a book: a marigold bar that fills to [value] when it
/// first appears and glides when the value changes.
class ReadingBar extends StatelessWidget {
  const ReadingBar({required this.value, super.key, this.height = 4});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: Motion.of(context, const Duration(milliseconds: 700)),
        curve: Motion.arrive,
        builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: height, color: c.marigold, backgroundColor: c.rule),
      ),
    );
  }
}
