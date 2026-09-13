import 'package:arth/core/models/contracts.dart';
import 'package:arth/data/lemma.dart';
import 'package:flutter_test/flutter_test.dart';

DictionaryEntry _entry(String w) => DictionaryEntry(
      word: w,
      ipa: '',
      hindiPronunciation: '',
      senses: const [],
      synonyms: const [],
      antonyms: const [],
      forms: const [],
      isPhrase: false,
    );

class MemSource implements LemmaSource {
  MemSource(this.words, this.forms);

  final Set<String> words;
  final Map<String, String> forms;

  @override
  Future<DictionaryEntry?> entry(String word) async =>
      words.contains(word) ? _entry(word) : null;

  @override
  Future<String?> formLemma(String form) async => forms[form];
}

void main() {
  group('resolveLemma', () {
    test('exact', () async {
      final r = await resolveLemma(MemSource({'fortune'}, {}), 'fortune');
      expect(r?.lemma, 'fortune');
      expect(r?.via, 'exact');
    });
    test('form', () async {
      final r = await resolveLemma(
        MemSource({'acknowledge'}, {'acknowledged': 'acknowledge'}),
        'acknowledged',
      );
      expect(r?.lemma, 'acknowledge');
      expect(r?.via, 'exact-form');
    });
    test('lowercase then form', () async {
      final r = await resolveLemma(
        MemSource({'wife'}, {'wives': 'wife'}),
        'Wives',
      );
      expect(r?.lemma, 'wife');
      expect(r?.via, 'lowercase-form');
    });
    test("strip 's", () async {
      final r = await resolveLemma(MemSource({'darcy'}, {}), "Darcy's");
      expect(r?.lemma, 'darcy');
      expect(r?.via, 'possessive');
    });
    test('miss', () async {
      expect(await resolveLemma(MemSource({}, {}), 'zzz'), isNull);
      expect(await resolveLemma(MemSource({}, {}), "'s"), isNull);
    });
  });

  group('suggest', () {
    test('levenshtein basics', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
      expect(levenshtein('same', 'same'), 0);
    });
    test('closest first, capped', () {
      final s = suggest(
        'fortun',
        ['fortune', 'fortunes', 'forturn', 'fort', 'zebra', 'fortunate'],
        limit: 3,
      );
      expect(s, ['fortune', 'forturn', 'fort']); // ties alphabetical
    });
  });
}
