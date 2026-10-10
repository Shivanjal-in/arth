import 'package:arth/core/reading_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 10, 20);
  DateTime day(int d) => DateTime(2026, 10, d);
  const minute = 60 * 1000;

  ReadingStats build(Map<DateTime, int> days, {List<BookPace> books = const []}) =>
      ReadingStats.build(dayMs: days, hourMs: List.filled(24, 0)..[21] = 5, books: books, now: now);

  test('the streak counts back from today, or from yesterday while today is still empty', () {
    expect(build({day(10): 5 * minute, day(9): 2 * minute, day(8): minute, day(6): 9 * minute}).streak, 3);
    expect(build({day(9): 5 * minute, day(8): 5 * minute}).streak, 2);
    expect(build({day(8): 5 * minute}).streak, 0);
    expect(build({day(10): 30 * 1000}).streak, 0); // under a minute doesn't count
  });

  test('best streak, today, the week and the best hour', () {
    final s = build({day(1): minute, day(2): minute, day(3): minute, day(4): minute, day(7): minute, day(10): 4 * minute});
    expect(s.bestStreak, 4);
    expect(s.todayMs, 4 * minute);
    expect(s.lastDays.length, 7);
    expect(s.lastDays.last.day, day(10));
    expect(s.lastDays.first.day, day(4));
    expect(s.bestHour, 21);
  });

  test('a book still being read estimates what is left from its pace', () {
    BookPace book({double? progress, DateTime? finished, int ms = 60 * minute}) => BookPace(
          bookId: 1, title: 'Emma', activeMs: ms, pagesRead: 30, avgPageMs: 2 * minute,
          firstAt: day(1), lastAt: day(9), readingDays: 4, progress: progress, finishedAt: finished,
        );
    expect(book(progress: 0.25).remaining, const Duration(minutes: 180));
    expect(book(progress: 0.01).remaining, isNull);
    expect(book(progress: 0.5, finished: day(9)).remaining, isNull);
    expect(book(progress: 1, finished: day(9)).calendarToFinish, const Duration(days: 8));
  });

  test('average page time is weighted by pages read', () {
    BookPace b(int pages, int avg) => BookPace(
          bookId: pages, title: 'b', activeMs: pages * avg, pagesRead: pages, avgPageMs: avg,
          firstAt: day(1), lastAt: day(2), readingDays: 1,
        );
    final s = build({day(10): minute}, books: [b(10, 60 * 1000), b(30, 120 * 1000)]);
    expect(s.totalPages, 40);
    expect(s.avgPageMs, 105 * 1000);
  });
}
