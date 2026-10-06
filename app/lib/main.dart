import 'dart:async';
import 'dart:io';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/app.dart';
import 'package:arth/app/firebase_setup.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/reminders.dart';
import 'package:arth/data/book_keys.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/ads/ads.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// Development only: PDF or EPUB URLs (comma-separated) to import into an
/// empty library on launch, so a reader can be exercised on a simulator
/// without the file picker.
///   flutter run --dart-define=ARTH_DEV_PDF_URL=http://host:8765/book.pdf
const String _devPdfUrl = String.fromEnvironment('ARTH_DEV_PDF_URL');

const _fontLicenses = [
  ('Montserrat', 'OFL-montserrat.txt'),
  ('Literata', 'OFL-literata.txt'),
  ('Mukta', 'OFL-mukta.txt'),
  ('Noto Sans', 'OFL-notosans.txt'),
  ('Kaushan Script', 'OFL-kaushanscript.txt'),
  ('Quintessential', 'OFL-quintessential.txt'),
  ('Bricolage Grotesque', 'OFL-bricolagegrotesque.txt'),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled fonts' licenses (SIL OFL), for the licence page.
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in _fontLicenses) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/google_fonts/$file'));
    }
  });
  await pdfrxFlutterInitialize();
  final store = await LocalStore.open();
  final docsDir = (await getApplicationDocumentsDirectory()).path;
  final deviceId = await loadDeviceId(store);
  final firebaseReady = await initFirebase();
  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      documentsDirProvider.overrideWithValue(docsDir),
      deviceIdProvider.overrideWithValue(deviceId),
      firebaseReadyProvider.overrideWithValue(firebaseReady),
    ],
  );
  await container.read(settingsProvider.notifier).load();
  await container.read(ttsProvider).init();
  // Starts listening for sign-in so the first sync runs without a screen asking.
  container.read(syncProvider);
  // Notifications: set up handlers now; the token is registered on sign-in.
  await container.read(localNotificationsProvider).init();
  container.read(cardRemindersProvider); // schedules, and follows card changes
  await container.read(analyticsProvider).init(optedOut: !container.read(settingsProvider).usageStats);
  // Plans in the app stores; logs in with the account once sign-in is restored.
  await container.read(billingProvider).init();
  final push = container.read(pushServiceProvider);
  if (push != null) {
    try {
      await push.init();
    } on Exception catch (e) {
      debugPrint('push init failed: $e');
    }
  }
  final needsSeed = await store.entryCount() == 0;
  await _importDevPdf(store, docsDir);
  unawaited(backfillContentKeys(store, docsDir));
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ArthApp(needsSeed: needsSeed),
    ),
  );
  // After the first frame: the consent form (where required) needs a screen.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(initAds(container)));
}

Future<void> _importDevPdf(LocalStore store, String docsDir) async {
  if (_devPdfUrl.isEmpty || (await store.books()).isNotEmpty) return;
  for (final url in _devPdfUrl.split(',')) {
    try {
      await Directory(p.join(docsDir, 'books')).create(recursive: true);
      final rel = p.join('books', p.basename(Uri.parse(url).path));
      await Dio().download(url, p.join(docsDir, rel));
      final kind = p.extension(rel).toLowerCase() == '.pdf' ? BookKind.pdf : BookKind.epub;
      await store.addBook(title: p.basenameWithoutExtension(rel).replaceAll(RegExp('[_-]+'), ' '), path: rel, kind: kind);
    } on Exception catch (e) {
      debugPrint('dev import failed for $url: $e');
    }
  }
}
