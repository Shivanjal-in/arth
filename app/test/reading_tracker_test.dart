import 'package:arth/core/reading_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime clock;
  late List<ReadingSession> saved;
  late ReadingTracker tracker;

  setUp(() {
    clock = DateTime(2026, 10, 1, 9);
    saved = [];
    tracker = ReadingTracker(bookId: 7, sink: (s) async => saved.add(s), now: () => clock);
  });

  void after(int seconds) => clock = clock.add(Duration(seconds: seconds));

  test('times each page and writes a session when the book closes', () async {
    tracker
      ..visit(1);
    after(40);
    tracker.visit(2);
    after(65);
    await tracker.end();
    expect(saved, hasLength(1));
    expect(saved.single.bookId, 7);
    expect(saved.single.pages.map((p) => (p.key, p.ms)), [(1, 40000), (2, 65000)]);
    expect(saved.single.activeMs, 105000);
  });

  test('flicking past a page, or leaving the phone on one, is not reading', () async {
    tracker.visit(1);
    after(1);
    tracker.visit(2); // flicked
    after(30);
    tracker.visit(3);
    after(60 * 20); // put the phone down
    tracker.visit(4);
    after(20);
    await tracker.end();
    expect(saved.single.pages.map((p) => p.key), [2, 4]);
  });

  test('time in the background does not count, and the session is written out', () async {
    tracker.visit(1);
    after(30);
    await tracker.pause();
    after(3600);
    tracker.resume();
    after(20);
    tracker.visit(2);
    after(10);
    await tracker.end();
    expect(saved, hasLength(2));
    expect(saved.first.pages.single.ms, 30000);
    expect(saved.last.pages.map((p) => p.ms), [20000, 10000]);
  });

  test('a book closed without reading anything writes nothing', () async {
    tracker.visit(1);
    after(2);
    await tracker.end();
    expect(saved, isEmpty);
  });
}
