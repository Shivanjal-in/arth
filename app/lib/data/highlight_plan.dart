// What adding a highlight does to the ones already in the same block (a PDF
// page, or one EPUB paragraph): highlights never stack.
//
// - Same colour, overlapping or touching: they become one highlight.
// - Another colour under the new one: the new colour wins there — covered
//   highlights go, partly covered ones are trimmed, and one the new
//   highlight sits inside is split around it.

import 'package:arth/data/local_store.dart';

typedef WordRange = ({int start, int end});

class HighlightPlan {
  const HighlightPlan({required this.add, required this.remove, required this.trim, required this.split});

  /// The new highlight, grown to take in same-colour neighbours.
  final WordRange add;

  /// Highlights to delete (merged into [add], or covered by it).
  final List<int> remove;

  /// Highlights that keep their id and colour on a shorter range.
  final List<({int id, WordRange range})> trim;

  /// The right-hand part of a highlight [add] was placed inside; its left
  /// part is in [trim].
  final List<({WordRange range, HighlightColor color})> split;
}

/// [block] is the highlights on the same page/block as the new range.
HighlightPlan planHighlight(List<Highlight> block, int start, int end, HighlightColor color) {
  var s = start;
  var e = end;
  final remove = <int>[];

  // Merge same-colour highlights that overlap or touch, until nothing more
  // joins (a merge can reach the next one along).
  var grew = true;
  while (grew) {
    grew = false;
    for (final h in block) {
      if (h.color != color || remove.contains(h.id)) continue;
      if (h.startWord <= e + 1 && h.endWord >= s - 1) {
        remove.add(h.id);
        if (h.startWord < s) s = h.startWord;
        if (h.endWord > e) e = h.endWord;
        grew = true;
      }
    }
  }

  final trim = <({int id, WordRange range})>[];
  final split = <({WordRange range, HighlightColor color})>[];
  for (final h in block) {
    if (remove.contains(h.id) || h.endWord < s || h.startWord > e) continue;
    final before = h.startWord < s;
    final after = h.endWord > e;
    if (!before && !after) {
      remove.add(h.id);
    } else if (before && after) {
      trim.add((id: h.id, range: (start: h.startWord, end: s - 1)));
      split.add((range: (start: e + 1, end: h.endWord), color: h.color));
    } else if (before) {
      trim.add((id: h.id, range: (start: h.startWord, end: s - 1)));
    } else {
      trim.add((id: h.id, range: (start: e + 1, end: h.endWord)));
    }
  }
  return HighlightPlan(add: (start: s, end: e), remove: remove, trim: trim, split: split);
}
