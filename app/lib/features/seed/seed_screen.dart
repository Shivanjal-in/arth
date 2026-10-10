// First launch: download the on-device dictionary with visible progress.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SeedScreen extends ConsumerStatefulWidget {
  const SeedScreen({super.key});

  @override
  ConsumerState<SeedScreen> createState() => _SeedScreenState();
}

class _SeedScreenState extends ConsumerState<SeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  // The download lives in seedProvider, so it carries on (and retries) after
  // the reader skips ahead; build() moves on to the library when it's done.
  void _start() => unawaited(ref.read(seedProvider.notifier).run(delta: false));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final t = ref.watch(stringsProvider);
    final p = ref.watch(seedProvider);
    ref.listen(seedProvider, (_, next) {
      if (next.phase == SeedPhase.done) context.go('/');
    });
    final body = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('अ', style: const HindiText(1).headline(c.accent).copyWith(fontSize: 72, height: 1)),
              const SizedBox(height: 24),
              Text(t.seedTitle, style: uiHeadline(hindi: t.isHindi, color: c.ink, scale: scale)),
              const SizedBox(height: 6),
              Text(t.seedBody, style: body),
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: p.phase == SeedPhase.downloading ? p.fraction : (p.phase == SeedPhase.done ? 1 : 0),
                color: c.marigold,
                backgroundColor: c.rule,
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                seedStatusText(t, p),
                style: uiBody(hindi: t.isHindi, color: p.phase == SeedPhase.failed ? c.accent : c.inkMuted, scale: scale, size: 13),
              ),
              if (p.phase == SeedPhase.failed) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: c.accent),
                      onPressed: _start,
                      child: Text(t.retry),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => context.go('/'),
                      child: Text(t.skipForNow, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                    ),
                  ],
                ),
              ] else if (p.phase != SeedPhase.done) ...[
                // The download lives in seedProvider, not this screen, so it
                // keeps going after the reader moves on.
                const SizedBox(height: 28),
                Text(t.seedKeepsGoing, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14)),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => context.go('/'),
                  child: Text(t.skipForNow, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line on how the download is going; Settings shows it too.
String seedStatusText(AppStrings t, SeedProgress p) {
  if (p.phase == SeedPhase.failed) return seedFailureText(t, p.failure);
  if (p.retrying) return p.failure == SeedFailure.offline ? t.seedWaitingForNetwork : t.seedTryingAgain;
  if (p.total == 0) return t.connecting;
  return p.stage == SeedStage.download ? t.seedDownloading(p.done, p.total) : t.seedSaving(p.done, p.total);
}

String seedFailureText(AppStrings t, SeedFailure? f) => switch (f) {
      SeedFailure.offline => t.seedOffline,
      SeedFailure.server => t.seedServerDown,
      SeedFailure.storage => t.seedNoSpace,
      SeedFailure.unknown || null => t.downloadFailed,
    };
