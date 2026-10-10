import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arth/data/api_client.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// /v1/seed and /v1/seed/file over an in-memory dictionary whose slice ends
/// at [maxRank], with connections that drop when a test says so.
class FakeSeedApi extends ApiClient {
  FakeSeedApi(this.ranks, {this.forms = 0});

  final List<int> ranks;
  final int forms;
  int maxRank = 0;
  final calls = <String>[];

  /// Per /seed call: how many lines get through before the connection drops
  /// (null: all of them).
  final streamDrops = <int?>[];

  /// The seed file; null makes /seed/file a 404 (an older server).
  List<int>? file;
  String etag = '"v1"';

  /// Per /seed/file call: bytes sent before the connection drops.
  final fileDrops = <int?>[];

  List<String> _lines({DateTime? since, int? afterRank, bool extras = false}) {
    final slice = [
      for (final r in ranks)
        if (r <= maxRank && (afterRank == null || r > afterRank) && since == null) r,
    ];
    final withExtras = afterRank == null || extras;
    final entry = {'word': 'w', 'phonetic': '', 'senses': <Object>[]};
    return [
      jsonEncode({'t': 'meta', 'asOf': '2026-09-26T00:00:00Z', 'entries': slice.length, 'forms': withExtras ? forms : 0, 'phrases': 0, 'maxRank': maxRank}),
      for (final r in slice) jsonEncode({'t': 'entry', 'word': 'word$r', 'freqRank': r, 'entry': entry}),
      if (withExtras)
        for (var f = 0; f < forms; f++) jsonEncode({'t': 'form', 'form': 'form$f', 'lemma': 'word1'}),
      jsonEncode({'t': 'end'}),
    ];
  }

  /// The file the server would build from the current dictionary.
  void buildFile() => file = gzip.encode(utf8.encode('${_lines().join('\n')}\n'));

  @override
  Future<Stream<String>> seedLines({DateTime? since, int? afterRank, bool extras = false}) async {
    calls.add(afterRank != null ? 'after $afterRank${extras ? '+extras' : ''}' : since != null ? 'delta' : 'full');
    final lines = _lines(since: since, afterRank: afterRank, extras: extras);
    final drop = streamDrops.isEmpty ? null : streamDrops.removeAt(0);
    return () async* {
      for (var i = 0; i < lines.length; i++) {
        if (drop != null && i == drop) throw const HttpException('Connection closed while receiving data');
        yield lines[i];
      }
    }();
  }

  @override
  Future<void> downloadSeedFile(String path, {String? etag, void Function(String? etag)? onStart, void Function(int received, int total)? onBytes}) async {
    final bytes = file;
    if (bytes == null) {
      calls.add('file 404');
      throw const ApiFailure('NOT_FOUND', 'नहीं मिला।');
    }
    final f = File(path);
    final have = etag == this.etag && f.existsSync() ? f.lengthSync() : 0;
    calls.add('file from $have');
    onStart?.call(this.etag);
    final drop = fileDrops.isEmpty ? null : fileDrops.removeAt(0);
    final end = drop == null ? bytes.length : (have + drop).clamp(0, bytes.length);
    f.writeAsBytesSync(bytes.sublist(have, end), mode: have > 0 ? FileMode.append : FileMode.write);
    onBytes?.call(end, bytes.length);
    if (end < bytes.length) throw const HttpException('Connection closed while receiving data');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  var n = 0;
  Future<LocalStore> fresh() async {
    final path = '${await factory.getDatabasesPath()}/seed_loader_test_${n++}.db';
    await factory.deleteDatabase(path);
    return LocalStore.openAt(path, factory: factory);
  }

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('seed_loader_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  const noWait = [Duration.zero, Duration.zero, Duration.zero];

  test('a phone seeded with the old slice fetches only the new range when the slice grows', () async {
    final store = await fresh();
    final api = FakeSeedApi([for (var r = 1; r <= 300; r++) r])..maxRank = 100;
    final loader = SeedLoader(api, store);

    await loader.run(onProgress: (_) {}, delta: false);
    expect(await store.entryCount(), 100);

    // Nothing new: the daily delta alone.
    await loader.run(onProgress: (_) {});
    expect(api.calls, ['full', 'delta']);

    // SEED_LIMIT raised on the server.
    api.maxRank = 250;
    final done = await loader.run(onProgress: (_) {});
    expect(done.phase, SeedPhase.done);
    expect(api.calls.sublist(2), ['delta', 'after 100']);
    expect(await store.entryCount(), 250);
    expect(await store.maxEntryRank(), 250);
  });

  test('an older server (no maxRank) never triggers a catch-up', () async {
    final store = await fresh();
    final api = _OldServer();
    await SeedLoader(api, store).run(onProgress: (_) {});
    expect(api.calls, 1);
  });

  group('the seed file', () {
    test('is downloaded, read in, and cleared away', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 1000; r++) r], forms: 50)
        ..maxRank = 1000
        ..buildFile();
      final stages = <SeedStage>{};
      final r = await SeedLoader(api, store, fileDir: dir.path).run(onProgress: (p) => stages.add(p.stage), delta: false);
      expect(r.phase, SeedPhase.done);
      expect(api.calls, ['file from 0']);
      expect(stages, containsAll([SeedStage.download, SeedStage.save]));
      expect(await store.entryCount(), 1000);
      expect(await store.formLemma('form49'), 'word1');
      expect(dir.listSync(), isEmpty);
      expect(await store.get('seed_file_etag'), isNull);
      expect(await SeedLoader(api, store).lastSeededAt(), isNotNull);
    });

