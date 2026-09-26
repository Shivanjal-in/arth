import 'package:arth/features/ads/interstitials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 9, 25, 10);
  DateTime at(int minutes) => start.add(Duration(minutes: minutes));

  test('nothing in the first two minutes after launch', () {
    final p = AdPacing(appStartedAt: start);
    expect(p.allows(AdBreak.finishedReview, now: at(1)), isFalse);
    expect(p.allows(AdBreak.finishedReview, now: at(3)), isTrue);
  });

  test('a book only counts as a break after two minutes of reading', () {
    final p = AdPacing(appStartedAt: start);
    expect(p.allows(AdBreak.closedBook, now: at(10), readFor: const Duration(seconds: 40)), isFalse);
    expect(p.allows(AdBreak.closedBook, now: at(10), readFor: const Duration(minutes: 5)), isTrue);
    expect(p.allows(AdBreak.closedBook, now: at(10)), isFalse, reason: 'unknown reading time');
  });

  test('at most one every six minutes', () {
    final p = AdPacing(appStartedAt: start)..lastShownAt = at(10);
    expect(p.allows(AdBreak.finishedReview, now: at(14)), isFalse);
    expect(p.allows(AdBreak.finishedReview, now: at(16)), isTrue);
  });
}
