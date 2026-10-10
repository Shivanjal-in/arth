// What the reading habit screen shows, worked out from the page timings.

/// A day with at least this much reading counts toward the streak.
const int kStreakMinMs = 60 * 1000;

/// How one book has gone.
class BookPace {
  const BookPace({
    required this.bookId,
    required this.title,
    required this.activeMs,
    required this.pagesRead,
    required this.avgPageMs,
    required this.firstAt,
    required this.lastAt,
    required this.readingDays,
    this.progress,
    this.finishedAt,
  });

  final int bookId;
  final String title;

  /// Time actually spent reading it.
  final int activeMs;

  /// Different pages looked at (a page read twice counts once).
  final int pagesRead;

  /// Average time on a page.
  final int avgPageMs;
  final DateTime firstAt;
  final DateTime lastAt;

  /// Days on which it was read.
  final int readingDays;
  final double? progress;
  final DateTime? finishedAt;

  bool get isFinished => finishedAt != null;

  /// From first reading to the end, on the calendar.
  Duration? get calendarToFinish => finishedAt?.difference(firstAt);

  /// Reading time still to go at the pace so far, once there's enough to tell.
  Duration? get remaining {
    final p = progress;
    if (isFinished || p == null || p < 0.03 || p >= 1 || activeMs < 5 * 60 * 1000) return null;
    return Duration(milliseconds: (activeMs * (1 - p) / p).round());
  }
}

class ReadingStats {
  const ReadingStats({
    required this.todayMs,
    required this.streak,
    required this.bestStreak,
    required this.lastDays,
    required this.totalMs,
    required this.totalPages,
    required this.avgPageMs,
    required this.bestHour,
    required this.books,
  });

  /// [dayMs] by calendar day (midnight local), [hourMs] 24 slots by hour of
  /// day, [books] from the page log, most recently read first.
  factory ReadingStats.build({
    required Map<DateTime, int> dayMs,
    required List<int> hourMs,
    required List<BookPace> books,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime back(int n) => DateTime(today.year, today.month, today.day - n);
    bool counts(DateTime d) => (dayMs[d] ?? 0) >= kStreakMinMs;

    // The run ending today, or yesterday if today hasn't been read yet.
    var streak = 0;
    var d = counts(today) ? today : back(1);
    while (counts(d)) {
      streak++;
      d = DateTime(d.year, d.month, d.day - 1);
    }

    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in (dayMs.keys.where(counts).toList()..sort())) {
      run = previous != null && DateTime(previous.year, previous.month, previous.day + 1) == day ? run + 1 : 1;
      if (run > best) best = run;
      previous = day;
    }

    final total = dayMs.values.fold(0, (a, b) => a + b);
    final pages = books.fold(0, (a, b) => a + b.pagesRead);
    final weighted = books.fold<int>(0, (a, b) => a + b.avgPageMs * b.pagesRead);

    int? bestHour;
    var most = 0;
    for (var h = 0; h < hourMs.length; h++) {
      if (hourMs[h] > most) {
        most = hourMs[h];
        bestHour = h;
      }
    }

    return ReadingStats(
      todayMs: dayMs[today] ?? 0,
      streak: streak,
      bestStreak: best,
      lastDays: [for (var i = 6; i >= 0; i--) (day: back(i), ms: dayMs[back(i)] ?? 0)],
      totalMs: total,
      totalPages: pages,
      avgPageMs: pages == 0 ? 0 : (weighted / pages).round(),
      bestHour: bestHour,
      books: books,
    );
  }

  final int todayMs;

  /// Days in a row, counting back from today (or yesterday).
  final int streak;
  final int bestStreak;

  /// The last seven days, oldest first, ending today.
  final List<({DateTime day, int ms})> lastDays;
  final int totalMs;
  final int totalPages;

  /// Average time on a page, over every book.
  final int avgPageMs;

  /// The hour of day (0–23) with the most reading, or null before any.
  final int? bestHour;
  final List<BookPace> books;

  bool get isEmpty => totalMs == 0;
}
