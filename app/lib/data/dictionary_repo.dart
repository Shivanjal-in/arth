// The tap flow (Section 7), in order: phrase match (local, then API) →
// local lookup → API lookup. Context and translation are separate calls the
// UI fires in parallel with rendering.

import 'package:arth/core/models/contracts.dart';
import 'package:arth/core/text/phrase_windows.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/lemma.dart';
import 'package:arth/data/local_store.dart';

enum LookupSource { local, api }

sealed class LookupOutcome {
  const LookupOutcome();
}

class LookupFound extends LookupOutcome {
  const LookupFound({
    required this.entry,
    required this.lemma,
    required this.source,
    this.phrase,
  });

  final DictionaryEntry entry;
  final String lemma;
  final LookupSource source;

  /// Set when a multi-word phrase covered the tapped token.
  final PhraseMatch? phrase;
}

class LookupMissing extends LookupOutcome {
  const LookupMissing({
    required this.word,
    required this.suggestions,
    required this.offline,
  });

  final String word;
  final List<String> suggestions;

  /// True when the API could not be reached, so the miss may just be
  /// "not in the top 20k" rather than "not a word".
  final bool offline;
}

class _LocalSource implements LemmaSource {
  _LocalSource(this.store);

  final LocalStore store;

  @override
  Future<DictionaryEntry?> entry(String word) => store.entry(word);

  @override
  Future<String?> formLemma(String form) => store.formLemma(form);
}

class DictionaryRepo {
  DictionaryRepo({required this.store, required this.api})
      : _local = _LocalSource(store);

  final LocalStore store;
  final ApiClient api;
  final _LocalSource _local;
  List<String>? _vocabulary;

  /// Full tap flow for the token at [index] within [tokens] (normalized keys).
  Future<LookupOutcome> lookupAt(List<String> tokens, int index) async {
    final key = tokens[index];
    if (key.isEmpty) {
      return const LookupMissing(word: '', suggestions: [], offline: false);
    }

    // 1. Phrase: local windows, longest first.
    final windows = phraseWindows(tokens, index);
    for (final w in windows) {
      final lemma = await store.phraseLemma(w.phrase);
      if (lemma == null) continue;
      final entry = await store.entry(lemma) ?? await _apiEntry(lemma);
      if (entry != null) {
        return LookupFound(
          entry: entry,
          lemma: lemma,
          source: LookupSource.local,
          phrase: PhraseMatch(
            phrase: w.phrase,
            lemma: lemma,
            start: w.start,
            tokenCount: w.tokenCount,
          ),
        );
      }
    }

    // 2. Local single word.
    final local = await resolveLemma(_local, key);
    if (local != null) {
      // A phrase the local table doesn't know might still exist on the server;
      // but the spec's order puts speed first: show the word now, and let the
      // server's phrase check ride along with /context (Phase 3).
      return LookupFound(
        entry: local.entry,
        lemma: local.lemma,
        source: LookupSource.local,
      );
    }

    // 3. API: phrase first, then word.
    var offline = false;
    try {
      if (windows.isNotEmpty) {
        final m = await api.matchPhrase(tokens: tokens, index: index);
        if (m != null) {
          final entry = await _apiEntry(m.lemma);
          if (entry != null) {
            return LookupFound(
              entry: entry,
              lemma: m.lemma,
              source: LookupSource.api,
              phrase: m,
            );
          }
        }
      }
      final entry = await api.lookup(key);
      if (entry != null) {
        return LookupFound(
          entry: entry,
          lemma: entry.word,
          source: LookupSource.api,
        );
      }
    } on ApiFailure catch (e) {
      offline = e.isOffline;
    }

    return LookupMissing(
      word: key,
      suggestions: await suggestions(key),
      offline: offline,
    );
  }

  /// Direct headword lookup (dictionary screen, saved words).
  Future<LookupOutcome> lookupWord(String word) async {
    final key = word.trim().toLowerCase();
    final local = await resolveLemma(_local, key);
    if (local != null) {
      return LookupFound(
        entry: local.entry,
        lemma: local.lemma,
        source: LookupSource.local,
      );
    }
    var offline = false;
    try {
      final entry = await api.lookup(key);
      if (entry != null) {
        return LookupFound(
          entry: entry,
          lemma: entry.word,
          source: LookupSource.api,
        );
      }
    } on ApiFailure catch (e) {
      offline = e.isOffline;
    }
    return LookupMissing(
      word: key,
      suggestions: await suggestions(key),
      offline: offline,
    );
  }

  Future<DictionaryEntry?> _apiEntry(String lemma) async {
    try {
      return await api.lookup(lemma);
    } on ApiFailure {
      return null;
    }
  }

  Future<List<String>> suggestions(String word) async {
    _vocabulary ??= await store.allWords();
    return suggest(word, _vocabulary!);
  }

  /// Step 4 of the tap flow. Throws [ApiFailure]; callers keep the entry.
  Future<ContextResult> contextFor({
    required String word,
    required String sentence,
  }) =>
      api.context(word: word, sentence: sentence);

  Stream<SseEvent> translate({required String text, String? context}) =>
      api.translate(text: text, context: context);
}
