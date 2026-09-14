// Words, sentences and hit-testing over a page's extracted text.
//
// Pure Dart: takes the page's full text and one rect per character (already in
// the caller's coordinate space) so it can be unit-tested without pdfrx.

import 'dart:math' as math;
import 'dart:ui';

import 'package:arth/core/normalize.dart';

/// One whitespace-delimited token on the page, with its bounding box.
class PageWord {
  const PageWord({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
    required this.rect,
  });

  /// Position in [PageTextIndex.words].
  final int index;

  /// Character range in the page's full text.
  final int start;
  final int end;

  /// Raw token as it appears on the page (punctuation attached).
  final String text;

  /// Union of the character rects.
  final Rect rect;

  /// The dictionary key for this token.
  String get key => normalizeWord(text);
}

/// A sentence as a range of words.
class SentenceSpan {
  const SentenceSpan({required this.firstWord, required this.lastWord});

  final int firstWord;
  final int lastWord;

  bool contains(int wordIndex) =>
      wordIndex >= firstWord && wordIndex <= lastWord;
}

const _abbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'st',
  'jr',
  'sr',
  'vs',
  'etc',
  'i.e',
  'e.g',
  'no',
  'vol',
  'ch',
  'p',
  'pp',
  'prof',
  'rev',
  'hon',
  'capt',
  'col',
  'gen',
  'lt',
  'sgt',
  'mt',
  'ft',
  'inc',
  'ltd',
  'co',
};

final RegExp _terminal = RegExp(r'''[.!?…]+['"’”)\]]*$''');
final RegExp _opensSentence = RegExp(r'''^['"‘“(\[]*\p{Lu}''', unicode: true);
final RegExp _whitespace = RegExp(r'\s+');

/// Index of a page's text.
class PageTextIndex {
  PageTextIndex._(this.fullText, this.words, this.sentences);

  /// Builds the index from a page's text and per-character rects.
  ///
  /// [charRects] must have one entry per UTF-16 code unit of [fullText].
  /// Characters with an empty rect (line breaks pdfium synthesises) are fine.
  factory PageTextIndex.build(String fullText, List<Rect> charRects) {
    assert(
      charRects.length == fullText.length,
      'one rect per character expected',
    );
    final words = <PageWord>[];
    for (final m in _nonSpace.allMatches(fullText)) {
      Rect? union;
      for (var i = m.start; i < m.end; i++) {
        final r = charRects[i];
        if (r.isEmpty) continue;
        union = union == null ? r : union.expandToInclude(r);
      }
      if (union == null) continue;
      words.add(
        PageWord(
          index: words.length,
          start: m.start,
          end: m.end,
          text: m.group(0)!,
          rect: union,
        ),
      );
    }
    return PageTextIndex._(fullText, words, _segment(fullText, words));
  }

  /// Builds the index from OCR output: lines of (word, box). The full text is
  /// reconstructed with spaces inside a line and newlines between lines, so
  /// sentence segmentation and hyphen joining behave exactly as for a PDF;
  /// every character of a word shares the word's box.
  factory PageTextIndex.fromLines(List<List<({String text, Rect rect})>> lines) {
    final text = StringBuffer();
    final rects = <Rect>[];
    for (var li = 0; li < lines.length; li++) {
      if (li > 0) {
        text.write('\n');
        rects.add(Rect.zero);
      }
      var first = true;
      for (final w in lines[li]) {
        final token = w.text.trim();
        if (token.isEmpty) continue;
        if (!first) {
          text.write(' ');
          rects.add(Rect.zero);
        }
        first = false;
        text.write(token);
        for (var i = 0; i < token.length; i++) {
          rects.add(w.rect);
        }
      }
    }
    return PageTextIndex.build(text.toString(), rects);
  }

  static final RegExp _nonSpace = RegExp(r'\S+');

  final String fullText;
  final List<PageWord> words;
  final List<SentenceSpan> sentences;

