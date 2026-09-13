// First-launch download of the on-device dictionary, with progress.
//
// Reads /v1/seed as NDJSON and inserts in batches while the stream is still
// arriving, so a 20k-entry seed shows movement immediately instead of a
// spinner. Resumable in the weak sense: rerunning after a failure upserts, so
// nothing is duplicated; `seed_as_of` is only written on a clean finish.

import 'dart:convert';

import 'package:arth/data/api_client.dart';
import 'package:arth/data/local_store.dart';

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

  final ApiClient _api;
  final LocalStore _store;

  Future<DateTime?> lastSeededAt() async {
    final v = await _store.get(_kAsOf);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Runs a full seed (first launch) or a delta (later launches) and reports
  /// progress through [onProgress]. Never throws: failures end in
  /// [SeedPhase.failed] with a Hindi message.
  Future<SeedProgress> run({
    required void Function(SeedProgress) onProgress,
    bool delta = true,
  }) async {
    var progress = const SeedProgress(phase: SeedPhase.downloading);
    onProgress(progress);
    final since = delta ? await lastSeededAt() : null;

    final entries = <(String, int, String)>[];
    final forms = <(String, String)>[];
    final phrases = <(String, String, String, int)>[];
    String? asOf;
    var sawEnd = false;

    Future<void> flush() async {
      await _store.upsertSeed(entries: entries, forms: forms, phrases: phrases);
      entries.clear();
      forms.clear();
      phrases.clear();
    }

    try {
      final lines = await _api.seedLines(since: since);
      await for (final line in lines) {
        if (line.isEmpty) continue;
        final obj = jsonDecode(line) as Map<String, dynamic>;
        switch (obj['t']) {
          case 'meta':
            asOf = obj['asOf'] as String?;
            final total = (obj['entries'] as int) +
                (obj['forms'] as int) +
                (obj['phrases'] as int);
            progress = progress.copyWith(total: total);
          case 'entry':
            entries.add(
              (
                obj['word'] as String,
                obj['freqRank'] as int,
                jsonEncode(obj['entry']),
              ),
            );
          case 'form':
            forms.add((obj['form'] as String, obj['lemma'] as String));
          case 'phrase':
            phrases.add(
              (
                obj['phrase'] as String,
                obj['lemma'] as String,
                obj['firstToken'] as String,
                obj['tokenCount'] as int,
              ),
            );
          case 'end':
            sawEnd = true;
        }
        if (entries.length + forms.length + phrases.length >= _batchSize) {
          final n = entries.length + forms.length + phrases.length;
          await flush();
          progress = progress.copyWith(done: progress.done + n);
          onProgress(progress);
        }
      }
      final n = entries.length + forms.length + phrases.length;
      await flush();
      progress = progress.copyWith(done: progress.done + n);
      if (!sawEnd) {
        throw const ApiFailure('INTERNAL', 'डाउनलोड बीच में रुक गया।');
      }
      if (asOf != null) await _store.set(_kAsOf, asOf);
      progress = progress.copyWith(phase: SeedPhase.done);
      onProgress(progress);
      return progress;
    } on ApiFailure catch (e) {
      progress = progress.copyWith(phase: SeedPhase.failed, message: e.message);
      onProgress(progress);
      return progress;
    } on Exception catch (_) {
      progress = progress.copyWith(
        phase: SeedPhase.failed,
        message: 'शब्दकोश डाउनलोड नहीं हो पाया।',
      );
      onProgress(progress);
      return progress;
    }
  }
}
