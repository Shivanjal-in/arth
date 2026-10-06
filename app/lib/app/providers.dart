// App-wide Riverpod providers. Everything below the UI is reachable from here.

import 'dart:convert';
import 'dart:math';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/tts.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/highlight_plan.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/data/ocr_service.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opened once in main() before runApp so screens never see a loading store.
final localStoreProvider = Provider<LocalStore>((_) => throw UnimplementedError());

/// The app documents directory, resolved once in main(). Book paths are stored
/// relative to it: iOS moves the sandbox on every reinstall, so absolute paths
/// silently break.
final documentsDirProvider = Provider<String>((_) => throw UnimplementedError());

/// Asks the open reader to show its first-time gesture guide (see
/// features/reader/reader_guide.dart); the settings sheet sets it.
final readerGuideRequestProvider = StateProvider<bool>((_) => false);

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => const Settings();

  Future<void> load() async {
    state = await Settings.load(ref.read(localStoreProvider));
  }

  Future<void> update(Settings Function(Settings) change) async {
    state = change(state);
    await state.save(ref.read(localStoreProvider));
  }
}

/// Interface strings for the selected language.
final stringsProvider = Provider<AppStrings>(
  (ref) => AppStrings.of(ref.watch(settingsProvider.select((s) => s.language))),
);

/// Stable anonymous id for the API's per-device rate limits. Created in main().
final deviceIdProvider = Provider<String>((_) => throw UnimplementedError());

/// Reads (or mints) the device id from the kv table. Random v4 UUID; no
/// package needed.
/// This phone's id for the API (rate limits, and the Free plan's per-phone
/// AI allowance). From the platform's reinstall-proof id (Android's
/// ANDROID_ID, an iOS Keychain item), hashed so the raw id never leaves the
/// phone; a random id kept in the database where that isn't available.
Future<String> loadDeviceId(LocalStore store) async {
  try {
    final stable = await const MethodChannel('arth/device').invokeMethod<String>('stableId');
    if (stable != null && stable.isNotEmpty) return deviceIdFrom(stable);
  } on PlatformException catch (_) {
  } on MissingPluginException catch (_) {}
  final existing = await store.get('device_id');
  if (existing != null && existing.isNotEmpty) return existing;
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  final id = '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  await store.set('device_id', id);
  return id;
}

/// A platform id as a UUID-shaped SHA-256 digest (salted for this app).
String deviceIdFrom(String platformId) {
  final h = sha256.convert(utf8.encode('arth-device:$platformId')).toString();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    deviceId: ref.watch(deviceIdProvider),
    idToken: ref.watch(authServiceProvider)?.idToken,
    onUsage: (usage) => ref.read(usageProvider.notifier).report(usage),
  );
});

final dictionaryRepoProvider = Provider<DictionaryRepo>(
  (ref) => DictionaryRepo(
    store: ref.watch(localStoreProvider),
    api: ref.watch(apiClientProvider),
  ),
);

final ttsProvider = Provider<TtsService>((_) => TtsService());

final ocrProvider = Provider<OcrService>((ref) {
  final s = OcrService();
  ref.onDispose(s.close);
  return s;
});

/// Seed download state; the first-launch screen and Settings both watch it.
final seedProvider = NotifierProvider<SeedNotifier, SeedProgress>(SeedNotifier.new);

class SeedNotifier extends Notifier<SeedProgress> {
  @override
  SeedProgress build() => const SeedProgress(phase: SeedPhase.idle);

  Future<SeedProgress> run({bool delta = true}) async {
    final loader = SeedLoader(ref.read(apiClientProvider), ref.read(localStoreProvider));
    return loader.run(onProgress: (p) => state = p, delta: delta);
  }
}

final localEntryCountProvider = FutureProvider<int>(
  (ref) => ref.watch(localStoreProvider).entryCount(),
);

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<Book>>(LibraryNotifier.new);

