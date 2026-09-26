import 'package:arth/data/highlight_plan.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

Highlight hl(int id, int start, int end, HighlightColor color) => Highlight(
      id: id,
      bookId: 1,
      page: 1,
      startWord: start,
      endWord: end,
      text: '',
      color: color,
      createdAt: DateTime(2026),
    );

void main() {
  const pink = HighlightColor.pink;
  const blue = HighlightColor.blue;

  test('nothing there: the new highlight as asked', () {
    final p = planHighlight(const [], 3, 7, pink);
    expect(p.add, (start: 3, end: 7));
    expect(p.remove, isEmpty);
    expect(p.trim, isEmpty);
    expect(p.split, isEmpty);
  });

  test('the same line again in the same colour is one highlight, not two', () {
    final p = planHighlight([hl(1, 3, 7, pink)], 3, 7, pink);
    expect(p.add, (start: 3, end: 7));
    expect(p.remove, [1]);
  });

  test('same colour overlapping or touching merges, reaching along a chain', () {
    final p = planHighlight([hl(1, 0, 4, pink), hl(2, 9, 12, pink), hl(3, 20, 22, pink)], 3, 8, pink);
    expect(p.add, (start: 0, end: 12)); // 0–4 overlaps, 9–12 touches the grown range
    expect(p.remove, unorderedEquals([1, 2]));
  });

  test('another colour fully under the new one goes', () {
    final p = planHighlight([hl(1, 4, 6, blue)], 3, 8, pink);
    expect(p.remove, [1]);
    expect(p.trim, isEmpty);
  });

  test('another colour partly under is trimmed on the covered side', () {
    final p = planHighlight([hl(1, 0, 5, blue), hl(2, 7, 12, blue)], 3, 8, pink);
    expect(p.trim, [(id: 1, range: (start: 0, end: 2)), (id: 2, range: (start: 9, end: 12))]);
    expect(p.remove, isEmpty);
  });

  test('a highlight inside another colour splits it around', () {
    final p = planHighlight([hl(1, 0, 20, blue)], 5, 8, pink);
    expect(p.trim, [(id: 1, range: (start: 0, end: 4))]);
    expect(p.split, [(range: (start: 9, end: 20), color: blue)]);
  });

  test('merging first, then the grown range clears other colours', () {
    final p = planHighlight([hl(1, 0, 4, pink), hl(2, 1, 2, blue)], 4, 6, pink);
    expect(p.add, (start: 0, end: 6));
    expect(p.remove, unorderedEquals([1, 2]));
  });
}
