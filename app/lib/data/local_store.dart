// On-device SQLite: the top-20k dictionary slice, forms, phrases, plus the
// app's own tables (library, saved words, highlights, flashcards, bookmarks,
// recent lookups, key/value settings).
//
// Flashcards and bookmarks are made to sync later: UUID ids, an updated_at on
// every write, deletes kept as tombstones (deleted_at), and a dirty flag for
// rows the server hasn't seen.

import 'dart:convert';

import 'package:arth/core/models/contracts.dart';
import 'package:arth/core/reading_stats.dart';
import 'package:arth/core/reading_tracker.dart';
import 'package:arth/core/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum BookKind { pdf, scan, epub }

/// A place in a book: a page (EPUB: chapter), 1-based, and for an EPUB the
/// block within the chapter.
typedef BookPlace = ({int page, int? block});

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
    this.progress,
    this.finishedAt,
    this.contentKey,
    this.archived = false,
    this.categoryGroup,
    this.category,
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
        progress: (r['progress'] as num?)?.toDouble(),
        finishedAt: r['finished_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['finished_at']! as int),
        contentKey: r['content_key'] as String?,
        archived: (r['archived'] as int?) == 1,
        categoryGroup: r['category_group'] as String?,
        category: r['category'] as String?,
      );

  final int id;
  final String title;

  /// Relative to the app documents directory (see documentsDirProvider).
  /// A PDF file for [BookKind.pdf]; for [BookKind.epub], an EPUB or any
  /// other reflowable document ReflowBook opens (TXT, HTML, ODT…); a
  /// directory of page images for [BookKind.scan].
  final String path;
  final BookKind kind;
  final DateTime addedAt;
  final int? pageCount;
  final int lastPage;
  final DateTime? lastOpenedAt;

  /// How far through the book the reader is, 0–1; null until a reader has
  /// reported a position. Finer than [lastPage] for chapter-paged books.
  final double? progress;

  /// When the reader first reached the end.
  final DateTime? finishedAt;

  /// Fingerprint of the file's content (see book_key.dart): how synced cards
  /// and bookmarks find this book on another device. Null for scans.
  final String? contentKey;

  /// Off the home shelf, listed on the archive screen. The file stays.
  final bool archived;

  /// `fiction` or `nonfiction`, with [category] a shelf id. Both null until
  /// the reader picks one.
  final String? categoryGroup;
  final String? category;

  /// [progress], else estimated from the page (books opened before the
  /// progress column existed).
  double? get readFraction {
    if (progress != null) return progress;
    final pages = pageCount;
    return pages == null || pages == 0 ? null : (lastPage / pages).clamp(0, 1);
  }
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

/// Highlighter colours. Stored by name; the fill per theme is in
/// `features/reader/highlights/highlight_colors.dart`.
enum HighlightColor { yellow, green, blue, pink }

/// A highlighted run of words. Anchored to word indices in the page's (PDF)
/// or block's (EPUB) PageTextIndex, which are deterministic for a given file;
/// [text] is kept for the list and as a fallback if the file changes.
class Highlight {
  const Highlight({
    required this.id,
    required this.bookId,
    required this.page,
    required this.startWord,
    required this.endWord,
    required this.text,
    required this.color,
    required this.createdAt,
    this.block,
  });

  factory Highlight.fromRow(Map<String, Object?> r) => Highlight(
        id: r['id']! as int,
        bookId: r['book_id']! as int,
        page: r['page']! as int,
        block: r['block'] as int?,
        startWord: r['start_word']! as int,
        endWord: r['end_word']! as int,
        text: r['text']! as String,
        color: HighlightColor.values.byName(r['color']! as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
      );

  final int id;
  final int bookId;

  /// PDF page number, or EPUB chapter number (both 1-based).
  final int page;

  /// EPUB block index within the chapter; null for a PDF.
  final int? block;

  /// Inclusive word range.
  final int startWord;
  final int endWord;
  final String text;
  final HighlightColor color;
  final DateTime createdAt;

  bool covers(int wordIndex) => wordIndex >= startWord && wordIndex <= endWord;

  Highlight copyWith({HighlightColor? color}) => Highlight(
        id: id,
        bookId: bookId,
        page: page,
        block: block,
        startWord: startWord,
        endWord: endWord,
        text: text,
        color: color ?? this.color,
        createdAt: createdAt,
      );
}

/// What a card holds: the reader's own note on the book (an idea, a
/// character, a plot point), a quote from it, or a word learned from it.
enum CardKind { idea, quote, word }

/// A flashcard: [front] is what you see first (a question, the quote, the
/// word), [back] the answer (the Hindi meaning, a translation, the idea),
/// [note] the reader's own words. Anchored to where in the book it was made,
/// so a deck reads in the book's order.
class Flashcard {
  const Flashcard({
    required this.id,
    required this.kind,
    required this.front,
    required this.createdAt,
    required this.updatedAt,
    this.back = '',
    this.note = '',
    this.context,
    this.bookId,
    this.bookTitle,
    this.bookKey,
    this.page,
    this.block,
    this.location,
    this.box = 0,
    this.dueAt,
  });

