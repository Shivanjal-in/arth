import 'package:arth/app/app.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final store = await LocalStore.open();
  final container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
  await container.read(settingsProvider.notifier).load();
  await container.read(ttsProvider).init();
  final needsSeed = await store.entryCount() == 0;
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ArthApp(needsSeed: needsSeed),
    ),
  );
}
