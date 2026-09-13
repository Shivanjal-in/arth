import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/seed_loader.dart';
import 'package:arth/features/settings/settings_controls.dart';
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
    final n = ref.read(settingsProvider.notifier);
    final count = ref.watch(localEntryCountProvider).valueOrNull;
    final seed = ref.watch(seedProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
          children: [
            // Masthead: the monogram is the one loud thing on the page.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('अ', style: const HindiText(1).headline(c.accent).copyWith(fontSize: 56, height: 1)),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.settingsTitle, style: uiTitle(hindi: t.isHindi, color: c.ink, scale: s.hindiScale)),
                      Text(t.settingsIntro, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale)),
                    ],
                  ),
                ),
              ],
            ),

            SettingsHeading(t.language),
            const LanguageTiles(),

            SettingsHeading(t.theme),
            const AppearancePicker(),

            SettingsHeading(t.tooltipDetail),
            const TooltipDetailControl(),

            SettingsHeading(t.hindiSize),
            const HindiSizeControl(),

            const SizedBox(height: 26),
            Divider(color: c.rule),
            const SizedBox(height: 6),
            SettingsSwitch(
              title: t.tts,
              value: s.ttsEnabled,
              onChanged: (v) => n.update((s) => s.copyWith(ttsEnabled: v)),
            ),
            SettingsSwitch(
              title: t.prefetch,
              subtitle: t.prefetchHelp,
              value: s.prefetch,
              onChanged: (v) => n.update((s) => s.copyWith(prefetch: v)),
            ),

            SettingsHeading(t.sectionDictionary),
            Text(
              count == null ? '…' : t.wordsOnDevice(count),
              style: uiBody(hindi: t.isHindi, color: c.ink, scale: s.hindiScale, size: 16.5),
            ),
            const SizedBox(height: 12),
            if (seed.phase == SeedPhase.downloading)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: seed.fraction,
                  minHeight: 6,
                  color: c.marigold,
                  backgroundColor: c.rule,
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text(t.updateDictionary, style: uiLabel(hindi: t.isHindi, color: c.onAccent, scale: s.hindiScale)),
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
              SettingsCaption(seed.message!),

            SettingsHeading(t.serverTitle),
            TextFormField(
              initialValue: s.apiBaseUrl ?? '',
              style: EnglishText.body(c.ink, size: 16),
              decoration: InputDecoration(
                hintText: kApiBaseUrl,
                hintStyle: EnglishText.body(c.inkMuted, size: 16),
                helperText: t.serverHelp,
                helperStyle: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale, size: 13),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onFieldSubmitted: (v) => n.update((s) => s.copyWith(apiBaseUrl: () => v.trim().isEmpty ? null : v.trim())),
            ),

            const SizedBox(height: 28),
            Material(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/about'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(t.about, style: uiBody(hindi: t.isHindi, color: c.ink, scale: s.hindiScale, size: 16.5)),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: c.accent, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
