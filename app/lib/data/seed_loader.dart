// First-launch download of the on-device dictionary, with progress.
//
// Reads /v1/seed as NDJSON and inserts in batches while the stream is still
// arriving, so a 20k-entry seed shows movement immediately instead of a
// spinner. Resumable in the weak sense: rerunning after a failure upserts, so
// nothing is duplicated; `seed_as_of` is only written on a clean finish.

import 'dart:convert';

import 'package:arth/data/api_client.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter/foundation.dart';

enum SeedPhase { idle, downloading, done, failed }

class SeedProgress {
  const SeedProgress({
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.message,
  });

  final SeedPhase phase;
  final int done;
  final int total;

  /// Hindi, user-facing, only when [phase] is failed.
  final String? message;

  double? get fraction => total == 0 ? null : (done / total).clamp(0, 1);

  SeedProgress copyWith({
    SeedPhase? phase,
    int? done,
    int? total,
    String? message,
  }) =>
      SeedProgress(
        phase: phase ?? this.phase,
        done: done ?? this.done,
        total: total ?? this.total,
        message: message ?? this.message,
      );
}

class SeedLoader {
  SeedLoader(this._api, this._store);

  static const _kAsOf = 'seed_as_of';
  static const _batchSize = 400;
  static const _attempts = 3;

  final ApiClient _api;
  final LocalStore _store;

  Future<DateTime?> lastSeededAt() async {
    final v = await _store.get(_kAsOf);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Runs a full seed (first launch) or a delta (later launches) and reports
  /// progress through [onProgress]. Never throws: failures end in
  /// [SeedPhase.failed] with a Hindi message.
  ///
  /// If the server's slice now reaches rarer words than the phone has (its
  /// SEED_LIMIT was raised), the missing range is fetched too.
  Future<SeedProgress> run({
    required void Function(SeedProgress) onProgress,
    bool delta = true,
  }) async {
    var progress = const SeedProgress(phase: SeedPhase.downloading);
    onProgress(progress);
    // The stream can drop part-way (mobile data, a cold server). Rows are
    // upserted, so a fresh attempt only repeats work; try a few times before
    // giving up to the retry button.
    for (var attempt = 1;; attempt++) {
      try {
        await _once(delta: delta, onProgress: (p) => onProgress(progress = p));
        progress = progress.copyWith(phase: SeedPhase.done);
        onProgress(progress);
        return progress;
      } on Object catch (e, st) {
        debugPrint('Seed attempt $attempt failed: $e\n$st');
        if (attempt < _attempts) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          progress = const SeedProgress(phase: SeedPhase.downloading);
          onProgress(progress);
          continue;
        }
        progress = progress.copyWith(
          phase: SeedPhase.failed,
          message: e is ApiFailure ? e.message : 'शब्दकोश डाउनलोड नहीं हो पाया।',
        );
        onProgress(progress);
        return progress;
      }
    }
  }

  Future<void> _once({required bool delta, required void Function(SeedProgress) onProgress}) async {
    var progress = const SeedProgress(phase: SeedPhase.downloading);
    final since = delta ? await lastSeededAt() : null;
    final meta = await _consume(await _api.seedLines(since: since), progress, (p) => onProgress(progress = p));
    final asOf = meta.asOf;
    if (asOf != null) await _store.set(_kAsOf, asOf);

    // Catch up with a larger slice. Entries arrive rarest-last, so an
    // interrupted catch-up resumes from where it stopped next time.
    final have = await _store.maxEntryRank();
    final serverMax = meta.maxRank;
    if (have != null && serverMax != null && serverMax > have) {
      await _consume(await _api.seedLines(afterRank: have), progress, (p) => onProgress(progress = p));
    }
  }

  /// Reads one /seed stream into the store, in batches, adding its size to
  /// the progress total. Throws if the stream ends early.
  Future<({String? asOf, int? maxRank})> _consume(
    Stream<String> lines,
    SeedProgress start,
    void Function(SeedProgress) onProgress,
  ) async {
    var progress = start;
    final entries = <(String, int, String)>[];
    final forms = <(String, String)>[];
    final phrases = <(String, String, String, int)>[];
    String? asOf;
    int? maxRank;
    var sawEnd = false;

    Future<void> flush() async {
      final n = entries.length + forms.length + phrases.length;
      await _store.upsertSeed(entries: entries, forms: forms, phrases: phrases);
      entries.clear();
      forms.clear();
      phrases.clear();
      progress = progress.copyWith(done: progress.done + n);
      onProgress(progress);
    }

    await for (final line in lines) {
      if (line.isEmpty) continue;
      final obj = jsonDecode(line) as Map<String, dynamic>;
      switch (obj['t']) {
        case 'meta':
          asOf = obj['asOf'] as String?;
          maxRank = obj['maxRank'] as int?; // absent from older servers
          final total = (obj['entries'] as int) + (obj['forms'] as int) + (obj['phrases'] as int);
          progress = progress.copyWith(total: progress.total + total);
          onProgress(progress);
        case 'entry':
          entries.add((obj['word'] as String, obj['freqRank'] as int, jsonEncode(obj['entry'])));
        case 'form':
          forms.add((obj['form'] as String, obj['lemma'] as String));
        case 'phrase':
          phrases.add((obj['phrase'] as String, obj['lemma'] as String, obj['firstToken'] as String, obj['tokenCount'] as int));
        case 'end':
          sawEnd = true;
      }
      if (entries.length + forms.length + phrases.length >= _batchSize) await flush();
    }
    await flush();
    if (!sawEnd) throw const ApiFailure('INTERNAL', 'डाउनलोड बीच में रुक गया।');
    return (asOf: asOf, maxRank: maxRank);
  }
}
