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
    final t = ref.watch(stringsProvider);
    final body = uiBody(hindi: t.isHindi, color: c.ink, scale: s.hindiScale);
    final help = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale, size: 13);
    final count = ref.watch(localEntryCountProvider).valueOrNull;
    final seed = ref.watch(seedProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          SectionLabel(t.sectionReading),
          const ReadingSettings(showLanguage: true),
          SectionLabel(t.sectionDictionary),
          Text(count == null ? '…' : t.wordsOnDevice(count), style: body),
          const SizedBox(height: 8),
          if (seed.phase == SeedPhase.downloading)
            LinearProgressIndicator(value: seed.fraction, color: c.accent, backgroundColor: c.rule)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(t.updateDictionary, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: s.hindiScale)),
                style: OutlinedButton.styleFrom(foregroundColor: c.accent, side: BorderSide(color: c.rule)),
                onPressed: () async {
                  final r = await ref.read(seedProvider.notifier).run(delta: count != 0);
                  ref.invalidate(localEntryCountProvider);
                  if (context.mounted && r.phase == SeedPhase.failed) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? t.downloadFailed)));
                  }
                },
              ),
            ),
          if (seed.phase == SeedPhase.failed && seed.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(seed.message!, style: help.copyWith(color: c.accent)),
            ),
          SectionLabel(t.sectionServer),
          TextFormField(
            initialValue: s.apiBaseUrl ?? '',
            style: EnglishText.body(c.ink),
            decoration: InputDecoration(
              hintText: kApiBaseUrl,
              hintStyle: EnglishText.body(c.inkMuted),
              helperText: t.serverHelp,
              helperStyle: help,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onFieldSubmitted: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(apiBaseUrl: () => v.trim().isEmpty ? null : v.trim())),
          ),
          SectionLabel(t.sectionInfo),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.about, style: body.copyWith(fontSize: 17)),
            trailing: Icon(Icons.chevron_right_rounded, color: c.inkMuted),
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }
}
