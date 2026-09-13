// Reading settings, reachable from the reader and reused by the Settings tab.

import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showReadingSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: ReadingSettings(),
      ),
    );

class ReadingSettings extends ConsumerWidget {
  const ReadingSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: 'रंग',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('कागज़')),
              ButtonSegment(value: ThemeMode.dark, label: Text('रात')),
              ButtonSegment(value: ThemeMode.system, label: Text('फ़ोन')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => n.update((s) => s.copyWith(themeMode: v.first)),
          ),
        ),
        _Row(
          label: 'टूलटिप',
          child: SegmentedButton<TooltipDetail>(
            segments: const [
              ButtonSegment(value: TooltipDetail.compact, label: Text('छोटा')),
              ButtonSegment(value: TooltipDetail.detailed, label: Text('विस्तार से')),
            ],
            selected: {s.tooltipDetail},
            onSelectionChanged: (v) => n.update((s) => s.copyWith(tooltipDetail: v.first)),
          ),
        ),
        _Row(
          label: 'हिंदी का आकार',
          child: SegmentedButton<HindiSize>(
            segments: const [
              ButtonSegment(value: HindiSize.small, label: Text('अ', style: TextStyle(fontSize: 13))),
              ButtonSegment(value: HindiSize.medium, label: Text('अ', style: TextStyle(fontSize: 16))),
              ButtonSegment(value: HindiSize.large, label: Text('अ', style: TextStyle(fontSize: 20))),
            ],
            selected: {s.hindiSize},
            onSelectionChanged: (v) => n.update((s) => s.copyWith(hindiSize: v.first)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('उच्चारण सुनें (TTS)', style: HindiText(s.hindiScale).meaning(context.colors.ink)),
          value: s.ttsEnabled,
          activeThumbColor: context.colors.accent,
          onChanged: (v) => n.update((s) => s.copyWith(ttsEnabled: v)),
        ),
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final h = HindiText(ref.watch(settingsProvider).hindiScale);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: h.label(c.inkMuted)),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }
}
