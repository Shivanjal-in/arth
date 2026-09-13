// Text normalization — implements contracts/normalize.md.
//
// Any change here must keep contracts/normalize-vectors.json passing
// (test/normalize_test.dart), and the TypeScript and Python implementations
// must change in lockstep. Cache keys on the server derive from this output.
//
// Character sets are built from code points so the file reads like the spec
// tables and has no escape-sequence ambiguity.

import 'dart:convert';

import 'package:crypto/crypto.dart';

String _cp(int codePoint) => String.fromCharCode(codePoint);

String _charClass(Iterable<int> codePoints) =>
    '[${codePoints.map((c) => RegExp.escape(_cp(c))).join()}]';

// S1
final RegExp _invisible = RegExp(_charClass([0x00AD, 0x200B, 0xFEFF]));

// S2
final Map<String, String> _ligatures = {
  _cp(0xFB00): 'ff',
  _cp(0xFB01): 'fi',
  _cp(0xFB02): 'fl',
  _cp(0xFB03): 'ffi',
  _cp(0xFB04): 'ffl',
  _cp(0xFB05): 'st',
  _cp(0xFB06): 'st',
};
final RegExp _ligatureRe = RegExp(
  _charClass([0xFB00, 0xFB01, 0xFB02, 0xFB03, 0xFB04, 0xFB05, 0xFB06]),
);

// S3
final RegExp _singleQuotes = RegExp(
  _charClass([0x2018, 0x2019, 0x201A, 0x201B, 0x02BC, 0x2032]),
);
final RegExp _doubleQuotes = RegExp(
  _charClass([0x201C, 0x201D, 0x201E, 0x201F, 0x2033]),
);

// S4
final RegExp _hyphens = RegExp(
  _charClass([0x2010, 0x2011, 0x2212, 0xFE63, 0xFF0D]),
);
final RegExp _dashes = RegExp(
  _charClass([0x2013, 0x2014, 0x2015, 0x2E3A, 0x2E3B]),
);
final String _emDash = _cp(0x2014);

// S5 — letter, hyphen, optional spaces/tabs, one line/page break, optional
// spaces/tabs, letter.
final String _lf = _cp(10);
final String _cr = _cp(13);
final String _ff = _cp(12);
final String _tab = _cp(9);
final RegExp _hyphenBreak = RegExp(
  r'(\p{L})-[ '
  '$_tab]*(?:$_cr$_lf|$_lf|$_cr|$_ff)[ $_tab]*'
  r'(\p{L})',
  unicode: true,
);

// S6 — the exact whitespace set from the spec, not \s.
final RegExp _whitespaceRun = RegExp(
  '${_charClass([
    ...List.generate(5, (i) => 0x09 + i),
    0x20,
    0x85,
    0xA0,
    0x1680,
    ...List.generate(11, (i) => 0x2000 + i),
    0x2028,
    0x2029,
    0x202F,
    0x205F,
    0x3000,
  ])}+',
);

// W1
final RegExp _leadingNonAlnum = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);
final RegExp _trailingNonAlnum = RegExp(r'[^\p{L}\p{N}]+$', unicode: true);

/// Sentence/selection text. Case preserved.
String normalizeSentence(String text) {
  var s = text.replaceAll(_invisible, '');
  s = s.replaceAllMapped(_ligatureRe, (m) => _ligatures[m[0]!] ?? m[0]!);
  s = s.replaceAll(_singleQuotes, "'").replaceAll(_doubleQuotes, '"');
  s = s.replaceAll(_hyphens, '-').replaceAll(_dashes, _emDash);
  // S5 can chain across consecutive breaks; each match consumes its trailing
  // letter, so loop until stable.
  String prev;
  do {
    prev = s;
    s = s.replaceAllMapped(_hyphenBreak, (m) => '${m[1]}${m[2]}');
  } while (s != prev);
  s = s.replaceAll(_whitespaceRun, ' ');
  return s.trim();
}

/// A single tapped token: sentence rules, then edge punctuation stripped,
/// then lowercased. Trailing 's is kept (lemma resolution handles it).
String normalizeWord(String token) {
  final s = normalizeSentence(token)
      .replaceFirst(_leadingNonAlnum, '')
      .replaceFirst(_trailingNonAlnum, '');
  return s.toLowerCase();
}

String _sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// Cache key for a /context call. Matches the server's key exactly.
String contextKey(String word, String sentence) =>
    _sha256Hex('context:${normalizeWord(word)}|${normalizeSentence(sentence)}');

/// Cache key for a /translate call. Matches the server's key exactly.
String sentenceKey(String text) =>
    _sha256Hex('sentence:${normalizeSentence(text)}');
