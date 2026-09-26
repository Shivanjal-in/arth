import 'package:arth/data/card_reminders.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

Flashcard card(String id, DateTime made, {String book = 'Emma'}) =>
    Flashcard(id: id, kind: CardKind.word, front: id, createdAt: made, updatedAt: made, bookTitle: book);

void main() {
  const hours = defaultReminderHours; // 24, 42, 168

  test('one card: a day, 42 hours and a week after it was made', () {
    final made = DateTime(2026, 9, 1, 14);
    final slots = planReminders(cards: [card('a', made)], hours: hours, now: made);
    expect(slots.map((s) => s.at), [
      DateTime(2026, 9, 2, 14), // +24h
      DateTime(2026, 9, 3, 9), // +42h is 8 am: moved to 9
      DateTime(2026, 9, 8, 14), // +1 week
    ]);
  });

  test('nothing between 10 pm and 9 am', () {
    expect(outOfQuietHours(DateTime(2026, 9, 1, 23, 30)), DateTime(2026, 9, 2, 9));
    expect(outOfQuietHours(DateTime(2026, 9, 1, 3)), DateTime(2026, 9, 1, 9));
    expect(outOfQuietHours(DateTime(2026, 9, 1, 21, 59)), DateTime(2026, 9, 1, 21, 59));
  });

  test('cards made in one sitting share a reminder, sent once the last is due', () {
    final start = DateTime(2026, 9, 1, 14);
    final cards = [
      card('a', start),
      card('b', start.add(const Duration(minutes: 40)), book: 'Kim'),
      card('c', start.add(const Duration(minutes: 90))),
    ];
    final first = planReminders(cards: cards, hours: const [24], now: start).single;
    expect(first.cards.map((c) => c.id), ['a', 'b', 'c']);
    expect(first.at, DateTime(2026, 9, 2, 15, 30));
    expect(first.books, ['Emma', 'Kim']); // most cards first
  });

  test('reminders already past are dropped', () {
    final made = DateTime(2026, 9, 1, 14);
    final slots = planReminders(cards: [card('a', made)], hours: hours, now: DateTime(2026, 9, 5));
    expect(slots.single.at, DateTime(2026, 9, 8, 14));
  });

  test('capped at the soonest few', () {
    final made = DateTime(2026, 9, 1, 12);
    final cards = [for (var i = 0; i < 30; i++) card('$i', made.add(Duration(days: i)))];
    final slots = planReminders(cards: cards, hours: hours, now: made, max: 10);
    expect(slots, hasLength(10));
    expect(slots.first.at.isBefore(slots.last.at), isTrue);
  });
}
