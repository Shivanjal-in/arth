import 'dart:ui';

import 'package:arth/core/normalize.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lays each character out on a 10×10 grid, one line per '\n'.
PageTextIndex build(String text) {
  final rects = <Rect>[];
  var x = 0.0;
  var y = 0.0;
  for (final ch in text.split('')) {
    if (ch == '\n') {
      rects.add(Rect.zero);
      x = 0;
      y += 10;
    } else {
      rects.add(Rect.fromLTWH(x, y, 10, 10));
      x += 10;
    }
  }
  return PageTextIndex.build(text, rects);
}

void main() {
  ocrTests();
  test('words carry rects and keys', () {
    final idx = build('It is a truth, "universally"');
    expect(idx.words.map((w) => w.text), ['It', 'is', 'a', 'truth,', '"universally"']);
    expect(idx.words[3].key, 'truth');
    expect(idx.words[4].key, 'universally');
    expect(idx.words[3].rect, const Rect.fromLTWH(80, 0, 60, 10));
  });

  test('hit test with tolerance', () {
    final idx = build('It is');
    expect(idx.wordAt(const Offset(35, 5))?.text, 'is'); // on "i"
    expect(idx.wordAt(const Offset(29, 5))?.text, 'is'); // just left, in margin
    expect(idx.wordAt(const Offset(25, 5)), isNull); // middle of the gap
    expect(idx.wordAt(const Offset(200, 5)), isNull);
  });

  test('sentence boundaries: terminal + capital, not abbreviations', () {
    final idx = build(
      'Mr. Darcy came. He sat down! Did he? "Yes." J. K. said no. the end',
    );
    final sentences = idx.sentences
        .map((s) => idx.words.sublist(s.firstWord, s.lastWord + 1).map((w) => w.text).join(' '))
        .toList();
    expect(sentences, [
      'Mr. Darcy came.',
      'He sat down!',
      'Did he?',
      '"Yes."',
      'J. K. said no. the end',
    ]);
  });

  test('paragraph break is a boundary even without punctuation', () {
    final idx = build('a heading\n\nThe body starts');
    expect(idx.sentences.length, 2);
  });

  test('raw sentence joins hyphenated line breaks through normalize', () {
    final idx = build('a single man in pos-\nsession of a good fortune, must be.');
    final s = idx.sentenceOf(idx.words.length - 1);
    expect(
      normalizeSentence(idx.rawSentence(s)),
      'a single man in possession of a good fortune, must be.',
    );
  });

  test('tokensAround is clipped to the sentence', () {
    final idx = build('First one. It is a truth universally acknowledged. Next.');
    final truth = idx.words.indexWhere((w) => w.text == 'truth');
    final t = idx.tokensAround(truth);
    expect(t.tokens, ['it', 'is', 'a', 'truth', 'universally', 'acknowledged']);
    expect(t.index, 3);
  });

  test('page edge flags', () {
    expect(build('continues here.').startsMidSentence, isTrue);
    expect(build('Starts here').endsMidSentence, isTrue);
    expect(build('Starts here.').endsMidSentence, isFalse);
  });
}

void ocrTests() {
  test('fromLines: words carry their OCR boxes; lines break sentences and join hyphens', () {
    const r1 = Rect.fromLTWH(0, 0, 40, 10);
    const r2 = Rect.fromLTWH(50, 0, 60, 10);
    const r3 = Rect.fromLTWH(0, 20, 70, 10);
    final idx = PageTextIndex.fromLines([
      [(text: 'It', rect: r1), (text: 'is', rect: r2)],
      [(text: 'extra-', rect: r3), (text: 'ordinary.', rect: r3)],
    ]);
    expect(idx.words.map((w) => w.text), ['It', 'is', 'extra-', 'ordinary.']);
    expect(idx.words[1].rect, r2);
    expect(idx.wordAt(const Offset(60, 5))?.text, 'is');
    // Two words on one line aren't a line break, so no hyphen join here…
    expect(normalizeSentence(idx.rawSentence(idx.sentences.first)), 'It is extra- ordinary.');
    // …but across lines the joiner works.
    final idx2 = PageTextIndex.fromLines([
      [(text: 'extra-', rect: r1)],
      [(text: 'ordinary', rect: r3)],
    ]);
    expect(normalizeSentence(idx2.rawSentence(idx2.sentences.first)), 'extraordinary');
  });
}
