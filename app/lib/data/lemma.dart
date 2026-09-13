// Lemma resolution and spelling suggestions, mirroring the server's
// exact → forms → lowercase → strip 's order so local and remote agree.

import 'dart:math' as math;

import 'package:arth/core/models/contracts.dart';

abstract class LemmaSource {
  Future<DictionaryEntry?> entry(String word);
  Future<String?> formLemma(String form);
}

class Resolved {
  const Resolved(this.entry, this.lemma, this.via);

  final DictionaryEntry entry;
  final String lemma;
  final String via;
}

Future<Resolved?> _tryKey(LemmaSource src, String key, String via) async {
  final direct = await src.entry(key);
  if (direct != null) return Resolved(direct, key, via);
  final lemma = await src.formLemma(key);
  if (lemma != null) {
    final e = await src.entry(lemma);
    if (e != null) return Resolved(e, lemma, '$via-form');
  }
  return null;
}

Future<Resolved?> resolveLemma(LemmaSource src, String word) async {
  final w = word.trim();
  if (w.isEmpty) return null;
  final exact = await _tryKey(src, w, 'exact');
  if (exact != null) return exact;
  final lower = w.toLowerCase();
  if (lower != w) {
    final hit = await _tryKey(src, lower, 'lowercase');
    if (hit != null) return hit;
  }
  if (lower.endsWith("'s") && lower.length > 2) {
    final hit = await _tryKey(src, lower.substring(0, lower.length - 2), 'possessive');
    if (hit != null) return hit;
  }
  return null;
}

/// Standard Levenshtein distance.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(
        math.min(cur[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// Closest headwords to [word] by edit distance, computed on-device.
/// Cheap filter first (length within ±2), then a full distance on the rest.
List<String> suggest(
  String word,
  Iterable<String> vocabulary, {
  int limit = 5,
  int maxDistance = 2,
}) {
  final w = word.toLowerCase();
  final scored = <(int, String)>[];
  for (final v in vocabulary) {
    if ((v.length - w.length).abs() > maxDistance) continue;
    final d = levenshtein(w, v);
    if (d <= maxDistance) scored.add((d, v));
  }
  scored.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  return scored.take(limit).map((s) => s.$2).toList();
}
