import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/review_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  // sqflite hands back the same connection for the same path, in memory
  // too: each test gets its own file.
  var n = 0;
  Future<LocalStore> fresh() async {
    final path = '${await factory.getDatabasesPath()}/flashcards_test_${n++}.db';
    await factory.deleteDatabase(path);
    return LocalStore.openAt(path, factory: factory);
  }

  group('flashcards store', () {
    test('cards come back in reading order; delete is a tombstone that update undoes', () async {
      final store = await fresh();
      final book = await store.addBook(title: 'Emma', path: 'books/emma.epub', kind: BookKind.epub);
      final late = await store.addFlashcard(kind: CardKind.idea, front: 'Ending', bookId: book.id, bookTitle: 'Emma', page: 9);
      await store.addFlashcard(kind: CardKind.word, front: 'amiable', back: 'मिलनसार', bookId: book.id, bookTitle: 'Emma', page: 2, block: 7);
      await store.addFlashcard(kind: CardKind.quote, front: 'Handsome, clever, and rich', bookId: book.id, bookTitle: 'Emma', page: 2, block: 1);
      await store.addFlashcard(kind: CardKind.idea, front: 'Unplaced', bookId: book.id, bookTitle: 'Emma');

      expect((await store.flashcards(bookId: book.id)).map((c) => c.front), ['Handsome, clever, and rich', 'amiable', 'Ending', 'Unplaced']);

      await store.deleteFlashcard(late.id);
      expect((await store.flashcards(bookId: book.id)).length, 3);
      await store.updateFlashcard(late);
      expect((await store.flashcards(bookId: book.id)).length, 4);
    });

    test('decks: counts and due per book; removing a book keeps its deck by title', () async {
      final store = await fresh();
      final a = await store.addBook(title: 'Emma', path: 'a.epub', kind: BookKind.epub);
      final b = await store.addBook(title: 'Persuasion', path: 'b.pdf');
      await store.addFlashcard(kind: CardKind.idea, front: 'x', bookId: a.id, bookTitle: 'Emma');
      final known = await store.addFlashcard(kind: CardKind.idea, front: 'y', bookId: a.id, bookTitle: 'Emma');
      await store.updateFlashcard(reviewed(known, knewIt: true));
      await store.addFlashcard(kind: CardKind.word, front: 'z', bookId: b.id, bookTitle: 'Persuasion');
      await store.addBookmark(bookId: b.id, page: 3, label: 'Page 3');

      final decks = {for (final d in await store.decks()) d.bookTitle: d};
      expect(decks['Emma']!.count, 2);
      expect(decks['Emma']!.due, 1);
      expect(decks['Persuasion']!.count, 1);

      await store.removeBook(b.id);
      final after = {for (final d in await store.decks()) d.bookTitle: d};
      expect(after['Persuasion']!.bookId, isNull);
      expect(after['Persuasion']!.count, 1);
      expect((await store.flashcards(bookTitle: 'Persuasion')).map((c) => c.front), ['z']);
      expect(await store.bookmarks(b.id), isEmpty);
    });

    test('progress and finishing', () async {
      final store = await fresh();
      final book = await store.addBook(title: 'Emma', path: 'a.pdf');
      await store.touchBook(book.id, pageCount: 200, lastPage: 50);
      expect((await store.book(book.id))!.readFraction, 0.25);
      await store.touchBook(book.id, progress: 0.4);
      expect((await store.book(book.id))!.readFraction, 0.4);
      expect(await store.markFinished(book.id), isTrue);
      expect(await store.markFinished(book.id), isFalse, reason: 'only the first time');
      expect((await store.book(book.id))!.finishedAt, isNotNull);
    });

    test('upgrades a version-3 database', () async {
      // A v3 database, as shipped: books without progress, no cards or
      // bookmarks. A file, not memory, so the upgrade reopens the same one.
      final path = '${await factory.getDatabasesPath()}/upgrade_test.db';
      await factory.deleteDatabase(path);
      final old = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE books (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, path TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL DEFAULT 'pdf', added_at INTEGER NOT NULL, page_count INTEGER,
                last_page INTEGER NOT NULL DEFAULT 1, last_opened_at INTEGER)''');
            await db.insert('books', {'title': 'Old', 'path': 'old.pdf', 'added_at': 1, 'page_count': 10, 'last_page': 5});
          },
        ),
      );
      await old.close();

      final store = await LocalStore.openAt(path, factory: factory);
      final book = (await store.books()).single;
      expect(book.progress, isNull);
      expect(book.readFraction, 0.5);
      await store.addFlashcard(kind: CardKind.idea, front: 'works', bookId: book.id, bookTitle: book.title);
      expect((await store.flashcards(bookId: book.id)).single.front, 'works');
      await factory.deleteDatabase(path);
    });
  });

  group('review schedule', () {
    final now = DateTime(2026, 9, 24, 10);
    Flashcard card(String id, {int box = 0, DateTime? due}) =>
        Flashcard(id: id, kind: CardKind.idea, front: id, createdAt: now, updatedAt: now, box: box, dueAt: due);

    test('knowing a card moves it up a box and out; missing it sends it back to today', () {
      final up = reviewed(card('a', box: 1), knewIt: true, now: now);
      expect(up.box, 2);
      expect(up.dueAt, now.add(const Duration(days: 3)));
      final top = reviewed(card('b', box: Flashcard.maxBox), knewIt: true, now: now);
      expect(top.box, Flashcard.maxBox);
      final missed = reviewed(card('c', box: 3), knewIt: false, now: now);
      expect(missed.box, 0);
      expect(missed.dueAt, now);
    });

    test('practice: due cards first, shakiest first, then the rest in order', () {
      final cards = [
        card('later', box: 2, due: now.add(const Duration(days: 2))),
        card('due-box2', box: 2, due: now.subtract(const Duration(hours: 1))),
        card('new'),
        card('due-box1', box: 1, due: now),
      ];
      expect(practiceOrder(cards, now: now).map((c) => c.id), ['new', 'due-box1', 'due-box2', 'later']);
    });
  });
}
