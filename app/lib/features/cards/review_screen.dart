// Flip through a deck. Replay shows every card in reading order (swipe or
// tap the arrows to move); practice shows due cards first, and after the
// flip asks "again" or "got it" (or swipe left / right), moving the card
// between review boxes.
//
// The deck is a physical stack: the next two cards peek out behind the
// current one, the current card flips in 3D and follows the finger.

import 'dart:async';
import 'dart:math';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/ads/interstitials.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/cards/review_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ReviewMode { replay, practice }

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({required this.deck, required this.mode, super.key});

  final DeckRef deck;
  final ReviewMode mode;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> with TickerProviderStateMixin {
  /// The session's cards, fixed when it starts so rating one doesn't
  /// reshuffle the rest.
  List<Flashcard>? _cards;
  int _index = 0;
  int _known = 0;
  bool _done = false;

  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _fling = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Offset _drag = Offset.zero;
  Offset _flingFrom = Offset.zero;
  Offset _flingTo = Offset.zero;

  bool get _flipped => _flip.value >= 0.5;

  @override
  void initState() {
    super.initState();
    _fling.addListener(() => setState(() => _drag = Offset.lerp(_flingFrom, _flingTo, Curves.easeOut.transform(_fling.value))!));
    unawaited(_load());
  }

  Future<void> _load() async {
    final cards = await ref.read(flashcardsProvider(widget.deck).future);
    if (!mounted) return;
    setState(() => _cards = widget.mode == ReviewMode.practice ? practiceOrder(cards) : cards);
  }

  @override
  void dispose() {
    _flip.dispose();
    _fling.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    Haptics.choose();
    if (_flipped) {
      unawaited(_flip.reverse());
    } else {
      unawaited(_flip.forward());
    }
  }

  /// Moves past the current card; [direction] +1 flies it off right, -1 left.
  Future<void> _advance(int direction, {bool? knewIt}) async {
    final cards = _cards!;
    final card = cards[_index];
    if (knewIt != null) {
      Haptics.commit();
      if (knewIt) _known++;
      unawaited(ref.read(cardsProvider).update(reviewed(card, knewIt: knewIt)));
    }
    final width = MediaQuery.sizeOf(context).width;
    _flingFrom = _drag;
    _flingTo = Offset(direction * width * 1.3, _drag.dy + 40);
    await _fling.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _drag = Offset.zero;
      _flip.value = 0;
      if (_index + 1 >= cards.length) {
        _done = true;
      } else {
        _index++;
      }
    });
  }

  void _back() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _flip.value = 0;
      _drag = Offset.zero;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final width = MediaQuery.sizeOf(context).width;
    final far = _drag.dx.abs() > width * 0.28 || d.velocity.pixelsPerSecond.dx.abs() > 900;
    if (!far) {
      _flingFrom = _drag;
      _flingTo = Offset.zero;
      unawaited(_fling.forward(from: 0).then((_) => setState(() => _drag = Offset.zero)));
      return;
    }
    final right = _drag.dx > 0 || (_drag.dx == 0 && d.velocity.pixelsPerSecond.dx > 0);
    if (widget.mode == ReviewMode.practice) {
      unawaited(_advance(right ? 1 : -1, knewIt: right));
    } else if (right && _index > 0) {
      // Replay: swipe right goes back a card, like turning back a page.
      _back();
    } else if (!right) {
      unawaited(_advance(-1));
    } else {
      _flingFrom = _drag;
      _flingTo = Offset.zero;
      unawaited(_fling.forward(from: 0).then((_) => setState(() => _drag = Offset.zero)));
    }
  }

  void _restart() {
    setState(() {
      _index = 0;
      _known = 0;
      _done = false;
      _cards = null;
      _flip.value = 0;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final books = ref.watch(libraryProvider).valueOrNull ?? const <Book>[];
    final title = books.where((b) => b.id == widget.deck.bookId).firstOrNull?.title ?? widget.deck.bookTitle ?? '';
    final ink = deckInk(title);
    final cards = _cards;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.maybePop(context)),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: cards == null || cards.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: _done ? 1 : _index / cards.length),
                            duration: const Duration(milliseconds: 300),
                            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 5, color: ink, backgroundColor: c.rule),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${min(_index + 1, cards.length)} / ${cards.length}', style: EnglishText.label(c.inkMuted, size: 12.5)),
                    ],
                  ),
                ),
              ),
      ),
      body: cards == null
          ? const Center(child: CircularProgressIndicator())
          : cards.isEmpty
              ? Center(child: Text(t.cardsEmptyTitle, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)))
              : _done
                  ? _Summary(
                      known: _known,
                      total: cards.length,
                      practice: widget.mode == ReviewMode.practice,
                      onAgain: _restart,
                      onFinish: () {
                        unawaited(Navigator.maybePop(context));
                        ref.read(interstitialsProvider).onBreak(AdBreak.finishedReview);
                      },
                    )
                  : SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                              child: _stack(cards, ink, t.tapToFlip),
                            ),
                          ),
                          _controls(c, scale),
                        ],
                      ),
                    ),
    );
  }

  Widget _stack(List<Flashcard> cards, Color ink, String hint) {
    final width = MediaQuery.sizeOf(context).width;
    // How far the top card has travelled, 0–1: the cards behind rise to meet it.
    final lift = (_drag.dx.abs() / (width * 0.6)).clamp(0.0, 1.0);
    final c = context.colors;
    return LayoutBuilder(
      builder: (_, box) => Stack(
        clipBehavior: Clip.none,
        children: [
          for (var depth = 2; depth >= 1; depth--)
            if (_index + depth < cards.length)
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, (depth - lift) * 14),
                  child: Transform.scale(
                    scale: 1 - (depth - lift) * 0.05,
                    alignment: Alignment.bottomCenter,
                    child: Opacity(
                      opacity: depth == 2 ? 0.6 : 0.85,
                      child: IndexCard(ink: ink, elevated: false, child: const SizedBox.expand()),
                    ),
                  ),
                ),
              ),
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleFlip,
              onPanUpdate: (d) => setState(() => _drag += d.delta),
              onPanEnd: _onDragEnd,
              child: Transform.translate(
                offset: _drag,
                child: Transform.rotate(
                  angle: _drag.dx / width * 0.25,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _flip,
                          builder: (_, _) {
                            final angle = _flip.value * pi;
                            final back = angle > pi / 2;
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0012)
                                ..rotateY(angle),
                              child: back
                                  ? Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()..rotateY(pi),
                                      child: CardBack(card: cards[_index], ink: ink),
                                    )
                                  : CardFront(card: cards[_index], ink: ink, hint: hint),
                            );
                          },
                        ),
                      ),
                      if (widget.mode == ReviewMode.practice && _drag.dx.abs() > 12)
                        Positioned(
                          top: 26,
                          left: _drag.dx > 0 ? 24 : null,
                          right: _drag.dx < 0 ? 24 : null,
                          child: _Stamp(
                            text: _drag.dx > 0 ? ref.read(stringsProvider).gotIt : ref.read(stringsProvider).again,
                            color: _drag.dx > 0 ? const Color(0xFF3F7D4A) : c.accent,
                            opacity: lift,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(ArthColors c, double scale) {
    final strings = ref.read(stringsProvider);
    final label = uiLabel(hindi: strings.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 15);
    if (widget.mode == ReviewMode.replay) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: _index == 0 ? null : _back,
              icon: const Icon(Icons.chevron_left_rounded),
              style: IconButton.styleFrom(side: BorderSide(color: c.rule), fixedSize: const Size(56, 56)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleFlip,
                icon: const Icon(Icons.flip_rounded, size: 18),
                label: Text(strings.tapToFlip, style: label),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.ink,
                  side: BorderSide(color: c.rule),
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              onPressed: () => _advance(-1),
              icon: const Icon(Icons.chevron_right_rounded),
              style: IconButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.paper, fixedSize: const Size(56, 56)),
            ),
          ],
        ),
      );
    }
    // Practice: rating only makes sense once you've seen the answer.
    return AnimatedBuilder(
      animation: _flip,
      builder: (_, _) {
        final shown = _flip.value > 0.5;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: shown ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: shown ? () => _advance(-1, knewIt: false) : _toggleFlip,
                    icon: Icon(Icons.replay_rounded, size: 18, color: c.accent),
                    label: Text(strings.again, style: label.copyWith(color: c.accent)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.accent.withValues(alpha: 0.6)),
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: shown ? () => _advance(1, knewIt: true) : _toggleFlip,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(strings.gotIt, style: label.copyWith(color: c.paper)),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.ink,
                      foregroundColor: c.paper,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Got it" / "Again" pressed onto the card as it's dragged.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.text, required this.color, required this.opacity});

  final String text;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: -0.12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: color, width: 2.5), borderRadius: BorderRadius.circular(8)),
            child: Text(text, style: EnglishText.heading(color)),
          ),
        ),
      );
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.known, required this.total, required this.practice, required this.onAgain, required this.onFinish});

  final int known;
  final int total;
  final bool practice;
  final VoidCallback onAgain;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 48, color: c.marigold),
            const SizedBox(height: 16),
            Text(t.reviewDone, style: uiTitle(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              practice ? t.reviewSummary(known, total) : t.cardCount(total),
              style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton(onPressed: onFinish, child: Text(t.finish)),
            const SizedBox(height: 8),
            TextButton(onPressed: onAgain, style: TextButton.styleFrom(foregroundColor: c.accent), child: Text(t.reviewAgain)),
          ],
        ),
      ),
    );
  }
}
