// Reading habit: how long pages take, how long books take, a daily goal and
// a streak — drawn from the page timings the readers log (see
// core/reading_tracker.dart).

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/reading_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _goalKey = 'reading_goal_min';
const _goalChoices = [5, 10, 15, 20, 30, 45, 60];
const _defaultGoal = 15;

final AutoDisposeFutureProvider<ReadingStats> readingStatsProvider = FutureProvider.autoDispose<ReadingStats>(
  (ref) => ref.watch(localStoreProvider).readingStats(),
);

final AutoDisposeFutureProvider<int> readingGoalProvider = FutureProvider.autoDispose<int>((ref) async {
  final saved = int.tryParse(await ref.watch(localStoreProvider).get(_goalKey) ?? '');
  return saved != null && _goalChoices.contains(saved) ? saved : _defaultGoal;
});

/// "45s", "12m", "1h 5m".
String shortDuration(int ms) {
  final s = (ms / 1000).round();
  if (s < 60) return '${s}s';
  final m = (s / 60).round();
  if (m < 60) return s % 60 == 0 || m >= 10 ? '${m}m' : '${s ~/ 60}m ${s % 60}s';
  final h = m ~/ 60;
  return m % 60 == 0 ? '${h}h' : '${h}h ${m % 60}m';
}

class ReadingHabitScreen extends ConsumerWidget {
  const ReadingHabitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final stats = ref.watch(readingStatsProvider);
    final goal = ref.watch(readingGoalProvider).valueOrNull ?? _defaultGoal;
    return Scaffold(
      appBar: AppBar(title: Text(t.readingHabit)),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(t.somethingWrong, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale))),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(readingStatsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              _TodayCard(stats: s, goalMin: goal),
              const SizedBox(height: 16),
              _WeekCard(stats: s, goalMin: goal),
              const SizedBox(height: 16),
              if (s.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(t.habitEmpty, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale), textAlign: TextAlign.center),
                )
              else ...[
                _PaceCard(stats: s),
                const SizedBox(height: 16),
                _Tips(stats: s, goalMin: goal),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(t.yourBooks, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
                ),
                for (final b in s.books) _BookRow(book: b),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.rule)),
      child: child,
    );
  }
}

/// Today against the daily goal, and the streak.
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.stats, required this.goalMin});

  final ReadingStats stats;
  final int goalMin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final goalMs = goalMin * 60 * 1000;
    final done = (stats.todayMs / goalMs).clamp(0.0, 1.0);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(value: done, strokeWidth: 8, color: c.accent, backgroundColor: c.rule),
                    ),
                    Text(shortDuration(stats.todayMs), style: EnglishText.label(c.ink, size: 15)),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.readToday, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                    Text(t.ofGoal(goalMin), style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.local_fire_department_rounded, color: stats.streak > 0 ? c.marigold : c.rule, size: 22),
                        const SizedBox(width: 4),
                        Text(t.dayStreak(stats.streak), style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 15)),
                      ],
                    ),
                    if (stats.bestStreak > stats.streak)
                      Text(t.bestStreak(stats.bestStreak), style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(t.dailyGoal, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final m in _goalChoices)
                ChoiceChip(
                  label: Text('$m ${t.minShort}'),
                  selected: m == goalMin,
                  showCheckmark: false,
                  onSelected: (_) async {
                    await ref.read(localStoreProvider).set(_goalKey, '$m');
                    ref.invalidate(readingGoalProvider);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The last seven days as bars; a day that met the goal is filled.
class _WeekCard extends ConsumerWidget {
  const _WeekCard({required this.stats, required this.goalMin});

  final ReadingStats stats;
  final int goalMin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final goalMs = goalMin * 60 * 1000;
    final top = stats.lastDays.fold<int>(goalMs, (m, d) => d.ms > m ? d.ms : m);
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.thisWeek, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in stats.lastDays)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(d.ms == 0 ? '' : shortDuration(d.ms), style: EnglishText.label(c.inkMuted, size: 10)),
                        const SizedBox(height: 3),
                        Container(
                          width: 22,
                          height: (d.ms / top * 70).clamp(d.ms == 0 ? 3.0 : 6.0, 70.0),
                          decoration: BoxDecoration(
                            color: d.ms >= goalMs ? c.accent : (d.ms == 0 ? c.rule : c.inkMuted),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(weekdays[d.day.weekday - 1], style: EnglishText.label(c.ink, size: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How fast pages go, over every book.
class _PaceCard extends ConsumerWidget {
  const _PaceCard({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: EnglishText.word(c.ink, size: 22)),
              const SizedBox(height: 2),
              Text(label, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 12.5), textAlign: TextAlign.center),
            ],
          ),
        );
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stat(shortDuration(stats.avgPageMs), t.perPage),
          stat(shortDuration(stats.totalMs), t.totalReading),
          stat('${stats.totalPages}', t.pagesRead),
        ],
      ),
    );
  }
}

/// A few nudges, from the numbers.
class _Tips extends ConsumerWidget {
  const _Tips({required this.stats, required this.goalMin});

  final ReadingStats stats;
  final int goalMin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final goalMs = goalMin * 60 * 1000;
    final tips = <String>[
      if (stats.todayMs >= goalMs)
        t.tipGoalMet
      else if (stats.streak > 0 && stats.todayMs < kStreakMinMs)
        t.tipKeepStreak(stats.streak)
      else
        t.tipToGo(shortDuration(goalMs - stats.todayMs)),
      if (stats.bestHour != null) t.tipBestHour(_hourLabel(stats.bestHour!)),
    ];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined, size: 18, color: c.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tip, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 15))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _hourLabel(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12 ${h < 12 ? 'AM' : 'PM'}';
  }
}

class _BookRow extends ConsumerWidget {
  const _BookRow({required this.book});

  final BookPace book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final lines = <String>[
      t.pacePerPage(shortDuration(book.avgPageMs)),
      t.timeAndDays(shortDuration(book.activeMs), book.readingDays),
    ];
    final remaining = book.remaining;
    final span = book.calendarToFinish;
    final status = book.isFinished
        ? t.finishedIn(span == null ? 1 : (span.inDays < 1 ? 1 : span.inDays + 1), shortDuration(book.activeMs))
        : (remaining == null ? null : t.timeLeft(shortDuration(remaining.inMilliseconds)));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rule))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(book.title, style: EnglishText.word(c.ink, size: 17), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (book.isFinished) Icon(Icons.check_circle_rounded, color: c.accent, size: 18),
            ],
          ),
          const SizedBox(height: 2),
          Text(lines.join('  ·  '), style: EnglishText.label(c.inkMuted, size: 12)),
          if (status != null) Text(status, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14)),
        ],
      ),
    );
  }
}
