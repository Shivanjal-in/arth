// App-wide Riverpod providers. Everything below the UI is reachable from here.

import 'dart:math';

import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/tts.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/data/ocr_service.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opened once in main() before runApp so screens never see a loading store.
final localStoreProvider = Provider<LocalStore>((_) => throw UnimplementedError());

/// The app documents directory, resolved once in main(). Book paths are stored
/// relative to it: iOS moves the sandbox on every reinstall, so absolute paths
/// silently break.
final documentsDirProvider = Provider<String>((_) => throw UnimplementedError());

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
Future<String> loadDeviceId(LocalStore store) async {
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

final apiClientProvider = Provider<ApiClient>((ref) {
  final override = ref.watch(settingsProvider.select((s) => s.apiBaseUrl));
  final url = (override == null || override.trim().isEmpty) ? kApiBaseUrl : override.trim();
  return ApiClient(baseUrl: url, deviceId: ref.watch(deviceIdProvider));
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
    ref.invalidateSelf();
    return book;
  }

  Future<void> remove(int id) async {
    await ref.read(localStoreProvider).removeBook(id);
    ref.invalidateSelf();
  }

  Future<void> touch(int id, {int? lastPage, int? pageCount}) async {
    await ref.read(localStoreProvider).touchBook(id, lastPage: lastPage, pageCount: pageCount);
    ref.invalidateSelf();
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

  Future<void> unsave(String lemma) async {
    await ref.read(localStoreProvider).unsaveWord(lemma);
    ref.invalidateSelf();
  }

  bool contains(String lemma) =>
      state.valueOrNull?.any((w) => w.lemma == lemma) ?? false;
}

final recentLookupsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(localStoreProvider).recentLookups(),
);
