// When to remind a reader to review their cards: a set time after each card
// is made (by default a day, 42 hours, a week), with cards that fall due
// close together sharing one notification, and nothing in the night.

import 'package:arth/data/local_store.dart';

/// The default reminder times, in hours after a card is made.
const defaultReminderHours = [24, 42, 168];

/// The times a reader can pick from in Settings, in hours.
const reminderHourChoices = [4, 8, 12, 24, 36, 42, 48, 72, 120, 168, 240, 336, 720];

/// One notification: the cards it's about, and when it fires.
class ReminderSlot {
  const ReminderSlot({required this.at, required this.cards});

  final DateTime at;
  final List<Flashcard> cards;

  /// Book titles, most cards first.
  List<String> get books {
    final counts = <String, int>{};
    for (final c in cards) {
      final title = c.bookTitle;
      if (title != null && title.isNotEmpty) counts[title] = (counts[title] ?? 0) + 1;
    }
    return counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }
}

/// Quiet hours: nothing before [quietMorning] or from [quietNight] on (local time).
const quietMorning = 9;
const quietNight = 22;

/// A time moved out of the night to the next morning at [quietMorning].
DateTime outOfQuietHours(DateTime t) {
  if (t.hour >= quietNight) return DateTime(t.year, t.month, t.day + 1, quietMorning);
  if (t.hour < quietMorning) return DateTime(t.year, t.month, t.day, quietMorning);
  return t;
}

/// The reminders still to come for [cards], soonest first, at most [max]
/// (iOS keeps 64 pending notifications per app). Reminders within [window]
/// of the first in a group are sent together, at the latest of them, so
/// no card is reminded of early.
List<ReminderSlot> planReminders({
  required List<Flashcard> cards,
  required List<int> hours,
  required DateTime now,
  Duration window = const Duration(hours: 2),
  int max = 40,
}) {
  final due = <({DateTime at, Flashcard card})>[];
  for (final card in cards) {
    for (final h in hours.toSet()) {
      final at = outOfQuietHours(card.createdAt.add(Duration(hours: h)));
      if (at.isAfter(now)) due.add((at: at, card: card));
    }
  }
  due.sort((a, b) => a.at.compareTo(b.at));

  final slots = <ReminderSlot>[];
  var i = 0;
  while (i < due.length && slots.length < max) {
    final start = due[i].at;
    final group = <Flashcard>[];
    final seen = <String>{};
    var at = start;
    while (i < due.length && !due[i].at.isAfter(start.add(window))) {
      if (seen.add(due[i].card.id)) group.add(due[i].card);
      at = due[i].at;
      i++;
    }
    slots.add(ReminderSlot(at: at, cards: group));
  }
  return slots;
}
