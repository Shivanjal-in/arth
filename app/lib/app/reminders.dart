// Keeps the phone's scheduled review reminders in step with the cards and
// the reminder settings: whenever either changes, the pending reminders are
// replaced by a fresh plan (card_reminders.dart). They're scheduled on the
// device, so they come without an account, a server, or a connection.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/data/card_reminders.dart';
import 'package:arth/data/local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

final localNotificationsProvider = Provider<LocalNotifications>((_) => LocalNotifications());

final cardRemindersProvider = Provider<CardReminders>((ref) {
  final reminders = CardReminders(ref);
  ref
    ..listen(decksProvider, (_, _) => reminders.reschedule())
    ..listen(settingsProvider.select((s) => (s.cardReminders, s.reminderHours.join(','), s.language)), (_, _) => reminders.reschedule())
    ..onDispose(reminders.dispose);
  reminders.reschedule();
  return reminders;
});

class CardReminders {
  CardReminders(this._ref);

  final Ref _ref;
  Timer? _debounce;

  /// Our notification ids: [_firstId], [_firstId] + 1, … (pushes use
  /// others). planReminders caps the count well under 100.
  static const _firstId = 7000;

  /// Replan soon; several changes in a row (a sync, a saved deck) plan once.
  void reschedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(_apply()));
  }

  void dispose() => _debounce?.cancel();

  Future<void> _apply() async {
    final local = _ref.read(localNotificationsProvider);
    if (!local.ready) return;
    try {
      final pending = await local.plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= _firstId && p.id < _firstId + 100) await local.plugin.cancel(id: p.id);
      }
      final settings = _ref.read(settingsProvider);
      if (!settings.cardReminders) return;
      final store = _ref.read(localStoreProvider);
      final slots = planReminders(cards: await store.flashcards(), hours: settings.reminderHours, now: DateTime.now());
      if (slots.isEmpty) return;

      // The first time there's something to remind of, ask to notify.
      if (await store.get('reminder_permission_asked') == null) {
        await store.set('reminder_permission_asked', 'true');
        await local.requestPermission();
      }
      final t = _ref.read(stringsProvider);
      for (final (i, slot) in slots.indexed) {
        final books = slot.books;
        await local.plugin.zonedSchedule(
          id: _firstId + i,
          scheduledDate: tz.TZDateTime.from(slot.at, tz.UTC),
          title: t.reminderTitle,
          body: t.reminderBody(slot.cards.length, books.firstOrNull, books.length <= 1 ? 0 : books.length - 1),
          notificationDetails: LocalNotifications.details,
          // Inexact is fine for a reminder, and needs no exact-alarm permission.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: _routeFor(slot),
        );
      }
    } on Exception catch (e) {
      debugPrint('card reminders: $e');
    }
  }

  /// One book: practise its cards. Several: the Cards tab.
  static String _routeFor(ReminderSlot slot) {
    final first = slot.cards.first;
    final oneBook = slot.cards.every((c) => c.bookId == first.bookId && c.bookTitle == first.bookTitle);
    if (!oneBook) return '/cards';
    return Uri(
      path: '/deck/review',
      queryParameters: {'mode': 'practice', 'book': ?first.bookId?.toString(), 'title': ?first.bookTitle},
    ).toString();
  }
}