class LibraryNotifier extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() => ref.watch(localStoreProvider).books();

  Future<Book> add({required String title, required String path, BookKind kind = BookKind.pdf}) async {
    final book = await ref.read(localStoreProvider).addBook(title: title, path: path, kind: kind);
    ref.read(analyticsProvider).track('Book Added', {'format': kind.name});
    ref.invalidateSelf();
    return book;
  }

  Future<void> remove(int id) async {
    await ref.read(localStoreProvider).removeBook(id);
    ref.invalidateSelf();
  }

  Future<void> setCategory(int id, {String? group, String? category}) async {
    await ref.read(localStoreProvider).setCategory(id, group: group, category: category);
    ref.invalidateSelf();
  }

  /// By hand, so no recap sheet: that belongs to reaching the end.
  Future<void> setFinished(int id, {required bool finished}) async {
    await ref.read(localStoreProvider).setFinished(id, finished: finished);
    ref.invalidateSelf();
  }

  /// Moves a book off the shelf, or back onto it. The file is kept.
  Future<void> setArchived(int id, {required bool archived}) async {
    await ref.read(localStoreProvider).setArchived(id, archived: archived);
    ref.invalidateSelf();
  }

  Future<void> touch(int id, {int? lastPage, int? pageCount, double? progress}) async {
    await ref.read(localStoreProvider).touchBook(id, lastPage: lastPage, pageCount: pageCount, progress: progress);
    ref.invalidateSelf();
  }

  /// Records how far through the book the reader is. True the first time
  /// the reader reaches the end, so the reader can offer the recap.
  Future<bool> reportProgress(int id, double progress, {int? lastPage}) async {
    final store = ref.read(localStoreProvider);
    await store.touchBook(id, progress: progress, lastPage: lastPage);
    final finished = progress >= kFinishedAt && await store.markFinished(id);
    ref.invalidateSelf();
    return finished;
  }
}

/// A book counts as read once the reader gets this far (the last pages are
/// often notes and adverts).
const kFinishedAt = 0.97;

/// Which deck: a book in the library, or a removed book's cards by title.
typedef DeckRef = ({int? bookId, String? bookTitle});

/// A deck's cards in reading order.
final FutureProviderFamily<List<Flashcard>, DeckRef> flashcardsProvider = FutureProvider.family<List<Flashcard>, DeckRef>(
  (ref, deck) => ref.watch(localStoreProvider).flashcards(bookId: deck.bookId, bookTitle: deck.bookId == null ? deck.bookTitle : null),
);

/// Every deck with its counts, most recently touched first.
final decksProvider = FutureProvider<List<DeckSummary>>((ref) => ref.watch(localStoreProvider).decks());

/// Card writes; every change refreshes the decks and card lists.
final cardsProvider = Provider<CardsService>(CardsService.new);

class CardsService {
  CardsService(this._ref);

  final Ref _ref;

  LocalStore get _store => _ref.read(localStoreProvider);

  void _changed() {
    _ref
      ..invalidate(flashcardsProvider)
      ..invalidate(decksProvider);
    _ref.read(syncProvider.notifier).schedule();
  }

  Future<Flashcard> add({
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
    final card = await _store.addFlashcard(
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
    );
    _ref.read(analyticsProvider).track('Card Created', {'kind': kind.name, 'from_book': bookId != null});
    _changed();
    return card;
  }

  Future<void> update(Flashcard card) async {
    await _store.updateFlashcard(card);
    _changed();
  }

  Future<void> delete(String id) async {
    await _store.deleteFlashcard(id);
    _changed();
  }

  /// A community deck, copied into this reader's cards.
  Future<int> saveDeck({required String bookTitle, required String? bookKey, required List<({CardKind kind, String front, String back, String note, String? location})> cards}) async {
    final n = await _store.saveDeckCards(bookTitle: bookTitle, bookKey: bookKey, cards: cards);
    _ref.read(analyticsProvider).track('Deck Saved', {'cards': n});
    _changed();
    return n;
  }
}

/// A book's bookmarks, in reading order.
final AsyncNotifierProviderFamily<BookmarksNotifier, List<Bookmark>, int> bookmarksProvider =
    AsyncNotifierProvider.family<BookmarksNotifier, List<Bookmark>, int>(BookmarksNotifier.new);

class BookmarksNotifier extends FamilyAsyncNotifier<List<Bookmark>, int> {
  @override
  Future<List<Bookmark>> build(int arg) => ref.watch(localStoreProvider).bookmarks(arg);

