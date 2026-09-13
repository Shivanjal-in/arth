import 'package:arth/core/text/phrase_windows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tokens = ['a', 'single', 'man', 'in', 'possession', 'of', 'a', 'good'];

  test('longest windows first, all covering the index', () {
    final w = phraseWindows(tokens, 3); // "in"
    expect(w.first.tokenCount, 4);
    expect(w.map((x) => x.phrase).toList(), [
      'a single man in',
      'single man in possession',
      'man in possession of',
      'in possession of a',
      'single man in',
      'man in possession',
      'in possession of',
      'man in',
      'in possession',
    ]);
    for (final x in w) {
      expect(x.start <= 3 && x.start + x.tokenCount > 3, isTrue);
    }
  });

  test('clips at the edges', () {
    final w = phraseWindows(tokens, 0);
    expect(w.map((x) => x.phrase).toList(), [
      'a single man in',
      'a single man',
      'a single',
    ]);
    final last = phraseWindows(tokens, tokens.length - 1);
    expect(last.first.phrase, 'possession of a good');
    expect(last.last.phrase, 'a good');
  });

  test('skips windows containing an empty (punctuation-only) token', () {
    final w = phraseWindows(['in', 'want', '', 'of'], 1);
    expect(w.map((x) => x.phrase).toList(), ['in want']);
  });

  test('single token yields nothing', () {
    expect(phraseWindows(['alone'], 0), isEmpty);
  });
}
