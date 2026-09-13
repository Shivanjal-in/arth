// Reading settings from inside the reader: the subset that changes the page
// you're on. Language lives on the Settings tab.

import 'package:arth/app/providers.dart';
import 'package:arth/features/settings/settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showReadingSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: ReadingSettings(),
      ),
    );

class ReadingSettings extends ConsumerWidget {
  const ReadingSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(t.theme, first: true),
        const AppearancePicker(),
        SettingsHeading(t.tooltipDetail),
        const TooltipDetailControl(),
        SettingsHeading(t.hindiSize),
        const HindiSizeControl(),
        const SizedBox(height: 16),
        SettingsSwitch(
          title: t.tts,
          value: s.ttsEnabled,
          onChanged: (v) => n.update((s) => s.copyWith(ttsEnabled: v)),
        ),
        SettingsSwitch(
          title: t.prefetch,
          value: s.prefetch,
          onChanged: (v) => n.update((s) => s.copyWith(prefetch: v)),
        ),
      ],
    );
  }
}