  factory Flashcard.fromRow(Map<String, Object?> r) => Flashcard(
        id: r['id']! as String,
        kind: CardKind.values.byName(r['kind']! as String),
        front: r['front']! as String,
        back: (r['back'] as String?) ?? '',
        note: (r['note'] as String?) ?? '',
        context: r['context'] as String?,
        bookId: r['book_id'] as int?,
        bookTitle: r['book_title'] as String?,
        bookKey: r['book_key'] as String?,
        page: r['page'] as int?,
        block: r['block'] as int?,
        location: r['location'] as String?,
        box: (r['box'] as int?) ?? 0,
        dueAt: r['due_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['due_at']! as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int),
      );

  final String id;
  final CardKind kind;
  final String front;
  final String back;
  final String note;

  /// The sentence from the book the card came from.
  final String? context;
  final int? bookId;

  /// Kept on the card so a deck outlives the book file.
  final String? bookTitle;

  /// The book's content key (book_key.dart), when known. Read-only here:
  /// the store sets it.
  final String? bookKey;

  /// PDF/scan page or EPUB chapter (1-based); [block] within the chapter.
  final int? page;
  final int? block;

  /// Human label for the place: "Chapter 3: The Ball", "Page 42".
  final String? location;

  /// Review box, 0 (new or missed) to [maxBox] (known); see review_schedule.
  final int box;
  final DateTime? dueAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const maxBox = 4;

  bool get isDue => dueAt == null || !dueAt!.isAfter(DateTime.now());

  Flashcard copyWith({
    CardKind? kind,
    String? front,
    String? back,
    String? note,
    int? box,
    DateTime? dueAt,
    DateTime? updatedAt,
  }) => Flashcard(
        id: id,
        kind: kind ?? this.kind,
        front: front ?? this.front,
        back: back ?? this.back,
        note: note ?? this.note,
        context: context,
        bookId: bookId,
        bookTitle: bookTitle,
        bookKey: bookKey,
        page: page,
        block: block,
        location: location,
        box: box ?? this.box,
        dueAt: dueAt ?? this.dueAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'kind': kind.name,
        'front': front,
        'back': back,
        'note': note,
        'context': context,
        'book_id': bookId,
        'book_title': bookTitle,
        'page': page,
        'block': block,
        'location': location,
        'box': box,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };
}

/// Per-book card counts, for the decks list and library tiles.
class DeckSummary {
  const DeckSummary({required this.bookId, required this.bookTitle, required this.count, required this.due, required this.lastAt});

  final int? bookId;
  final String bookTitle;
  final int count;
  final int due;
  final DateTime lastAt;
}

/// A place the reader marked: a page, or an EPUB chapter and the block at
/// the top of the screen (a block survives font-size changes; pixels don't).
class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.page,
    required this.createdAt,
    this.block,
    this.label,
    this.excerpt,
  });

  factory Bookmark.fromRow(Map<String, Object?> r) => Bookmark(
        id: r['id']! as String,
        bookId: r['book_id']! as int,
        page: r['page']! as int,
        block: r['block'] as int?,
        label: r['label'] as String?,
        excerpt: r['excerpt'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
      );

  final String id;
  final int bookId;

  /// PDF/scan page or EPUB chapter, 1-based.
  final int page;

  /// First visible EPUB block when the bookmark was made.
  final int? block;

  /// "Chapter 3: The Ball" / "Page 42".
  final String? label;

  /// The first words at the bookmark, so the list says what's there.
  final String? excerpt;
  final DateTime createdAt;
}

class LocalStore {
  LocalStore._(this._db);

  static const _schemaVersion = 10;

  final Database _db;

