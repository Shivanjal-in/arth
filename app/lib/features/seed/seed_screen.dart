// First launch: download the on-device dictionary with visible progress.

import 'package:arth/app/providers.dart';
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

  Future<void> _start() async {
    final r = await ref.read(seedProvider.notifier).run(delta: false);
    ref.invalidate(localEntryCountProvider);
    if (mounted && r.phase == SeedPhase.done) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = HindiText(ref.watch(settingsProvider).hindiScale);
    final p = ref.watch(seedProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('अर्थ', style: EnglishText.word(c.accent, size: 44)),
              const SizedBox(height: 24),
              Text('शब्दकोश तैयार हो रहा है', style: h.headline(c.ink)),
              const SizedBox(height: 6),
              Text(
                'एक बार डाउनलोड होने के बाद आम शब्द बिना इंटरनेट भी मिलेंगे।',
                style: h.body(c.inkMuted),
              ),
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: p.phase == SeedPhase.downloading ? p.fraction : (p.phase == SeedPhase.done ? 1 : 0),
                color: c.accent,
                backgroundColor: c.rule,
                minHeight: 4,
              ),
              const SizedBox(height: 8),
              Text(
                p.phase == SeedPhase.failed
                    ? (p.message ?? 'डाउनलोड नहीं हो पाया।')
                    : p.total == 0
                        ? 'जुड़ रहा है…'
                        : '${p.done} / ${p.total}',
                style: h.small(p.phase == SeedPhase.failed ? c.accent : c.inkMuted),
              ),
              if (p.phase == SeedPhase.failed) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: c.accent),
                      onPressed: _start,
                      child: const Text('फिर कोशिश करें'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => context.go('/'),
                      child: Text('अभी छोड़ें', style: h.label(c.inkMuted)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
