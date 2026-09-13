import 'package:arth/app/providers.dart';
import 'package:arth/app/router.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ArthApp extends ConsumerStatefulWidget {
  const ArthApp({required this.needsSeed, super.key});

  final bool needsSeed;

  @override
  ConsumerState<ArthApp> createState() => _ArthAppState();
}

class _ArthAppState extends ConsumerState<ArthApp> {
  late final GoRouter router = buildRouter(needsSeed: widget.needsSeed);

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'Arth',
      debugShowCheckedModeBanner: false,
      theme: arthTheme(Brightness.light),
      darkTheme: arthTheme(Brightness.dark),
      themeMode: mode,
      routerConfig: router,
    );
  }
}