  /// Does the text before the first sentence boundary continue a sentence
  /// from the previous page? True when the page does not start a new sentence.
  bool get startsMidSentence =>
      words.isNotEmpty && !_opensSentence.hasMatch(words.first.text);

  /// Does the last sentence run past the end of the page?
  bool get endsMidSentence =>
      words.isNotEmpty && !_terminal.hasMatch(words.last.text);

  /// The word under [point], with a small tolerance so taps between glyphs
  /// still land. Returns null on empty space.
  PageWord? wordAt(Offset point, {double margin = 2}) {
    PageWord? best;
    var bestDist = double.infinity;
    for (final w in words) {
      final r = w.rect.inflate(margin);
      if (!r.contains(point)) continue;
      final d = (r.center - point).distanceSquared;
      if (d < bestDist) {
        best = w;
        bestDist = d;
      }
    }
    return best;
  }

  /// The word whose character range covers [charIndex].
  PageWord? wordAtChar(int charIndex) {
    for (final w in words) {
      if (charIndex >= w.start && charIndex < w.end) return w;
    }
    return null;
  }

  SentenceSpan sentenceOf(int wordIndex) =>
      sentences.firstWhere((s) => s.contains(wordIndex));

  /// The sentence's raw text (page line breaks preserved as the page had them),
  /// ready for [normalizeSentence].
  String rawSentence(SentenceSpan span) => fullText.substring(
        words[span.firstWord].start,
        words[span.lastWord].end,
      );

  /// Normalized dictionary keys for the words [before] and [after] a word,
  /// clipped to the sentence. Used for phrase matching.
  ({List<String> tokens, int index}) tokensAround(
    int wordIndex, {
    int before = 3,
    int after = 3,
  }) {
    final s = sentenceOf(wordIndex);
    final from = math.max(s.firstWord, wordIndex - before);
    final to = math.min(s.lastWord, wordIndex + after);
    final tokens = [
      for (var i = from; i <= to; i++) words[i].key,
    ];
    return (tokens: tokens, index: wordIndex - from);
  }

  /// Bounding rect of a run of words.
  Rect rectOf(SentenceSpan span) {
    var r = words[span.firstWord].rect;
    for (var i = span.firstWord + 1; i <= span.lastWord; i++) {
      r = r.expandToInclude(words[i].rect);
    }
    return r;
  }

  static List<SentenceSpan> _segment(String fullText, List<PageWord> words) {
    final spans = <SentenceSpan>[];
    if (words.isEmpty) return spans;
    var first = 0;
    for (var i = 0; i < words.length; i++) {
      final isLast = i == words.length - 1;
      if (isLast || _isBoundary(fullText, words[i], words[i + 1])) {
        spans.add(SentenceSpan(firstWord: first, lastWord: i));
        first = i + 1;
      }
    }
    return spans;
  }

  static bool _isBoundary(String fullText, PageWord w, PageWord next) {
    // A blank line between the words is always a boundary (paragraph).
    final gap = fullText.substring(w.end, next.start);
    if (_paragraphBreak.hasMatch(gap)) return true;
    if (!_terminal.hasMatch(w.text)) return false;
    if (!_opensSentence.hasMatch(next.text)) return false;
    final bare = w.text.replaceAll(_trailingPunct, '').toLowerCase();
    if (_abbreviations.contains(bare)) return false;
    // A lone initial ("J. K. Rowling").
    if (bare.length == 1 && w.text.endsWith('.')) return false;
    return true;
  }

  static final RegExp _paragraphBreak = RegExp(r'(\r?\n[ \t]*){2,}');
  static final RegExp _trailingPunct = RegExp(r'''[.!?…'"’”)\]]+$''');
}

/// Splits arbitrary text into whitespace tokens — used for the tokens the
/// server-side phrase matcher expects.
List<String> tokenize(String text) =>
    text.trim().split(_whitespace).where((t) => t.isNotEmpty).toList();
