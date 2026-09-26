// ignore_for_file: leading_newlines_in_multiline_strings — schema fixtures read as one statement per string.

import 'dart:convert';
import 'dart:typed_data';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/account/sign_in_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The API's sync rules (api/src/services/accounts.ts), in memory: one
/// user's rows, last write wins, a sequence number per accepted write.
class FakeSyncServer implements HttpClientAdapter {
  final rows = <String, ({String kind, Map<String, Object?> row, int seq})>{};
  int seq = 0;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    assert(options.path == '/sync', options.path);
    final body = options.data as Map<String, dynamic>;
    final pushed = <String>{};
    for (final kind in ['cards', 'bookmarks']) {
      for (final r in (body[kind] as List).cast<Map<String, Object?>>()) {
        pushed.add('${r['id']}:${r['updatedAt']}');
        final cur = rows[r['id']];
        seq++;
        if (cur == null || (cur.row['updatedAt']! as int) < (r['updatedAt']! as int)) rows[r['id']! as String] = (kind: kind, row: r, seq: seq);
      }
    }
    final after = body['cursor'] as int;
    final changed = rows.values.where((r) => r.seq > after).toList()..sort((a, b) => a.seq.compareTo(b.seq));
    final data = {
      'cursor': changed.isEmpty ? after : changed.last.seq,
      'more': false,
      'accepted': 0,
      'cards': [for (final r in changed) if (r.kind == 'cards' && !pushed.contains('${r.row['id']}:${r.row['updatedAt']}')) r.row],
      'bookmarks': [for (final r in changed) if (r.kind == 'bookmarks' && !pushed.contains('${r.row['id']}:${r.row['updatedAt']}')) r.row],
    };
    return ResponseBody.fromString(jsonEncode({'ok': true, 'data': data}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  var n = 0;
  Future<LocalStore> fresh() async {
    final path = '${await factory.getDatabasesPath()}/sync_test_${n++}.db';
    await factory.deleteDatabase(path);
    return LocalStore.openAt(path, factory: factory);
  }

  group('store sync', () {
    test('pending rows carry the book key; editing mid-flight keeps a row dirty', () async {
      final store = await fresh();
      final book = await store.addBook(title: 'Emma', path: 'a.epub', kind: BookKind.epub);
      final card = await store.addFlashcard(kind: CardKind.idea, front: 'before key', bookId: book.id, bookTitle: 'Emma');
      await store.setContentKey(book.id, 'key-emma');
      final pending = await store.pendingCards();
      expect(pending.single['bookKey'], 'key-emma', reason: 'cards made before the key get it');
      expect(pending.single['bookTitle'], 'Emma');

      // Edited after being read for upload, before the server answered.
      await store.updateFlashcard(card.copyWith(front: 'edited', updatedAt: DateTime.now().add(const Duration(seconds: 1))));
      await store.markSynced(cards: pending, bookmarks: const []);
      expect((await store.pendingCards()).single['front'], 'edited');
    });

    test('remote rows: newer wins, and they find their book by key — now or when it is imported', () async {
      final store = await fresh();
      final book = await store.addBook(title: 'Emma', path: 'a.epub', kind: BookKind.epub);
      await store.setContentKey(book.id, 'key-emma');
      Map<String, Object?> card(String id, int updatedAt, String front, String key) => {
            'id': id, 'kind': 'quote', 'front': front, 'back': '', 'note': '', 'context': null, 'bookKey': key, 'bookTitle': 'Some Book', //
            'page': 2, 'block': null, 'location': 'Chapter 2', 'box': 0, 'dueAt': null, 'createdAt': 1, 'updatedAt': updatedAt, 'deletedAt': null,
          };
      await store.applyRemote(
        cards: [card('c1', 10, 'for emma', 'key-emma'), card('c2', 10, 'for persuasion', 'key-persuasion')],
        bookmarks: [
          {'id': 'b1', 'bookKey': 'key-persuasion', 'bookTitle': 'Persuasion', 'page': 5, 'block': 3, 'label': 'Chapter 5', 'excerpt': null, 'createdAt': 1, 'updatedAt': 1, 'deletedAt': null},
        ],
      );
      expect((await store.flashcards(bookId: book.id)).single.front, 'for emma');
      expect(await store.pendingCards(), isEmpty, reason: 'rows from the server are not re-uploaded');

      await store.applyRemote(cards: [card('c1', 5, 'stale', 'key-emma')], bookmarks: const []);
      expect((await store.flashcards(bookId: book.id)).single.front, 'for emma');

      final later = await store.addBook(title: 'Persuasion', path: 'p.pdf');
      await store.setContentKey(later.id, 'key-persuasion');
      expect((await store.flashcards(bookId: later.id)).single.front, 'for persuasion');
      expect((await store.bookmarks(later.id)).single.page, 5);
    });

    test('upgrades a version-4 database: bookmarks keep their rows, book_id becomes optional', () async {
      final path = '${await factory.getDatabasesPath()}/sync_test_v4.db';
      await factory.deleteDatabase(path);
      final v4 = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE books (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, path TEXT NOT NULL UNIQUE,
              kind TEXT NOT NULL DEFAULT 'pdf', added_at INTEGER NOT NULL, page_count INTEGER, last_page INTEGER NOT NULL DEFAULT 1,
              last_opened_at INTEGER, progress REAL, finished_at INTEGER)''');
            await db.execute('''CREATE TABLE flashcards (id TEXT PRIMARY KEY, kind TEXT NOT NULL, front TEXT NOT NULL, back TEXT NOT NULL DEFAULT '',
              note TEXT NOT NULL DEFAULT '', context TEXT, book_id INTEGER, book_title TEXT, page INTEGER, block INTEGER, location TEXT,
              box INTEGER NOT NULL DEFAULT 0, due_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER,
              dirty INTEGER NOT NULL DEFAULT 1)''');
            await db.execute('CREATE INDEX flashcards_book ON flashcards(book_id, page, block)');
            await db.execute('''CREATE TABLE bookmarks (id TEXT PRIMARY KEY, book_id INTEGER NOT NULL, page INTEGER NOT NULL, block INTEGER,
              label TEXT, excerpt TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER, dirty INTEGER NOT NULL DEFAULT 1)''');
            await db.execute('CREATE INDEX bookmarks_book ON bookmarks(book_id, page)');
            await db.execute('''CREATE TABLE highlights (id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER NOT NULL, page INTEGER NOT NULL,
              block INTEGER, start_word INTEGER NOT NULL, end_word INTEGER NOT NULL, text TEXT NOT NULL, color TEXT NOT NULL, created_at INTEGER NOT NULL)''');
            await db.insert('books', {'title': 'Old', 'path': 'old.pdf', 'added_at': 1});
            await db.insert('bookmarks', {'id': 'bm', 'book_id': 1, 'page': 7, 'label': 'Page 7', 'created_at': 1, 'updated_at': 1});
          },
        ),
      );
      await v4.close();
      final store = await LocalStore.openAt(path, factory: factory);
      expect((await store.bookmarks(1)).single.label, 'Page 7');
      await store.setContentKey(1, 'k');
      await store.removeBook(1);
      expect((await store.pendingBookmarks()).single['bookKey'], 'k', reason: 'survives its book, keyed');
      await factory.deleteDatabase(path);
    });
  });

  group('two devices', () {
    Future<ProviderContainer> device(FakeSyncServer server) async {
      final store = await fresh();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          signedInUidProvider.overrideWithValue('reader-1'),
          apiClientProvider.overrideWithValue(ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://fake/v1'))..httpClientAdapter = server)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a card made on one phone appears on the other, and edits and deletes follow', () async {
      final server = FakeSyncServer();
      final a = await device(server);
      final b = await device(server);
      final storeA = a.read(localStoreProvider);
      final storeB = b.read(localStoreProvider);

      final card = await storeA.addFlashcard(kind: CardKind.idea, front: 'Who is Mr Knightley?', bookTitle: 'Emma');
      await a.read(syncProvider.notifier).run();
      await b.read(syncProvider.notifier).run();
      expect((await storeB.flashcards()).single.front, 'Who is Mr Knightley?');

      final onB = (await storeB.flashcards()).single;
      await storeB.updateFlashcard(onB.copyWith(back: 'Emma’s neighbour', updatedAt: DateTime.now().add(const Duration(seconds: 1))));
      await b.read(syncProvider.notifier).run();
      await a.read(syncProvider.notifier).run();
      expect((await storeA.flashcards()).single.back, 'Emma’s neighbour');

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storeA.deleteFlashcard(card.id);
      await a.read(syncProvider.notifier).run();
      await b.read(syncProvider.notifier).run();
      expect(await storeB.flashcards(), isEmpty);
      expect(b.read(syncProvider).phase, SyncPhase.idle);
      expect(b.read(syncProvider).lastSyncedAt, isNotNull);
    });

    test('an idle sync sends nothing new and changes nothing', () async {
      final server = FakeSyncServer();
      final a = await device(server);
      await a.read(localStoreProvider).addFlashcard(kind: CardKind.word, front: 'amiable');
      await a.read(syncProvider.notifier).run();
      final rows = server.rows.length;
      await a.read(syncProvider.notifier).run();
      expect(server.rows.length, rows);
      expect(await a.read(localStoreProvider).pendingCards(), isEmpty);
    });
  });

  test('phone numbers default to India', () {
    expect(toE164('98765 43210'), '+919876543210');
    expect(toE164('098765-43210'), '+919876543210');
    expect(toE164('+1 415 555 0100'), '+14155550100');
  });
}
