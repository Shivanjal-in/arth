// On-device SQLite: the top-20k dictionary slice, forms, phrases, plus the
// app's own tables (library, saved words, recent lookups, key/value settings).

import 'dart:convert';

import 'package:arth/core/models/contracts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum BookKind { pdf, scan }

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.path,
    required this.addedAt,
    this.kind = BookKind.pdf,
    this.pageCount,
    this.lastPage = 1,
    this.lastOpenedAt,
  });

  factory Book.fromRow(Map<String, Object?> r) => Book(
        id: r['id']! as int,
        title: r['title']! as String,
        path: r['path']! as String,
        kind: BookKind.values.byName((r['kind'] as String?) ?? 'pdf'),
        addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at']! as int),
        pageCount: r['page_count'] as int?,
        lastPage: (r['last_page'] as int?) ?? 1,
        lastOpenedAt: r['last_opened_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['last_opened_at']! as int),
      );

  final int id;
  final String title;

  /// Relative to the app documents directory (see documentsDirProvider).
  /// A PDF file for [BookKind.pdf]; a directory of page images for [BookKind.scan].
  final String path;
  final BookKind kind;
  final DateTime addedAt;
  final int? pageCount;
  final int lastPage;
  final DateTime? lastOpenedAt;
}

class SavedWord {
  const SavedWord({
    required this.lemma,
    required this.meaning,
    required this.savedAt,
    this.sentence,
    this.bookId,
    this.bookTitle,
  });

  factory SavedWord.fromRow(Map<String, Object?> r) => SavedWord(
        lemma: r['lemma']! as String,
        meaning: r['meaning']! as String,
        sentence: r['sentence'] as String?,
        bookId: r['book_id'] as int?,
        bookTitle: r['book_title'] as String?,
        savedAt: DateTime.fromMillisecondsSinceEpoch(r['saved_at']! as int),
      );

  final String lemma;
  final String meaning;
  final String? sentence;
  final int? bookId;
  final String? bookTitle;
  final DateTime savedAt;
}

class LocalStore {
  LocalStore._(this._db);

  static const _schemaVersion = 2;

  final Database _db;

