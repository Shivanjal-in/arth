// Candidate phrase windows around a tapped token.
//
// Mirrors the server's /phrases/match rule: windows of 2–4 tokens that include
// the tapped index, longest first, then leftmost. The caller checks each
// candidate against a store (local SQLite or the API) and takes the first hit.

class PhraseWindow {
  const PhraseWindow({
    required this.start,
    required this.tokenCount,
    required this.phrase,
  });

  final int start;
  final int tokenCount;

  /// Space-joined tokens — the `phrases._id` key.
  final String phrase;
}

/// All windows of [minLen]..[maxLen] tokens covering [index], longest first.
List<PhraseWindow> phraseWindows(
  List<String> tokens,
  int index, {
  int minLen = 2,
  int maxLen = 4,
}) {
  final out = <PhraseWindow>[];
  for (var len = maxLen; len >= minLen; len--) {
    for (var start = index - len + 1; start <= index; start++) {
      if (start < 0 || start + len > tokens.length) continue;
      final slice = tokens.sublist(start, start + len);
      if (slice.any((t) => t.isEmpty)) continue;
      out.add(
        PhraseWindow(start: start, tokenCount: len, phrase: slice.join(' ')),
      );
    }
  }
  return out;
}