    test('a dropped download carries on from the bytes already saved', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 1000; r++) r])
        ..maxRank = 1000
        ..buildFile();
      final third = api.file!.length ~/ 3;
      api.fileDrops.addAll([third, third]);
      final r = await SeedLoader(api, store, fileDir: dir.path, delays: noWait).run(onProgress: (_) {}, delta: false);
      expect(r.phase, SeedPhase.done);
      expect(api.calls, ['file from 0', 'file from $third', 'file from ${2 * third}']);
      expect(await store.entryCount(), 1000);
    });

    test('a download cut short by closing the app resumes on the next launch', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 1000; r++) r])
        ..maxRank = 1000
        ..buildFile();
      final quarter = api.file!.length ~/ 4;
      // A quarter, then a retry that gets nothing: gives up, as if the app
      // had been closed.
      api.fileDrops.addAll([quarter, 0]);
      final first = await SeedLoader(api, store, fileDir: dir.path, delays: [Duration.zero]).run(onProgress: (_) {}, delta: false);
      expect(first.phase, SeedPhase.failed);
      expect(first.failure, SeedFailure.offline);

      // A new loader, as after a restart: the ETag and the bytes are on disk.
      final r = await SeedLoader(api, store, fileDir: dir.path).run(onProgress: (_) {}, delta: false);
      expect(r.phase, SeedPhase.done);
      expect(api.calls, ['file from 0', 'file from $quarter', 'file from $quarter']);
    });

    test('a server without the file: the stream instead', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 100; r++) r])..maxRank = 100;
      final r = await SeedLoader(api, store, fileDir: dir.path).run(onProgress: (_) {}, delta: false);
      expect(r.phase, SeedPhase.done);
      expect(api.calls, ['file 404', 'full']);
      expect(await store.entryCount(), 100);
    });
  });

  group('the stream', () {
    test('a dropped stream resumes after the last entry stored, and still gets the forms', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 2000; r++) r], forms: 30)..maxRank = 2000;
      // The meta line and 900 entries: two batches of 400 stored, 100 not.
      api.streamDrops.add(901);
      final r = await SeedLoader(api, store, delays: noWait).run(onProgress: (_) {}, delta: false);
      expect(r.phase, SeedPhase.done);
      expect(api.calls, ['full', 'after 800+extras']);
      expect(await store.entryCount(), 2000);
      expect(await store.formLemma('form29'), 'word1');
    });

    test('a drop among the forms fetches the forms again, and no entries', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 1000; r++) r], forms: 600)..maxRank = 1000;
      // Batches of 400 rows: the third (the last 200 entries and 200 forms)
      // is stored when the drop comes, 100 rows later.
      api.streamDrops.add(1 + 1000 + 300);
      final r = await SeedLoader(api, store, delays: noWait).run(onProgress: (_) {}, delta: false);
      expect(r.phase, SeedPhase.done);
      expect(api.calls, ['full', 'after 1000+extras']);
      expect(await store.formLemma('form599'), 'word1');
    });

    test('after giving up, the next run carries on where that one stopped', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 2000; r++) r])..maxRank = 2000;
      api.streamDrops.addAll([401, 1, 1]);
      final loader = SeedLoader(api, store, delays: [Duration.zero, Duration.zero]);
      final failed = await loader.run(onProgress: (_) {}, delta: false);
      expect(failed.phase, SeedPhase.failed);
      expect(failed.failure, SeedFailure.offline);
      expect(failed.done, 400, reason: 'the bar stays where it got to');

      final r = await loader.run(onProgress: (_) {}, delta: false);
      expect(r.phase, SeedPhase.done);
      expect(api.calls.last, 'after 400+extras');
      expect(await store.entryCount(), 2000);
    });

    test('between tries the screen hears why, and that it is trying again', () async {
      final store = await fresh();
      final api = FakeSeedApi([for (var r = 1; r <= 10; r++) r])..maxRank = 10;
      api.streamDrops.add(3);
      final seen = <SeedProgress>[];
      await SeedLoader(api, store, delays: noWait).run(onProgress: seen.add, delta: false);
      final waiting = seen.where((p) => p.retrying).toList();
      expect(waiting, hasLength(1));
      expect(waiting.single.failure, SeedFailure.offline);
      expect(seen.last.phase, SeedPhase.done);
      expect(seen.last.retrying, isFalse);
    });
  });

  test('the connection coming back cuts the wait short', () async {
    final store = await fresh();
    final api = FakeSeedApi([for (var r = 1; r <= 10; r++) r])..maxRank = 10;
    api.streamDrops.add(3);
    final back = StreamController<void>.broadcast();
    final loader = SeedLoader(api, store, delays: const [Duration(hours: 1)], networkBack: () => back.stream);
    final run = loader.run(
      onProgress: (p) {
        if (p.retrying) scheduleMicrotask(() => back.add(null));
      },
      delta: false,
    );
    final r = await run.timeout(const Duration(seconds: 5));
    expect(r.phase, SeedPhase.done);
    await back.close();
  });

  test('a flaky line that keeps getting somewhere is never given up on', () async {
    final store = await fresh();
    final api = FakeSeedApi([for (var r = 1; r <= 1000; r++) r])
      ..maxRank = 1000
      ..buildFile();
    final step = api.file!.length ~/ 6;
    // Five drops, each after a little more of the file: more than the two
    // waits allowed for tries that get nowhere.
    api.fileDrops.addAll([step, step, step, step, step]);
    final r = await SeedLoader(api, store, fileDir: dir.path, delays: noWait.sublist(0, 2)).run(onProgress: (_) {}, delta: false);
    expect(r.phase, SeedPhase.done);
    expect(api.calls, hasLength(6));
  });

  test('tries that get nowhere use up the waits and give up', () async {
    final store = await fresh();
    final api = FakeSeedApi([for (var r = 1; r <= 1000; r++) r])
      ..maxRank = 1000
      ..buildFile();
    api.fileDrops.addAll([100, 0, 0]);
    final r = await SeedLoader(api, store, fileDir: dir.path, delays: noWait.sublist(0, 2)).run(onProgress: (_) {}, delta: false);
    expect(r.phase, SeedPhase.failed);
    // The first try got 100 bytes; two waits, two tries that got nothing.
    expect(api.calls, ['file from 0', 'file from 100', 'file from 100']);
  });

  test('a connectivity stream that is slow to cancel never holds up the retry', () async {
    final store = await fresh();
    final api = FakeSeedApi([for (var r = 1; r <= 10; r++) r])..maxRank = 10;
    api.streamDrops.addAll([3, 3]);
    // Like the platform's stream: no events, and a cancel that waits for one.
    Stream<void> stuck() => StreamController<void>(onCancel: () => Completer<void>().future).stream;
    final loader = SeedLoader(api, store, delays: const [Duration(milliseconds: 10), Duration(milliseconds: 10)], networkBack: stuck);
    final r = await loader.run(onProgress: (_) {}, delta: false).timeout(const Duration(seconds: 5));
    expect(r.phase, SeedPhase.done);
  });

  test('a full phone stops at once, without retrying', () async {
    final store = await fresh();
    final api = _FullDisk();
    final events = <String, Map<String, Object?>>{};
    final r = await SeedLoader(api, store, fileDir: dir.path, track: (e, p) => events[e] = p).run(onProgress: (_) {}, delta: false);
    expect(r.phase, SeedPhase.failed);
    expect(r.failure, SeedFailure.storage);
    expect(api.tries, 1);
    expect(events['Dictionary Download Failed'], containsPair('reason', 'storage'));
    expect(events['Dictionary Download Failed'], containsPair('causes', 'disk_full'));
  });

  test('analytics hear how a full download went', () async {
    final store = await fresh();
    final api = FakeSeedApi([for (var r = 1; r <= 100; r++) r])
      ..maxRank = 100
      ..buildFile()
      ..fileDrops.add(500);
    final events = <String, Map<String, Object?>>{};
    await SeedLoader(api, store, fileDir: dir.path, delays: noWait, track: (e, p) => events[e] = p).run(onProgress: (_) {}, delta: false);
    expect(events['Dictionary Downloaded'], allOf(containsPair('via', 'file'), containsPair('attempts', 2), containsPair('causes', 'connection_closed')));
  });

  test('errors sort into what the reader is told', () {
    expect(classifySeedError(const ApiFailure('OFFLINE', '', cause: 'connectionTimeout')), (SeedFailure.offline, 'connectionTimeout'));
    expect(classifySeedError(const ApiFailure('INTERNAL', '', cause: 'http_503')), (SeedFailure.server, 'http_503'));
    expect(classifySeedError(const ApiFailure('RATE_LIMITED', '')), (SeedFailure.server, 'RATE_LIMITED'));
    expect(classifySeedError(const HttpException('Connection closed while receiving data')), (SeedFailure.offline, 'connection_closed'));
    expect(classifySeedError(const SocketException('Network is unreachable')), (SeedFailure.offline, 'socket'));
    expect(classifySeedError(const SeedTruncated()), (SeedFailure.offline, 'truncated'));
    expect(classifySeedError(const FileSystemException('write', 'x', OSError('No space left on device', 28))), (SeedFailure.storage, 'disk_full'));
    expect(classifySeedError(const FormatException('bad gzip')), (SeedFailure.server, 'bad_data'));
    expect(classifySeedError(StateError('?')).$1, SeedFailure.unknown);
  });

  group('ApiClient.downloadSeedFile', () {
    late HttpServer server;
    late List<int> body;
    var dropAfter = <int>[];
    final requests = <({String? range, String? ifRange})>[];

    setUp(() async {
      body = List<int>.generate(200000, (i) => i * 7 % 256);
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((req) async {
        final range = req.headers.value('range');
        final ifRange = req.headers.value('if-range');
        requests.add((range: range, ifRange: ifRange));
        final res = req.response..headers.set('etag', '"abc"');
        var start = 0;
        final m = RegExp(r'bytes=(\d+)-').firstMatch(range ?? '');
        if (m != null && ifRange == '"abc"') {
          start = int.parse(m.group(1)!);
          if (start >= body.length) {
            res.statusCode = 416;
            await res.close();
            return;
          }
          res
            ..statusCode = 206
            ..headers.set('content-range', 'bytes $start-${body.length - 1}/${body.length}');
        }
        res.contentLength = body.length - start;
        final drop = dropAfter.isEmpty ? null : dropAfter.removeAt(0);
        if (drop != null) {
          // Part of the body, then hang up, as a lost signal does.
          final socket = await res.detachSocket();
          socket.add(body.sublist(start, start + drop));
          await socket.flush();
          socket.destroy();
          return;
        }
        res.add(body.sublist(start));
        await res.close();
      });
    });
    tearDown(() => server.close(force: true));

    ApiClient api() => ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

    // The test binding answers every HttpClient request with a 400; these
    // talk to the local server for real.
    Future<void> real(Future<void> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());

    test('resumes a dropped download with Range and If-Range', () async {
      await real(() async {
        dropAfter = [70000];
        final path = '${dir.path}/seed.gz';
        String? etag;
        await expectLater(api().downloadSeedFile(path, onStart: (e) => etag = e), throwsA(anything));
        expect(etag, '"abc"');
        final saved = File(path).lengthSync();
        expect(saved, greaterThan(0));

        var last = 0;
        await api().downloadSeedFile(path, etag: etag, onBytes: (got, total) => last = got);
        expect(File(path).readAsBytesSync(), body);
        expect(last, body.length);
        expect(requests.last.range, 'bytes=$saved-');
        expect(requests.last.ifRange, '"abc"');
      });
    });

    test('a file that changed on the server is fetched whole', () async {
      await real(() async {
        final path = '${dir.path}/seed.gz';
        File(path).writeAsBytesSync(List<int>.filled(1000, 9));
        await api().downloadSeedFile(path, etag: '"old"');
        expect(File(path).readAsBytesSync(), body);
      });
    });

    test("a partial file longer than the server's starts over", () async {
      await real(() async {
        final path = '${dir.path}/seed.gz';
        File(path).writeAsBytesSync(List<int>.filled(body.length + 10, 1));
        await api().downloadSeedFile(path, etag: '"abc"');
        expect(File(path).readAsBytesSync(), body);
        expect(requests.map((r) => r.range), ['bytes=${body.length + 10}-', null]);
      });
    });
  });
}

class _OldServer extends ApiClient {
  int calls = 0;

  @override
  Future<Stream<String>> seedLines({DateTime? since, int? afterRank, bool extras = false}) async {
    calls++;
    return Stream.fromIterable([
      jsonEncode({'t': 'meta', 'asOf': '2026-09-26T00:00:00Z', 'entries': 0, 'forms': 0, 'phrases': 0}),
      jsonEncode({'t': 'end'}),
    ]);
  }
}

class _FullDisk extends ApiClient {
  int tries = 0;

  @override
  Future<void> downloadSeedFile(String path, {String? etag, void Function(String? etag)? onStart, void Function(int received, int total)? onBytes}) async {
    tries++;
    throw const FileSystemException('write', 'seed.ndjson.gz', OSError('No space left on device', 28));
  }
}

class _RealHttp extends HttpOverrides {}
