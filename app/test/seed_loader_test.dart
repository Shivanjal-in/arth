import 'dart:convert';

import 'package:arth/data/api_client.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// /v1/seed over an in-memory dictionary whose slice ends at [maxRank].
class FakeSeedApi extends ApiClient {
  FakeSeedApi(this.ranks);

  final List<int> ranks;
  int maxRank = 0;
  final calls = <String>[];

  @override
  Future<Stream<String>> seedLines({DateTime? since, int? afterRank}) async {
    calls.add(afterRank != null ? 'after $afterRank' : since != null ? 'delta' : 'full');
    final slice = [
      for (final r in ranks)
        if (r <= maxRank && (afterRank == null || r > afterRank) && since == null) r,
    ];
    final entry = {'word': 'w', 'phonetic': '', 'senses': <Object>[]};
    return Stream.fromIterable([
      jsonEncode({'t': 'meta', 'asOf': '2026-09-26T00:00:00Z', 'entries': slice.length, 'forms': 0, 'phrases': 0, 'maxRank': maxRank}),
      for (final r in slice) jsonEncode({'t': 'entry', 'word': 'word$r', 'freqRank': r, 'entry': entry}),
      jsonEncode({'t': 'end'}),
    ]);
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
}

class _OldServer extends ApiClient {
  int calls = 0;

  @override
  Future<Stream<String>> seedLines({DateTime? since, int? afterRank}) async {
    calls++;
    return Stream.fromIterable([
      jsonEncode({'t': 'meta', 'asOf': '2026-09-26T00:00:00Z', 'entries': 0, 'forms': 0, 'phrases': 0}),
      jsonEncode({'t': 'end'}),
    ]);
  }
}