  static Future<LocalStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      p.join(dir.path, 'arth.db'),
      version: _schemaVersion,
      onCreate: (db, _) => _create(db),
      onUpgrade: (db, from, _) async {
        if (from < 2) {
          await db.execute("ALTER TABLE books ADD COLUMN kind TEXT NOT NULL DEFAULT 'pdf'");
        }
      },
    );
    return LocalStore._(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE entries (
        word TEXT PRIMARY KEY,
        freq_rank INTEGER NOT NULL,
        json TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX entries_freq ON entries(freq_rank)');
    await db.execute('''
      CREATE TABLE forms (form TEXT PRIMARY KEY, lemma TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE phrases (
        phrase TEXT PRIMARY KEY,
        lemma TEXT NOT NULL,
        first_token TEXT NOT NULL,
        token_count INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX phrases_first ON phrases(first_token)');
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL DEFAULT 'pdf',
        added_at INTEGER NOT NULL,
        page_count INTEGER,
        last_page INTEGER NOT NULL DEFAULT 1,
        last_opened_at INTEGER
      )''');
    await db.execute('''
      CREATE TABLE saved_words (
        lemma TEXT PRIMARY KEY,
        meaning TEXT NOT NULL,
        sentence TEXT,
        book_id INTEGER,
        book_title TEXT,
        saved_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE recent_lookups (
        word TEXT PRIMARY KEY,
        looked_up_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
  }

  // ---- dictionary ----

  Future<DictionaryEntry?> entry(String word) async {
    final rows = await _db.query(
      'entries',
      columns: ['json'],
      where: 'word = ?',
      whereArgs: [word],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DictionaryEntry.fromJson(
      jsonDecode(rows.first['json']! as String) as Map<String, dynamic>,
    );
  }

  Future<int?> freqRank(String word) async {
    final rows = await _db.query(
      'entries',
      columns: ['freq_rank'],
      where: 'word = ?',
      whereArgs: [word],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['freq_rank']! as int;
  }

  /// freqRank of a key, following the forms table (wives → wife). Null when
  /// the word isn't on the device at all.
  Future<int?> rankOf(String key) async {
    final direct = await freqRank(key);
    if (direct != null) return direct;
    final lemma = await formLemma(key);
    return lemma == null ? null : freqRank(lemma);
  }

  Future<String?> formLemma(String form) async {
    final rows = await _db.query(
      'forms',
      columns: ['lemma'],
      where: 'form = ?',
      whereArgs: [form],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['lemma']! as String;
  }

  Future<String?> phraseLemma(String phrase) async {
    final rows = await _db.query(
      'phrases',
      columns: ['lemma'],
      where: 'phrase = ?',
      whereArgs: [phrase],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['lemma']! as String;
  }

  /// Prefix search over headwords for the dictionary screen.
  Future<List<String>> searchWords(String prefix, {int limit = 30}) async {
    final rows = await _db.query(
      'entries',
      columns: ['word'],
      where: r"word LIKE ? ESCAPE '\'",
      whereArgs: ['${prefix.replaceAll('%', r'\%').replaceAll('_', r'\_')}%'],
      orderBy: 'freq_rank ASC',
      limit: limit,
    );
    return rows.map((r) => r['word']! as String).toList();
  }

  /// All headwords, for Levenshtein suggestions. ~20k short strings is fine.
  Future<List<String>> allWords() async {
    final rows = await _db.query('entries', columns: ['word']);
    return rows.map((r) => r['word']! as String).toList();
  }

  Future<int> entryCount() async {
    final n = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM entries'),
    );
    return n ?? 0;
  }

  /// Batched upsert used by the seed loader.
  Future<void> upsertSeed({
    required List<(String word, int freqRank, String json)> entries,
    required List<(String form, String lemma)> forms,
    required List<(String phrase, String lemma, String first, int count)>
        phrases,
  }) async {
    if (entries.isEmpty && forms.isEmpty && phrases.isEmpty) return;
    final batch = _db.batch();
    for (final (word, rank, json) in entries) {
      batch.insert(
        'entries',
        {'word': word, 'freq_rank': rank, 'json': json},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final (form, lemma) in forms) {
      batch.insert(
        'forms',
        {'form': form, 'lemma': lemma},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final (phrase, lemma, first, count) in phrases) {
      batch.insert(
        'phrases',
        {
          'phrase': phrase,
          'lemma': lemma,
          'first_token': first,
          'token_count': count,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ---- key/value (settings, seed state) ----

  Future<String?> get(String key) async {
    final rows = await _db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> set(String key, String? value) => _db.insert(
        'kv',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---- library ----

  Future<List<Book>> books() async {
    final rows = await _db.query(
      'books',
      orderBy: 'COALESCE(last_opened_at, added_at) DESC',
    );
    return rows.map(Book.fromRow).toList();
  }

  Future<Book?> book(int id) async {
    final rows = await _db.query('books', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Book.fromRow(rows.first);
  }

  Future<Book> addBook({required String title, required String path, BookKind kind = BookKind.pdf}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db.insert(
      'books',
      {'title': title, 'path': path, 'kind': kind.name, 'added_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return (await book(id))!;
  }

  Future<void> removeBook(int id) =>
      _db.delete('books', where: 'id = ?', whereArgs: [id]);

  Future<void> touchBook(int id, {int? lastPage, int? pageCount}) => _db.update(
        'books',
        {
          'last_opened_at': DateTime.now().millisecondsSinceEpoch,
          'last_page': ?lastPage,
          'page_count': ?pageCount,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  // ---- saved words ----

  Future<List<SavedWord>> savedWords() async {
    final rows = await _db.query('saved_words', orderBy: 'saved_at DESC');
    return rows.map(SavedWord.fromRow).toList();
  }

  Future<bool> isSaved(String lemma) async {
    final rows = await _db.query(
      'saved_words',
      columns: ['lemma'],
      where: 'lemma = ?',
      whereArgs: [lemma],
    );
    return rows.isNotEmpty;
  }

  Future<void> saveWord(SavedWord w) => _db.insert(
        'saved_words',
        {
          'lemma': w.lemma,
          'meaning': w.meaning,
          'sentence': w.sentence,
          'book_id': w.bookId,
          'book_title': w.bookTitle,
          'saved_at': w.savedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> unsaveWord(String lemma) =>
      _db.delete('saved_words', where: 'lemma = ?', whereArgs: [lemma]);

  // ---- recent lookups ----

  Future<List<String>> recentLookups({int limit = 10}) async {
    final rows = await _db.query(
      'recent_lookups',
      columns: ['word'],
      orderBy: 'looked_up_at DESC',
      limit: limit,
    );
    return rows.map((r) => r['word']! as String).toList();
  }

  Future<void> addRecentLookup(String word) => _db.insert(
        'recent_lookups',
        {'word': word, 'looked_up_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
