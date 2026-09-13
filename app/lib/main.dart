import 'dart:io';

import 'package:arth/app/app.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/data/local_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// Development only: a PDF URL to import into an empty library on launch, so
/// the reader can be exercised on a simulator without the file picker.
///   flutter run --dart-define=ARTH_DEV_PDF_URL=http://host:8765/book.pdf
const String _devPdfUrl = String.fromEnvironment('ARTH_DEV_PDF_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final store = await LocalStore.open();
  final docsDir = (await getApplicationDocumentsDirectory()).path;
  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      documentsDirProvider.overrideWithValue(docsDir),
    ],
  );
  await container.read(settingsProvider.notifier).load();
  await container.read(ttsProvider).init();
  final needsSeed = await store.entryCount() == 0;
  await _importDevPdf(store, docsDir);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ArthApp(needsSeed: needsSeed),
    ),
  );
}

Future<void> _importDevPdf(LocalStore store, String docsDir) async {
  if (_devPdfUrl.isEmpty || (await store.books()).isNotEmpty) return;
  try {
    await Directory(p.join(docsDir, 'books')).create(recursive: true);
    final rel = p.join('books', p.basename(Uri.parse(_devPdfUrl).path));
    await Dio().download(_devPdfUrl, p.join(docsDir, rel));
    await store.addBook(title: p.basenameWithoutExtension(rel), path: rel);
  } on Exception catch (e) {
    debugPrint('dev pdf import failed: $e');
  }
}