  Future<void> add({required int page, int? block, String? label, String? excerpt}) async {
    await ref.read(localStoreProvider).addBookmark(bookId: arg, page: page, block: block, label: label, excerpt: excerpt);
    ref.invalidateSelf();
    ref.read(syncProvider.notifier).schedule();
  }

  Future<void> remove(String id) async {
    await ref.read(localStoreProvider).deleteBookmark(id);
    ref.invalidateSelf();
    ref.read(syncProvider.notifier).schedule();
  }
}

final savedWordsProvider =
    AsyncNotifierProvider<SavedWordsNotifier, List<SavedWord>>(SavedWordsNotifier.new);

class SavedWordsNotifier extends AsyncNotifier<List<SavedWord>> {
  @override
  Future<List<SavedWord>> build() => ref.watch(localStoreProvider).savedWords();

  Future<void> save(SavedWord w) async {
    await ref.read(localStoreProvider).saveWord(w);
    ref.invalidateSelf();
  }

  /// [everywhere] drops the word from every book (the Vocabulary list).
  Future<void> unsave(String lemma, {int? bookId, bool everywhere = false}) async {
    final store = ref.read(localStoreProvider);
    if (everywhere) {
      await store.removeVocabulary(lemma);
    } else {
      await store.unsaveWord(lemma, bookId: bookId);
    }
    ref.invalidateSelf();
  }

  bool contains(String lemma, {int? bookId}) =>
      state.valueOrNull?.any((w) => w.lemma == lemma && w.bookId == bookId) ?? false;
}

/// A book's highlights, in reading order.
final AsyncNotifierProviderFamily<HighlightsNotifier, List<Highlight>, int> highlightsProvider =
    AsyncNotifierProvider.family<HighlightsNotifier, List<Highlight>, int>(HighlightsNotifier.new);

class HighlightsNotifier extends FamilyAsyncNotifier<List<Highlight>, int> {
  @override
  Future<List<Highlight>> build(int arg) => ref.watch(localStoreProvider).highlights(arg);

  /// Highlights words [startWord]..[endWord] without stacking on what's
  /// there (see planHighlight). [textOf] gives the text of any word range in
  /// the same block, for merged and trimmed highlights. [replacing] is an
  /// existing highlight being recoloured.
  Future<Highlight> add({
    required int page,
    required int startWord,
    required int endWord,
    required HighlightColor color,
    required String Function(int start, int end) textOf,
    int? block,
    int? replacing,
  }) async {
    final store = ref.read(localStoreProvider);
    final all = await store.highlights(arg);
    final here = [for (final h in all) if (h.page == page && h.block == block && h.id != replacing) h];
    final plan = planHighlight(here, startWord, endWord, color);
    final h = await store.rearrangeHighlights(
      bookId: arg,
      page: page,
      block: block,
      remove: [...plan.remove, ?replacing],
      trim: [for (final t in plan.trim) (id: t.id, start: t.range.start, end: t.range.end, text: textOf(t.range.start, t.range.end))],
      insert: [
        (start: plan.add.start, end: plan.add.end, text: textOf(plan.add.start, plan.add.end), color: color),
        for (final p in plan.split) (start: p.range.start, end: p.range.end, text: textOf(p.range.start, p.range.end), color: p.color),
      ],
    );
    ref.invalidateSelf();
    return h;
  }

  Future<void> recolor(int id, HighlightColor color) async {
    await ref.read(localStoreProvider).recolorHighlight(id, color);
    ref.invalidateSelf();
  }

  Future<void> remove(int id) async {
    await ref.read(localStoreProvider).removeHighlight(id);
    ref.invalidateSelf();
  }
}

final recentLookupsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(localStoreProvider).recentLookups(),
);
