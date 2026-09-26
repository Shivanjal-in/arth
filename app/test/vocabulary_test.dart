import 'package:arth/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  var n = 0;
  Future<LocalStore> fresh() async {
    final path = '${await factory.getDatabasesPath()}/vocabulary_test_${n++}.db';
    await factory.deleteDatabase(path);
    return LocalStore.openAt(path, factory: factory);
  }

  DateTime day(int d) => DateTime(2026, 9, d);

  test('a word is new in the book where it was first looked up, and met before in later ones', () async {
    final store = await fresh();
    await store.recordWord(lemma: 'solitude', bookId: 1, bookTitle: 'Emma', meaning: 'एकांत', at: day(1));
    await store.recordWord(lemma: 'solitude', bookId: 1, bookTitle: 'Emma', meaning: '', at: day(2)); // blank keeps the meaning
    await store.recordWord(lemma: 'solitude', bookId: 2, bookTitle: 'Kim', meaning: 'अकेलापन', at: day(5));
    await store.recordWord(lemma: 'bazaar', bookId: 2, bookTitle: 'Kim', meaning: 'बाज़ार', at: day(6));

    final emma = await store.bookVocabulary(1);
    expect(emma.single.lemma, 'solitude');
    expect(emma.single.isNew, isTrue);
    expect(emma.single.lookups, 2);
    expect(emma.single.meaning, 'एकांत');

    final kim = {for (final w in await store.bookVocabulary(2)) w.lemma: w};
    expect(kim['bazaar']!.isNew, isTrue);
    expect(kim['solitude']!.isNew, isFalse);
  });

  test('lifetime lists each word once: first book, total lookups, books, latest meaning', () async {
    final store = await fresh();
    await store.recordWord(lemma: 'solitude', bookId: 1, bookTitle: 'Emma', meaning: 'एकांत', at: day(1));
    await store.recordWord(lemma: 'solitude', bookId: 2, bookTitle: 'Kim', meaning: 'अकेलापन', at: day(5));
    await store.recordWord(lemma: 'bazaar', bookId: 2, bookTitle: 'Kim', meaning: 'बाज़ार', at: day(6));

    final all = await store.lifetimeVocabulary();
    expect(all.map((w) => w.lemma), ['bazaar', 'solitude']); // most recently first met first
    final solitude = all.last;
    expect(solitude.bookTitle, 'Emma');
    expect(solitude.books, 2);
    expect(solitude.lookups, 2);
    expect(solitude.meaning, 'अकेलापन');
    expect(solitude.lastAt, day(5));
  });
}
