import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:arth/features/dictionary/entry_widgets.dart';
import 'package:arth/features/settings/reading_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final h = HindiText(s.hindiScale);
    final count = ref.watch(localEntryCountProvider).valueOrNull;
    final seed = ref.watch(seedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('आप')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          const SectionLabel('पढ़ना', hindi: true),
          const ReadingSettings(),
          const SectionLabel('शब्दकोश', hindi: true),
          Text(
            count == null ? '…' : 'फ़ोन पर $count शब्द सहेजे हैं — बिना इंटरनेट भी काम करते हैं।',
            style: h.body(c.ink),
          ),
          const SizedBox(height: 8),
          if (seed.phase == SeedPhase.downloading)
            LinearProgressIndicator(value: seed.fraction, color: c.accent, backgroundColor: c.rule)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text('शब्दकोश अपडेट करें', style: h.label(c.accent)),
                style: OutlinedButton.styleFrom(foregroundColor: c.accent, side: BorderSide(color: c.rule)),
                onPressed: () async {
                  final r = await ref.read(seedProvider.notifier).run(delta: count != 0);
                  ref.invalidate(localEntryCountProvider);
                  if (context.mounted && r.phase == SeedPhase.failed) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? '')));
                  }
                },
              ),
            ),
          if (seed.phase == SeedPhase.failed && seed.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(seed.message!, style: h.small(c.accent)),
            ),
          const SectionLabel('सर्वर', hindi: true),
          TextFormField(
            initialValue: s.apiBaseUrl ?? '',
            style: EnglishText.body(c.ink),
            decoration: InputDecoration(
              hintText: kApiBaseUrl,
              hintStyle: EnglishText.body(c.inkMuted),
              helperText: 'खाली छोड़ें तो बिल्ड का डिफ़ॉल्ट इस्तेमाल होगा',
              helperStyle: h.small(c.inkMuted),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onFieldSubmitted: (v) =>
                ref.read(settingsProvider.notifier).update((s) => s.copyWith(apiBaseUrl: () => v.trim().isEmpty ? null : v.trim())),
          ),
          const SectionLabel('जानकारी', hindi: true),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Arth के बारे में', style: h.meaning(c.ink)),
            trailing: Icon(Icons.chevron_right_rounded, color: c.inkMuted),
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }
}