  static Future<LocalStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    return openAt(p.join(dir.path, 'arth.db'));
  }

  /// Opens (creating or upgrading) the database at [path]; tests pass an
  /// FFI [factory] and `inMemoryDatabasePath`.
  static Future<LocalStore> openAt(String path, {DatabaseFactory? factory}) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: (db, _) => _create(db),
        onUpgrade: (db, from, _) async {
          if (from < 2) {
            await db.execute("ALTER TABLE books ADD COLUMN kind TEXT NOT NULL DEFAULT 'pdf'");
          }
          if (from < 3) await _createHighlights(db);
          if (from < 4) {
            await db.execute('ALTER TABLE books ADD COLUMN progress REAL');
            await db.execute('ALTER TABLE books ADD COLUMN finished_at INTEGER');
            // Created in their current (v5) shape.
            await _createCardsAndBookmarks(db);
          }
          if (from < 5) await db.execute('ALTER TABLE books ADD COLUMN content_key TEXT');
          if (from < 6) {
            await _createVocabulary(db);
            // Words saved before vocabulary was kept count as met then.
            final saved = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'saved_words'");
            if (saved.isNotEmpty) {
              await db.execute('''
              INSERT OR IGNORE INTO vocabulary (lemma, book_id, book_title, meaning, first_at, last_at, lookups)
              SELECT lemma, book_id, book_title, meaning, saved_at, saved_at, 1 FROM saved_words WHERE book_id IS NOT NULL''');
            }
          }
          if (from == 4) {
            await db.execute('ALTER TABLE flashcards ADD COLUMN book_key TEXT');
            // A synced bookmark can arrive before its book is on this device:
            // book_id becomes nullable, which SQLite can only do by rebuilding.
            await db.execute('ALTER TABLE bookmarks RENAME TO bookmarks_v4');
            await db.execute('DROP INDEX bookmarks_book');
            await _createBookmarks(db);
            await db.execute('''
              INSERT INTO bookmarks (id, book_id, page, block, label, excerpt, created_at, updated_at, deleted_at, dirty)
              SELECT id, book_id, page, block, label, excerpt, created_at, updated_at, deleted_at, dirty FROM bookmarks_v4''');
            await db.execute('DROP TABLE bookmarks_v4');
          }
          if (from < 7) await db.execute('ALTER TABLE books ADD COLUMN archived INTEGER NOT NULL DEFAULT 0');
          if (from < 8) {
            await db.execute('ALTER TABLE books ADD COLUMN category_group TEXT');
            await db.execute('ALTER TABLE books ADD COLUMN category TEXT');
          }
          if (from < 9) {
            // A word can be saved in several books: one row per (word, book).
            final old = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'saved_words'");
            if (old.isNotEmpty) await db.execute('ALTER TABLE saved_words RENAME TO saved_words_v8');
            await _createSavedWords(db);
            if (old.isNotEmpty) {
              await db.execute('''
                INSERT INTO saved_words (lemma, meaning, sentence, book_id, book_title, saved_at)
                SELECT lemma, meaning, sentence, book_id, book_title, saved_at FROM saved_words_v8''');
              await db.execute('DROP TABLE saved_words_v8');
            }
          }
          if (from < 10) await _createReadingLog(db);
        },
      ),
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
        last_opened_at INTEGER,
        progress REAL,
        finished_at INTEGER,
        content_key TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        category_group TEXT,
        category TEXT
      )''');
    await _createSavedWords(db);
    await db.execute('''
      CREATE TABLE recent_lookups (
        word TEXT PRIMARY KEY,
        looked_up_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
    await _createHighlights(db);
    await _createReadingLog(db);
    await _createVocabulary(db);
    await _createCardsAndBookmarks(db);
  }

  static Future<void> _createCardsAndBookmarks(Database db) async {
    await db.execute('''
      CREATE TABLE flashcards (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        front TEXT NOT NULL,
        back TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        context TEXT,
        book_id INTEGER,
        book_key TEXT,
        book_title TEXT,
        page INTEGER,
        block INTEGER,
        location TEXT,
        box INTEGER NOT NULL DEFAULT 0,
        due_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        dirty INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('CREATE INDEX flashcards_book ON flashcards(book_id, page, block)');
    await _createBookmarks(db);
  }

  static Future<void> _createBookmarks(Database db) async {
    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        book_id INTEGER,
        book_key TEXT,
        book_title TEXT,
        page INTEGER NOT NULL,
        block INTEGER,
        label TEXT,
        excerpt TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        dirty INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('CREATE INDEX bookmarks_book ON bookmarks(book_id, page)');
  }

  static Future<void> _createHighlights(Database db) async {
    await db.execute('''
      CREATE TABLE highlights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        page INTEGER NOT NULL,
        block INTEGER,
        start_word INTEGER NOT NULL,
        end_word INTEGER NOT NULL,
        text TEXT NOT NULL,
        color TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX highlights_book ON highlights(book_id, page)');
  }
  /// Every word looked up while reading, once per book: when it was first
  /// and last looked up there, and how often.
  /// How long each page took to read, and the sessions they came in.
  static Future<void> _createReadingLog(Database db) async {
    await db.execute('''
      CREATE TABLE reading_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        active_ms INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE page_reads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        book_id INTEGER NOT NULL,
        page_key INTEGER NOT NULL,
        read_ms INTEGER NOT NULL,
        at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX page_reads_book ON page_reads(book_id)');
    await db.execute('CREATE INDEX page_reads_at ON page_reads(at)');
  }

  static Future<void> _createSavedWords(Database db) async {
    await db.execute('''
      CREATE TABLE saved_words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lemma TEXT NOT NULL,
        meaning TEXT NOT NULL,
        sentence TEXT,
        book_id INTEGER,
        book_title TEXT,
        saved_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX saved_words_lemma ON saved_words(lemma)');
  }

  static Future<void> _createVocabulary(Database db) async {
    await db.execute('''
      CREATE TABLE vocabulary (
        lemma TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        book_title TEXT,
        meaning TEXT NOT NULL DEFAULT '',
        first_at INTEGER NOT NULL,
        last_at INTEGER NOT NULL,
        lookups INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (lemma, book_id)
      )''');
    await db.execute('CREATE INDEX vocabulary_first ON vocabulary(lemma, first_at)');
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
  /// The rarest entry on the phone (highest freqRank), or null if none.
  Future<int?> maxEntryRank() async {
    final rows = await _db.rawQuery('SELECT MAX(freq_rank) AS r FROM entries');
    return rows.first['r'] as int?;
  }

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

  /// Removes the book and its highlights. Its flashcards and bookmarks stay,
  /// detached: a deck is worth keeping after the file is gone, and both
  /// reattach by content key if the book comes back. Detaching is local:
  /// other devices still have the book.
  Future<void> setCategory(int id, {String? group, String? category}) => _db.update(
        'books',
        {'category_group': group, 'category': category},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> setArchived(int id, {required bool archived}) => _db.update(
        'books',
        {'archived': archived ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> removeBook(int id) async {
    await _db.delete('highlights', where: 'book_id = ?', whereArgs: [id]);
    await _db.update('bookmarks', {'book_id': null}, where: 'book_id = ?', whereArgs: [id]);
    await _db.update('flashcards', {'book_id': null}, where: 'book_id = ?', whereArgs: [id]);
    await _db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  /// Records a book's content key and adopts the cards and bookmarks that
  /// were waiting for it (synced from another device, or left behind when
  /// the book was removed).
  Future<void> setContentKey(int bookId, String key) async {
    await _db.update('books', {'content_key': key}, where: 'id = ?', whereArgs: [bookId]);
    await _db.update('flashcards', {'book_id': bookId}, where: 'book_id IS NULL AND book_key = ?', whereArgs: [key]);
    await _db.update('bookmarks', {'book_id': bookId}, where: 'book_id IS NULL AND book_key = ?', whereArgs: [key]);
    // Cards made before keys existed get theirs now, for sync.
    await _db.update('flashcards', {'book_key': key}, where: 'book_id = ? AND book_key IS NULL', whereArgs: [bookId]);
    await _db.update('bookmarks', {'book_key': key}, where: 'book_id = ? AND book_key IS NULL', whereArgs: [bookId]);
  }

  /// Books (not scans) that don't have a content key yet.
  Future<List<Book>> booksWithoutKey() async {
    final rows = await _db.query('books', where: "content_key IS NULL AND kind != 'scan'");
    return rows.map(Book.fromRow).toList();
  }

  Future<void> touchBook(int id, {int? lastPage, int? pageCount, double? progress}) => _db.update(
        'books',
        {
          'last_opened_at': DateTime.now().millisecondsSinceEpoch,
          'last_page': ?lastPage,
          'page_count': ?pageCount,
          'progress': ?progress?.clamp(0.0, 1.0),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Marks the book finished if it isn't already; true when this call did.
  /// Marks a book read (now) or unread by hand. Its reading place is kept.
  Future<void> setFinished(int id, {required bool finished}) => _db.update(
        'books',
        {'finished_at': finished ? DateTime.now().millisecondsSinceEpoch : null},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<bool> markFinished(int id) async {
    final n = await _db.update(
      'books',
      {'finished_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND finished_at IS NULL',
      whereArgs: [id],
    );
    return n > 0;
  }

  // ---- flashcards ----

  /// A book's cards in reading order. Cards whose book was removed have a
  /// null book id and are found by [bookTitle]; with neither, every card.
  Future<List<Flashcard>> flashcards({int? bookId, String? bookTitle}) async {
    final rows = await _db.query(
      'flashcards',
      where: bookId != null
          ? 'deleted_at IS NULL AND book_id = ?'
          : bookTitle != null
          ? 'deleted_at IS NULL AND book_id IS NULL AND book_title = ?'
          : 'deleted_at IS NULL',
      whereArgs: [?bookId, if (bookId == null) ?bookTitle],
      orderBy: 'page IS NULL, page, block, created_at',
    );
    return rows.map(Flashcard.fromRow).toList();
  }

  Future<List<DeckSummary>> decks() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.rawQuery(
      '''
      SELECT f.book_id, COALESCE(b.title, f.book_title, '') AS title, COUNT(*) AS n,
             SUM(CASE WHEN f.due_at IS NULL OR f.due_at <= ? THEN 1 ELSE 0 END) AS due,
             MAX(f.updated_at) AS last_at
      FROM flashcards f LEFT JOIN books b ON b.id = f.book_id
      WHERE f.deleted_at IS NULL
      GROUP BY f.book_id, CASE WHEN f.book_id IS NULL THEN f.book_title END
      ORDER BY last_at DESC''',
      [now],
    );
    return [
      for (final r in rows)
        DeckSummary(
          bookId: r['book_id'] as int?,
          bookTitle: r['title']! as String,
          count: r['n']! as int,
          due: (r['due'] as int?) ?? 0,
          lastAt: DateTime.fromMillisecondsSinceEpoch(r['last_at']! as int),
        ),
    ];
  }

  Future<Flashcard> addFlashcard({
    required CardKind kind,
    required String front,
    String back = '',
    String note = '',
    String? context,
    int? bookId,
    String? bookTitle,
    int? page,
    int? block,
    String? location,
  }) async {
    final now = DateTime.now();
    final card = Flashcard(
      id: uuidV4(),
      kind: kind,
      front: front,
      back: back,
      note: note,
      context: context,
      bookId: bookId,
      bookTitle: bookTitle,
      page: page,
      block: block,
      location: location,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('flashcards', {...card.toRow(), 'book_key': await _keyOf(bookId), 'dirty': 1});
    return card;
  }

  /// Saves [card]'s fields; also undoes a delete.
  Future<void> updateFlashcard(Flashcard card) => _db.update(
        'flashcards',
        {...card.copyWith(updatedAt: DateTime.now()).toRow(), 'deleted_at': null, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [card.id],
      );

  Future<void> deleteFlashcard(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update('flashcards', {'deleted_at': now, 'updated_at': now, 'dirty': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Copies a community deck's cards into this reader's own cards, as new
  /// cards (UUIDs, dirty for sync). With [bookKey] they attach to the local
  /// copy of that book if there is one, and to it later if it's imported.
  Future<int> saveDeckCards({
    required String bookTitle,
    required String? bookKey,
    required List<({CardKind kind, String front, String back, String note, String? location})> cards,
  }) async {
    int? bookId;
    if (bookKey != null) {
      final rows = await _db.query('books', columns: ['id'], where: 'content_key = ?', whereArgs: [bookKey], limit: 1);
      if (rows.isNotEmpty) bookId = rows.first['id']! as int;
    }
    final now = DateTime.now();
    final batch = _db.batch();
    for (var i = 0; i < cards.length; i++) {
      final c = cards[i];
      // Keep the author's order: timestamps a millisecond apart.
      final at = now.add(Duration(milliseconds: i)).millisecondsSinceEpoch;
      batch.insert('flashcards', {
        'id': uuidV4(),
        'kind': c.kind.name,
        'front': c.front,
        'back': c.back,
        'note': c.note,
        'book_id': bookId,
        'book_key': bookKey,
        'book_title': bookTitle,
        'location': c.location,
        'box': 0,
        'created_at': at,
        'updated_at': at,
        'dirty': 1,
      });
    }
    await batch.commit(noResult: true);
    return cards.length;
  }

  Future<String?> _keyOf(int? bookId) async {
    if (bookId == null) return null;
    final rows = await _db.query('books', columns: ['content_key'], where: 'id = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : rows.first['content_key'] as String?;
  }

  // ---- bookmarks ----

  Future<List<Bookmark>> bookmarks(int bookId) async {
    final rows = await _db.query(
      'bookmarks',
      where: 'deleted_at IS NULL AND book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page, block',
    );
    return rows.map(Bookmark.fromRow).toList();
  }

  Future<Bookmark> addBookmark({required int bookId, required int page, int? block, String? label, String? excerpt}) async {
    final now = DateTime.now();
    final b = Bookmark(id: uuidV4(), bookId: bookId, page: page, block: block, label: label, excerpt: excerpt, createdAt: now);
    await _db.insert('bookmarks', {
      'id': b.id,
      'book_id': bookId,
      'book_key': await _keyOf(bookId),
      'page': page,
      'block': block,
      'label': label,
      'excerpt': excerpt,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
      'dirty': 1,
    });
    return b;
  }

  Future<void> deleteBookmark(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.update('bookmarks', {'deleted_at': now, 'updated_at': now, 'dirty': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // ---- saved words ----

  /// Every saved word, newest first; with [bookId], only that book's.
  Future<List<SavedWord>> savedWords({int? bookId}) async {
    final rows = await _db.query(
      'saved_words',
      where: bookId == null ? null : 'book_id = ?',
      whereArgs: bookId == null ? null : [bookId],
      orderBy: 'saved_at DESC, id DESC',
    );
    return rows.map(SavedWord.fromRow).toList();
  }

  /// Saved from [bookId] (or from the dictionary, when null).
  Future<void> saveWord(SavedWord w) async {
    await unsaveWord(w.lemma, bookId: w.bookId);
    await _db.insert('saved_words', {
      'lemma': w.lemma,
      'meaning': w.meaning,
      'sentence': w.sentence,
      'book_id': w.bookId,
      'book_title': w.bookTitle,
      'saved_at': w.savedAt.millisecondsSinceEpoch,
    });
  }

  /// Un-saves [lemma] from [bookId] (or from the dictionary, when null).
  Future<void> unsaveWord(String lemma, {int? bookId}) => _db.delete(
        'saved_words',
        where: bookId == null ? 'lemma = ? AND book_id IS NULL' : 'lemma = ? AND book_id = ?',
        whereArgs: bookId == null ? [lemma] : [lemma, bookId],
      );

  // ---- highlights ----

  Future<List<Highlight>> highlights(int bookId) async {
    final rows = await _db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page, block, start_word',
    );
    return rows.map(Highlight.fromRow).toList();
  }

  Future<Highlight> addHighlight({
    required int bookId,
    required int page,
    required int startWord,
    required int endWord,
    required String text,
    required HighlightColor color,
    int? block,
  }) async {
    final now = DateTime.now();
    final id = await _db.insert('highlights', {
      'book_id': bookId,
      'page': page,
      'block': block,
      'start_word': startWord,
      'end_word': endWord,
      'text': text,
      'color': color.name,
      'created_at': now.millisecondsSinceEpoch,
    });
    return Highlight(
      id: id,
      bookId: bookId,
      page: page,
      block: block,
      startWord: startWord,
      endWord: endWord,
      text: text,
      color: color,
      createdAt: now,
    );
  }

  /// Applies a highlight plan (see planHighlight) in one go: deletes, trims, and inserts (the
  /// first insert is the new highlight, which is returned).
  Future<Highlight> rearrangeHighlights({
    required int bookId,
    required int page,
    required int? block,
    required List<int> remove,
    required List<({int id, int start, int end, String text})> trim,
    required List<({int start, int end, String text, HighlightColor color})> insert,
  }) async {
    final now = DateTime.now();
    late int firstId;
    await _db.transaction((txn) async {
      for (final id in remove) {
        await txn.delete('highlights', where: 'id = ?', whereArgs: [id]);
      }
      for (final t in trim) {
        await txn.update('highlights', {'start_word': t.start, 'end_word': t.end, 'text': t.text}, where: 'id = ?', whereArgs: [t.id]);
      }
      for (final (i, h) in insert.indexed) {
        final id = await txn.insert('highlights', {
          'book_id': bookId,
          'page': page,
          'block': block,
          'start_word': h.start,
          'end_word': h.end,
          'text': h.text,
          'color': h.color.name,
          'created_at': now.millisecondsSinceEpoch,
        });
        if (i == 0) firstId = id;
      }
    });
    final first = insert.first;
    return Highlight(
      id: firstId,
      bookId: bookId,
      page: page,
      block: block,
      startWord: first.start,
      endWord: first.end,
      text: first.text,
      color: first.color,
      createdAt: now,
    );
  }

  Future<void> recolorHighlight(int id, HighlightColor color) =>
      _db.update('highlights', {'color': color.name}, where: 'id = ?', whereArgs: [id]);

  Future<void> removeHighlight(int id) => _db.delete('highlights', where: 'id = ?', whereArgs: [id]);

  // ---- sync ----
  //
  // The wire format is the API's (api/src/services/accounts.ts): camelCase,
  // millisecond timestamps, book identified by content key and title.

  /// Cards changed here that the server hasn't seen, in wire form.
  Future<List<Map<String, Object?>>> pendingCards({int limit = 500}) async {
    final rows = await _db.rawQuery('''
      SELECT f.*, COALESCE(f.book_key, b.content_key) AS key, COALESCE(b.title, f.book_title) AS title
      FROM flashcards f LEFT JOIN books b ON b.id = f.book_id
      WHERE f.dirty = 1 LIMIT ?''', [limit]);
    return [
      for (final r in rows)
        {
          'id': r['id'],
          'kind': r['kind'],
          'front': r['front'],
          'back': r['back'],
          'note': r['note'],
          'context': r['context'],
          'bookKey': r['key'],
          'bookTitle': r['title'],
          'page': r['page'],
          'block': r['block'],
          'location': r['location'],
          'box': r['box'],
          'dueAt': r['due_at'],
          'createdAt': r['created_at'],
          'updatedAt': r['updated_at'],
          'deletedAt': r['deleted_at'],
        },
    ];
  }

  Future<List<Map<String, Object?>>> pendingBookmarks({int limit = 500}) async {
    final rows = await _db.rawQuery('''
      SELECT m.*, COALESCE(m.book_key, b.content_key) AS key, COALESCE(b.title, m.book_title) AS title
      FROM bookmarks m LEFT JOIN books b ON b.id = m.book_id
      WHERE m.dirty = 1 LIMIT ?''', [limit]);
    return [
      for (final r in rows)
        {
          'id': r['id'],
          'bookKey': r['key'],
          'bookTitle': r['title'],
          'page': r['page'],
          'block': r['block'],
          'label': r['label'],
          'excerpt': r['excerpt'],
          'createdAt': r['created_at'],
          'updatedAt': r['updated_at'],
          'deletedAt': r['deleted_at'],
        },
    ];
  }

  /// Clears the dirty flag on rows the server accepted — unless they were
  /// edited again while the request was in flight.
  Future<void> markSynced({required List<Map<String, Object?>> cards, required List<Map<String, Object?>> bookmarks}) async {
    final batch = _db.batch();
    for (final (table, rows) in [('flashcards', cards), ('bookmarks', bookmarks)]) {
      for (final r in rows) {
        batch.update(table, {'dirty': 0}, where: 'id = ? AND updated_at = ?', whereArgs: [r['id'], r['updatedAt']]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Applies rows from the server, newer-wins against what's here. A row
  /// attaches to the local book with its content key, if there is one.
  Future<void> applyRemote({required List<Map<String, Object?>> cards, required List<Map<String, Object?>> bookmarks}) async {
    if (cards.isEmpty && bookmarks.isEmpty) return;
    await _db.transaction((tx) async {
      final bookIds = <String, int?>{};
      Future<int?> bookFor(Object? key) async {
        if (key is! String) return null;
        if (bookIds.containsKey(key)) return bookIds[key];
        final rows = await tx.query('books', columns: ['id'], where: 'content_key = ?', whereArgs: [key], limit: 1);
        return bookIds[key] = rows.isEmpty ? null : rows.first['id']! as int;
      }

      Future<bool> newer(String table, Map<String, Object?> r) async {
        final local = await tx.query(table, columns: ['updated_at'], where: 'id = ?', whereArgs: [r['id']]);
        return local.isEmpty || (local.first['updated_at']! as int) < (r['updatedAt']! as int);
      }

      for (final r in cards) {
        if (!await newer('flashcards', r)) continue;
        await tx.insert(
          'flashcards',
          {
            'id': r['id'],
            'kind': r['kind'],
            'front': r['front'],
            'back': r['back'] ?? '',
            'note': r['note'] ?? '',
            'context': r['context'],
            'book_id': await bookFor(r['bookKey']),
            'book_key': r['bookKey'],
            'book_title': r['bookTitle'],
            'page': r['page'],
            'block': r['block'],
            'location': r['location'],
            'box': r['box'] ?? 0,
            'due_at': r['dueAt'],
            'created_at': r['createdAt'],
            'updated_at': r['updatedAt'],
            'deleted_at': r['deletedAt'],
            'dirty': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final r in bookmarks) {
        if (!await newer('bookmarks', r)) continue;
        await tx.insert(
          'bookmarks',
          {
            'id': r['id'],
            'book_id': await bookFor(r['bookKey']),
            'book_key': r['bookKey'],
            'book_title': r['bookTitle'],
            'page': r['page'],
            'block': r['block'],
            'label': r['label'],
            'excerpt': r['excerpt'],
            'created_at': r['createdAt'],
            'updated_at': r['updatedAt'],
            'deleted_at': r['deletedAt'],
            'dirty': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Queues every card and bookmark for upload: the first time an account
  /// syncs from this device, what's already here joins it.
  Future<void> markAllDirty() async {
    await _db.update('flashcards', {'dirty': 1});
    await _db.update('bookmarks', {'dirty': 1});
  }

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

  Future<void> removeRecentLookup(String word) => _db.delete('recent_lookups', where: 'word = ?', whereArgs: [word]);

  // ---- reading habit ----

  Future<void> saveReadingSession(ReadingSession session) => _db.transaction((txn) async {
        final id = await txn.insert('reading_sessions', {
          'book_id': session.bookId,
          'started_at': session.startedAt.millisecondsSinceEpoch,
          'ended_at': session.endedAt.millisecondsSinceEpoch,
          'active_ms': session.activeMs,
        });
        final batch = txn.batch();
        for (final p in session.pages) {
          batch.insert('page_reads', {
            'session_id': id,
            'book_id': session.bookId,
            'page_key': p.key,
            'read_ms': p.ms,
            'at': p.at.millisecondsSinceEpoch,
          });
        }
        await batch.commit(noResult: true);
      });

  /// Everything the habit screen shows.
  Future<ReadingStats> readingStats({DateTime? now}) async {
    final days = await _db.rawQuery(
      "SELECT date(at / 1000, 'unixepoch', 'localtime') AS d, SUM(read_ms) AS ms FROM page_reads GROUP BY d",
    );
    final hours = await _db.rawQuery(
      "SELECT CAST(strftime('%H', at / 1000, 'unixepoch', 'localtime') AS INTEGER) AS h, SUM(read_ms) AS ms FROM page_reads GROUP BY h",
    );
    final books = await _db.rawQuery('''
      SELECT b.id, b.title, b.progress, b.finished_at,
        MIN(p.at) AS first_at, MAX(p.at) AS last_at, SUM(p.read_ms) AS ms,
        COUNT(DISTINCT p.page_key) AS pages, AVG(p.read_ms) AS avg_ms,
        COUNT(DISTINCT date(p.at / 1000, 'unixepoch', 'localtime')) AS days
      FROM page_reads p JOIN books b ON b.id = p.book_id
      GROUP BY b.id ORDER BY last_at DESC''');
    final dayMs = <DateTime, int>{};
    for (final r in days) {
      final d = DateTime.parse('${r['d']}');
      dayMs[DateTime(d.year, d.month, d.day)] = (r['ms']! as num).toInt();
    }
    final hourMs = List<int>.filled(24, 0);
    for (final r in hours) {
      hourMs[(r['h']! as num).toInt().clamp(0, 23)] = (r['ms']! as num).toInt();
    }
    return ReadingStats.build(
      dayMs: dayMs,
      hourMs: hourMs,
      now: now ?? DateTime.now(),
      books: [
        for (final r in books)
          BookPace(
            bookId: r['id']! as int,
            title: r['title']! as String,
            activeMs: (r['ms']! as num).toInt(),
            pagesRead: (r['pages']! as num).toInt(),
            avgPageMs: (r['avg_ms']! as num).round(),
            firstAt: DateTime.fromMillisecondsSinceEpoch((r['first_at']! as num).toInt()),
            lastAt: DateTime.fromMillisecondsSinceEpoch((r['last_at']! as num).toInt()),
            readingDays: (r['days']! as num).toInt(),
            progress: (r['progress'] as num?)?.toDouble(),
            finishedAt: r['finished_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['finished_at']! as int),
          ),
      ],
    );
  }

  // ---- vocabulary ----
  // The vocabulary is the saved words: every save lands here by itself.

  /// Every saved word, once: where and when it was first saved, the latest
  /// meaning, and how many books it was saved in. Newest first.
  Future<List<VocabWord>> lifetimeVocabulary() async {
    final rows = await _db.rawQuery('''
      SELECT s.lemma, s.book_id, s.book_title, s.saved_at AS first_at, s.saved_at AS last_at, 1 AS lookups,
        (SELECT meaning FROM saved_words m WHERE m.lemma = s.lemma AND m.meaning != '' ORDER BY m.saved_at DESC LIMIT 1) AS meaning,
        (SELECT COUNT(*) FROM saved_words b WHERE b.lemma = s.lemma AND b.book_id IS NOT NULL) AS books
      FROM saved_words s
      WHERE s.id = (SELECT f.id FROM saved_words f WHERE f.lemma = s.lemma ORDER BY f.saved_at ASC, f.id ASC LIMIT 1)
      ORDER BY s.saved_at DESC, s.id DESC''');
    return rows.map(VocabWord.fromRow).toList();
  }

  /// The words saved in [bookId]; [VocabWord.isNew] when this book is where
  /// the reader first saved the word.
  Future<List<VocabWord>> bookVocabulary(int bookId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT s.lemma, s.book_id, s.book_title, s.meaning, s.saved_at AS first_at, s.saved_at AS last_at, 1 AS lookups, 1 AS books,
        (SELECT COUNT(*) FROM saved_words e WHERE e.lemma = s.lemma AND e.id != s.id AND e.saved_at <= s.saved_at) = 0 AS is_new
      FROM saved_words s WHERE s.book_id = ?
      ORDER BY s.saved_at DESC, s.id DESC''',
      [bookId],
    );
    return rows.map(VocabWord.fromRow).toList();
  }

  /// Un-saves a word. With [bookId], only from that book; without, from
  /// every book.
  Future<void> removeVocabulary(String lemma, {int? bookId}) => _db.delete(
        'saved_words',
        where: bookId == null ? 'lemma = ?' : 'lemma = ? AND book_id = ?',
        whereArgs: bookId == null ? [lemma] : [lemma, bookId],
      );
}

/// A word from the reader's vocabulary.
class VocabWord {
  const VocabWord({
    required this.lemma,
    required this.meaning,
    required this.bookId,
    required this.bookTitle,
    required this.firstAt,
    required this.lastAt,
    required this.lookups,
    this.books = 1,
    this.isNew = true,
  });

  factory VocabWord.fromRow(Map<String, Object?> r) => VocabWord(
        lemma: r['lemma']! as String,
        meaning: (r['meaning'] as String?) ?? '',
        bookId: r['book_id'] as int?,
        bookTitle: (r['book_title'] as String?) ?? '',
        firstAt: DateTime.fromMillisecondsSinceEpoch(r['first_at']! as int),
        lastAt: DateTime.fromMillisecondsSinceEpoch(r['last_at']! as int),
        lookups: r['lookups']! as int,
        books: (r['books'] as int?) ?? 1,
        isNew: (r['is_new'] as int? ?? 1) == 1,
      );

  final String lemma;
  final String meaning;

  /// For the lifetime list: the book where it was first met.
  final int? bookId;
  final String bookTitle;
  final DateTime firstAt;
  final DateTime lastAt;
  final int lookups;

  /// How many books it was looked up in.
  final int books;

  /// First met in this book (not looked up in an earlier one).
  final bool isNew;
}
