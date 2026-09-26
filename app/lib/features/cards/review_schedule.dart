// Leitner boxes: a card you know moves up a box and comes back later; one
// you miss goes back to box 0 and comes back today. Five boxes are enough
// for a book's worth of cards — the point is a quick glance, not a
// lifetime of drilling.

import 'package:arth/data/local_store.dart';

/// How long a card rests in each box before it's due again.
const List<Duration> boxIntervals = [Duration.zero, Duration(days: 1), Duration(days: 3), Duration(days: 7), Duration(days: 21)];

Flashcard reviewed(Flashcard card, {required bool knewIt, DateTime? now}) {
  final at = now ?? DateTime.now();
  final box = knewIt ? (card.box + 1).clamp(0, Flashcard.maxBox) : 0;
  return card.copyWith(box: box, dueAt: at.add(boxIntervals[box]));
}

/// The order a practice session shows cards in: due ones first (lowest box
/// first, so the shakiest come up early), then the rest in reading order.
List<Flashcard> practiceOrder(List<Flashcard> cards, {DateTime? now}) {
  final at = now ?? DateTime.now();
  bool due(Flashcard c) => c.dueAt == null || !c.dueAt!.isAfter(at);
  final dueCards = cards.where(due).toList()..sort((a, b) => a.box.compareTo(b.box));
  return [...dueCards, ...cards.where((c) => !due(c))];
}
