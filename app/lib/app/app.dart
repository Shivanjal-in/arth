import 'dart:async';
import 'dart:io';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/dev_hooks.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/reminders.dart';
import 'package:arth/app/router.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:arth/features/scan/scan_pages.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class ArthApp extends ConsumerStatefulWidget {
  const ArthApp({required this.needsSeed, super.key});

  final bool needsSeed;

  @override
  ConsumerState<ArthApp> createState() => _ArthAppState();
}

class _ArthAppState extends ConsumerState<ArthApp> {
  late final GoRouter router = buildRouter(needsSeed: widget.needsSeed);
  StreamSubscription<String>? _pushRoutes;
  StreamSubscription<String>? _localRoutes;

  @override
  void initState() {
    super.initState();
    // Screen views, by route pattern (never a word or book id).
    router.routerDelegate.addListener(_trackScreen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _trackScreen());
    // A tapped notification opens its screen (the app may have been closed).
    final push = ref.read(pushServiceProvider);
    if (push != null) {
      _pushRoutes = push.routes.stream.listen((r) => openFromNotification(router, r));
      final pending = push.pendingRoute;
      push.pendingRoute = null;
      if (pending != null && !widget.needsSeed) WidgetsBinding.instance.addPostFrameCallback((_) => openFromNotification(router, pending));
    }
    // …and so does a tapped reminder, or a push shown while the app was open.
    final local = ref.read(localNotificationsProvider);
    _localRoutes = local.routes.stream.listen((r) => openFromNotification(router, r));
    final launch = local.launchRoute;
    local.launchRoute = null;
    if (launch != null && launch.isNotEmpty && !widget.needsSeed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openFromNotification(router, launch));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDictionaryIfStale());
    DevHooks.on('nav', (p) async {
      final lang = p['lang'];
      if (lang != null) {
        await ref.read(settingsProvider.notifier).update(
              (s) => s.copyWith(language: lang == 'hi' ? UiLanguage.hi : UiLanguage.en),
            );
      }
      final theme = p['theme'];
      if (theme != null) {
        await ref.read(settingsProvider.notifier).update(
              (s) => s.copyWith(themeMode: ThemeMode.values.byName(theme)),
            );
      }
      if (p['to'] != null) router.go(p['to']!);
      return {'ok': true};
    });
    DevHooks.on('scan', (p) async {
      // Simulators have no camera: fetch a page image and create a scan from it.
      final url = p['url']!;
      final tmp = File('${ref.read(documentsDirProvider)}/dev-scan.jpg');
      await Dio().download(url, tmp.path);
      final book = await createScan(ref, XFile(tmp.path), title: 'Dev scan');
      router.go('/scan/${book.id}');
      return {'ok': true, 'id': book.id};
    });
  }

  @override
  void dispose() {
    router.routerDelegate.removeListener(_trackScreen);
    unawaited(_pushRoutes?.cancel());
    unawaited(_localRoutes?.cancel());
    super.dispose();
  }

  void _trackScreen() {
    final analytics = ref.read(analyticsProvider);
    final route = router.routerDelegate.currentConfiguration.fullPath;
    if (!analytics.screen(route)) return;
    final format = switch (route) {
      '/read/:id' => 'pdf',
      '/epub/:id' => 'epub',
      '/scan/:id' => 'scan',
      _ => null,
    };
    if (format != null) analytics.track('Book Opened', {'format': format});
  }

  /// Pull the entry delta quietly once a day so the on-device dictionary
  /// follows the server (the full build landed after some phones seeded).
  Future<void> _refreshDictionaryIfStale() async {
    if (widget.needsSeed) return; // the seed screen handles the first run
    final store = ref.read(localStoreProvider);
    final last = DateTime.tryParse(await store.get('seed_checked_at') ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return;
    final r = await ref.read(seedProvider.notifier).run();
    if (r.phase == SeedPhase.done) {
      await store.set('seed_checked_at', DateTime.now().toIso8601String());
      ref.invalidate(localEntryCountProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    Haptics.enabled = ref.watch(settingsProvider.select((s) => s.haptics));
    return MaterialApp.router(
      title: 'Arth',
      debugShowCheckedModeBanner: false,
      theme: arthTheme(Brightness.light),
      darkTheme: arthTheme(Brightness.dark),
      themeMode: mode,
      routerConfig: router,
      // iOS keyboards have no hide key: a tap on anything that isn't a text
      // field or a control puts the keyboard away.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
    );
  }
}
