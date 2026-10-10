// First-launch download of the on-device dictionary, with progress.
//
// A first download fetches /v1/seed/file: the whole dictionary as one
// gzipped file, saved to disk and then read into the store. A dropped
// connection resumes the file where it stopped (Range), even after the app
// was closed. Servers without the file, and the daily delta, use /v1/seed:
// NDJSON inserted in batches while it arrives; a dropped stream resumes after
// the last entry stored (`afterRank`). `seed_as_of` is only written on a
// clean finish.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arth/data/api_client.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

enum SeedPhase { idle, downloading, done, failed }

/// What [SeedProgress.done] and [SeedProgress.total] count.
enum SeedStage {
  /// Bytes of the seed file.
  download,

  /// Words read from the downloaded file into the phone.
  save,

  /// Words arriving from /v1/seed, saved as they come.
  stream,
}

/// Why a download stopped; the screens word it (Strings.seedFailed).
enum SeedFailure {
  /// No connection, or it dropped. Tried again when the network is back.
  offline,

  /// The server answered with an error, or sent something unreadable.
  server,

  /// The phone is out of space.
  storage,
  unknown,
}

class SeedProgress {
  const SeedProgress({
    required this.phase,
    this.stage = SeedStage.stream,
    this.done = 0,
    this.total = 0,
    this.retrying = false,
    this.failure,
  });

  final SeedPhase phase;
  final SeedStage stage;
  final int done;
  final int total;

  /// Between tries, after [failure].
  final bool retrying;

  /// Why the last try failed: set while [retrying] and once [phase] is failed.
  final SeedFailure? failure;

  /// The whole job: downloading the file is the first half, saving it the second.
  double? get fraction {
    if (total == 0) return null;
    final f = (done / total).clamp(0.0, 1.0);
    return switch (stage) {
      SeedStage.download => f / 2,
      SeedStage.save => 0.5 + f / 2,
      SeedStage.stream => f,
    };
  }

  SeedProgress copyWith({
    SeedPhase? phase,
    SeedStage? stage,
    int? done,
    int? total,
    bool? retrying,
  }) =>
      SeedProgress(
        phase: phase ?? this.phase,
        stage: stage ?? this.stage,
        done: done ?? this.done,
        total: total ?? this.total,
        retrying: retrying ?? this.retrying,
        failure: failure,
      );
}

/// A /v1/seed stream that stopped without its `end` line.
class SeedTruncated implements Exception {
  const SeedTruncated();

  @override
  String toString() => 'SeedTruncated';
}

/// What went wrong, as a [SeedFailure] and a short cause for analytics.
(SeedFailure, String) classifySeedError(Object e) => switch (e) {
      ApiFailure(isOffline: true) => (SeedFailure.offline, e.cause ?? 'offline'),
      ApiFailure() => (SeedFailure.server, e.cause ?? e.code),
      SeedTruncated() => (SeedFailure.offline, 'truncated'),
      HandshakeException() => (SeedFailure.offline, 'tls'),
      SocketException() => (SeedFailure.offline, 'socket'),
      // "Connection closed while receiving data": the signal went mid-stream.
      HttpException() => (SeedFailure.offline, 'connection_closed'),
      TimeoutException() => (SeedFailure.offline, 'timeout'),
      // ENOSPC is 28 on Android and iOS alike.
      FileSystemException(:final osError) when osError?.errorCode == 28 => (SeedFailure.storage, 'disk_full'),
      FileSystemException() => (SeedFailure.storage, 'file'),
      DatabaseException() when e.toString().contains('SQLITE_FULL') || e.toString().contains('disk is full') =>
        (SeedFailure.storage, 'database_full'),
      FormatException() => (SeedFailure.server, 'bad_data'),
      _ => (SeedFailure.unknown, e.runtimeType.toString()),
    };

/// Where one download has got to, kept across its tries (and across runs,
/// until it finishes) so a retry carries on instead of starting over.
class _SeedJob {
  _SeedJob({required this.delta});

  final bool delta;
  final started = DateTime.now();
  bool resolved = false;

  /// The delta's starting point; null for a full download.
  DateTime? since;

  /// The server has no seed file: stream instead.
  bool noFile = false;

  /// The main download (file or stream) is in the store.
  bool mainDone = false;
  String? asOf;
  int? maxRank;

  /// The most of the seed file on disk so far.
  int bytesHigh = 0;

  /// Streaming: the rarest entry stored so far, and how many.
  int? streamRank;
  int streamStored = 0;

  String via = 'stream';
  final causes = <String>[];
}

