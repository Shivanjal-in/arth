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

  SavedWord word(String lemma, String meaning, int bookId, String title, int d) =>
      SavedWord(lemma: lemma, meaning: meaning, bookId: bookId, bookTitle: title, savedAt: day(d));

  test('a word is new in the book where it was first saved, and met before in later ones', () async {
    final store = await fresh();
    await store.saveWord(word('solitude', 'एकांत', 1, 'Emma', 1));
    await store.saveWord(word('solitude', 'अकेलापन', 2, 'Kim', 5));
    await store.saveWord(word('bazaar', 'बाज़ार', 2, 'Kim', 6));

    final emma = await store.bookVocabulary(1);
    expect(emma.single.lemma, 'solitude');
    expect(emma.single.isNew, isTrue);
    expect(emma.single.meaning, 'एकांत');

    final kim = {for (final w in await store.bookVocabulary(2)) w.lemma: w};
    expect(kim['bazaar']!.isNew, isTrue);
    expect(kim['solitude']!.isNew, isFalse);
  });

  test('saving again in the same book replaces it; other books keep theirs', () async {
    final store = await fresh();
    await store.saveWord(word('solitude', 'एकांत', 1, 'Emma', 1));
    await store.saveWord(word('solitude', 'अकेलापन', 1, 'Emma', 2));
    await store.saveWord(word('solitude', 'तनहाई', 2, 'Kim', 3));
    expect((await store.savedWords(bookId: 1)).single.meaning, 'अकेलापन');
    await store.unsaveWord('solitude', bookId: 1);
    expect(await store.savedWords(bookId: 1), isEmpty);
    expect(await store.savedWords(bookId: 2), hasLength(1));
  });

  test('vocabulary collects every saved word once: first book, books, latest meaning', () async {
    final store = await fresh();
    await store.saveWord(word('solitude', 'एकांत', 1, 'Emma', 1));
    await store.saveWord(word('solitude', 'अकेलापन', 2, 'Kim', 5));
    await store.saveWord(word('bazaar', 'बाज़ार', 2, 'Kim', 6));

    final all = await store.lifetimeVocabulary();
    expect(all.map((w) => w.lemma), ['bazaar', 'solitude']); // most recently first saved first
    final solitude = all.last;
    expect(solitude.bookTitle, 'Emma');
    expect(solitude.books, 2);
    expect(solitude.meaning, 'अकेलापन');
  });
}