class SeedLoader {
  /// [fileDir]: where the seed file is kept while it downloads; without it
  /// only the stream is used. [networkBack] makes a stream that fires when
  /// the phone gets its connection back, to cut a wait between tries short.
  /// [track] hears analytics events.
  SeedLoader(
    this._api,
    this._store, {
    this.fileDir,
    this.networkBack,
    this.track,
    this.delays = defaultDelays,
  });

  static const _kAsOf = 'seed_as_of';
  static const _kFileEtag = 'seed_file_etag';
  static const _fileName = 'seed.ndjson.gz';
  static const _batchSize = 400;

  /// The waits between tries: about four minutes in all, longer than a
  /// train's tunnel, before the screen shows Try again.
  static const defaultDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 60),
    Duration(seconds: 60),
  ];

  final ApiClient _api;
  final LocalStore _store;
  final String? fileDir;
  final Stream<void> Function()? networkBack;
  final void Function(String event, Map<String, Object?> properties)? track;
  final List<Duration> delays;

  /// Tries in one run, however well they go: a backstop.
  static const maxAttempts = 30;

  /// Bumped whenever bytes or words are saved, to tell a try that got
  /// somewhere from one that didn't.
  int _moved = 0;

  /// A download that gave up; the next run of the same kind picks it up.
  _SeedJob? _unfinished;

  SeedProgress _progress = const SeedProgress(phase: SeedPhase.idle);
  void Function(SeedProgress)? _onProgress;

  void _report(SeedProgress p) {
    _progress = p;
    _onProgress?.call(p);
  }

  Future<DateTime?> lastSeededAt() async {
    final v = await _store.get(_kAsOf);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Runs a full seed (first launch) or a delta (later launches) and reports
  /// progress through [onProgress]. Never throws: failures end in
  /// [SeedPhase.failed] with a [SeedFailure].
  ///
  /// If the server's slice now reaches rarer words than the phone has (its
  /// SEED_LIMIT was raised), the missing range is fetched too.
  Future<SeedProgress> run({
    required void Function(SeedProgress) onProgress,
    bool delta = true,
  }) async {
    final job = _unfinished?.delta == delta ? _unfinished! : _SeedJob(delta: delta);
    _unfinished = null;
    _onProgress = onProgress;
    _report(const SeedProgress(phase: SeedPhase.downloading));
    // Tries in a row that saved nothing; the waits grow with it.
    var strikes = 0;
    for (var attempt = 1;; attempt++) {
      final moved = _moved;
      try {
        await _once(job);
        _report(_progress.copyWith(phase: SeedPhase.done, retrying: false));
        if (job.since == null) track?.call('Dictionary Downloaded', _summary(job, attempt));
        return _progress;
      } on Object catch (e, st) {
        final (failure, cause) = classifySeedError(e);
        job.causes.add(cause);
        debugPrint('Seed attempt $attempt failed ($cause): $e\n$st');
        final p = _progress;
        // A dropped connection that had got somewhere starts the waits over:
        // a slow, flaky line that keeps moving is never given up on.
        strikes = failure == SeedFailure.offline && _moved > moved ? 1 : strikes + 1;
        // Out of space won't fix itself between tries.
        if (failure != SeedFailure.storage && strikes <= delays.length && attempt < maxAttempts) {
          _report(SeedProgress(phase: SeedPhase.downloading, stage: p.stage, done: p.done, total: p.total, retrying: true, failure: failure));
          await _pause(delays[strikes - 1]);
          continue;
        }
        _unfinished = job;
        _report(SeedProgress(phase: SeedPhase.failed, stage: p.stage, done: p.done, total: p.total, failure: failure));
        track?.call('Dictionary Download Failed', {
          ..._summary(job, attempt),
          'reason': failure.name,
          'stage': p.stage.name,
          'done': p.done,
          'total': p.total,
        });
        return _progress;
      }
    }
  }

  Map<String, Object?> _summary(_SeedJob job, int attempts) => {
        'full': job.since == null,
        'via': job.via,
        'attempts': attempts,
        'seconds': DateTime.now().difference(job.started).inSeconds,
        'causes': job.causes.join(','),
      };

  /// Waits [d], or less if the connection comes back meanwhile.
  Future<void> _pause(Duration d) async {
    final back = networkBack?.call();
    if (back == null) return Future<void>.delayed(d);
    final wait = Completer<void>();
    final timer = Timer(d, wait.complete);
    final sub = back.listen((_) {
      if (!wait.isCompleted) wait.complete();
    }, onError: (Object _) {});
    await wait.future;
    timer.cancel();
    // Not awaited: a platform stream's cancel can wait on its next event.
    unawaited(sub.cancel());
  }

  Future<void> _once(_SeedJob job) async {
    if (!job.resolved) {
      job
        ..since = job.delta ? await lastSeededAt() : null
        ..resolved = true;
    }
    if (!job.mainDone) {
      final dir = fileDir;
      if (job.since == null && dir != null && !job.noFile) {
        job.noFile = !await _fromFile(job, '$dir/$_fileName');
      }
      if (!job.mainDone) await _fromStream(job);
      final asOf = job.asOf;
      if (asOf != null) await _store.set(_kAsOf, asOf);
    }

    // Catch up with a larger slice. Entries arrive rarest-last, so an
    // interrupted catch-up resumes from where it stopped next time.
    final have = await _store.maxEntryRank();
    final serverMax = job.maxRank;
    if (have != null && serverMax != null && serverMax > have) {
      await _consume(await _api.seedLines(afterRank: have));
    }
  }

  /// The full seed from /v1/seed/file. False when the server has none.
  Future<bool> _fromFile(_SeedJob job, String path) async {
    job.via = 'file';
    try {
      await _api.downloadSeedFile(
        path,
        etag: await _store.get(_kFileEtag),
        onStart: (etag) => unawaited(_store.set(_kFileEtag, etag)),
        onBytes: (got, total) {
          if (got > job.bytesHigh) {
            job.bytesHigh = got;
            _moved++;
          }
          _report(SeedProgress(phase: SeedPhase.downloading, stage: SeedStage.download, done: got, total: total < 0 ? 0 : total));
        },
      );
    } on ApiFailure catch (e) {
      if (!e.isNotFound) rethrow;
      job.via = 'stream';
      return false;
    }

    final file = File(path);
    _report(const SeedProgress(phase: SeedPhase.downloading, stage: SeedStage.save));
    try {
      final lines = file.openRead().transform(gzip.decoder).transform(utf8.decoder).transform(const LineSplitter());
      final meta = await _consume(lines);
      job
        ..asOf = meta.asOf
        ..maxRank = meta.maxRank
        ..mainDone = true;
    } finally {
      // Whole or not, it's done with: an unreadable file is fetched afresh,
      // and a phone that ran out of space gets that space back.
      await _store.set(_kFileEtag, null);
      if (file.existsSync()) await file.delete();
    }
    return true;
  }

  /// The seed (or the delta) from /v1/seed, carrying on after what an
  /// earlier try stored.
  Future<void> _fromStream(_SeedJob job) async {
    final after = job.streamRank;
    _report(SeedProgress(phase: SeedPhase.downloading, done: job.streamStored, total: job.streamStored));
    final lines = await _api.seedLines(since: job.since, afterRank: after, extras: after != null);
    final meta = await _consume(
      lines,
      onEntries: (rank, n) => job
        ..streamRank = rank
        ..streamStored += n,
    );
    job
      ..asOf = meta.asOf
      // A resumed stream's meta still reports the whole slice's end.
      ..maxRank = meta.maxRank
      ..mainDone = true;
  }

  /// Reads one seed (stream or file) into the store, in batches, adding its
  /// size to the progress total. [onEntries] hears the rarest entry and the
  /// count of each stored batch. Throws if the lines end early.
  Future<({String? asOf, int? maxRank})> _consume(
    Stream<String> lines, {
    void Function(int rank, int count)? onEntries,
  }) async {
    final entries = <(String, int, String)>[];
    final forms = <(String, String)>[];
    final phrases = <(String, String, String, int)>[];
    String? asOf;
    int? maxRank;
    var sawEnd = false;

    Future<void> flush() async {
      final n = entries.length + forms.length + phrases.length;
      final rank = entries.isEmpty ? null : entries.last.$2;
      final stored = entries.length;
      await _store.upsertSeed(entries: entries, forms: forms, phrases: phrases);
      if (n > 0) _moved++;
      if (rank != null) onEntries?.call(rank, stored);
      entries.clear();
      forms.clear();
      phrases.clear();
      _report(_progress.copyWith(done: _progress.done + n));
    }

    await for (final line in lines) {
      if (line.isEmpty) continue;
      final obj = jsonDecode(line) as Map<String, dynamic>;
      switch (obj['t']) {
        case 'meta':
          asOf = obj['asOf'] as String?;
          maxRank = obj['maxRank'] as int?; // absent from older servers
          final total = (obj['entries'] as int) + (obj['forms'] as int) + (obj['phrases'] as int);
          _report(_progress.copyWith(total: _progress.total + total));
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
    if (!sawEnd) throw const SeedTruncated();
    return (asOf: asOf, maxRank: maxRank);
  }
}
