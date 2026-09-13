// Reading settings, reachable from the reader and reused by the Settings tab.

import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
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
  const ReadingSettings({super.key, this.showLanguage = false});

  /// The language switch lives on the Settings tab, not in the reader sheet.
  final bool showLanguage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final n = ref.read(settingsProvider.notifier);
    final rowText = uiBody(hindi: t.isHindi, color: c.ink, scale: s.hindiScale, size: 16);
    final helpText = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale, size: 13);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLanguage)
          _Row(
            label: t.language,
            child: SegmentedButton<UiLanguage>(
              segments: const [
                ButtonSegment(value: UiLanguage.en, label: Text('English')),
                ButtonSegment(value: UiLanguage.hi, label: Text('हिंदी')),
              ],
              selected: {s.language},
              onSelectionChanged: (v) => n.update((s) => s.copyWith(language: v.first)),
            ),
          ),
        _Row(
          label: t.theme,
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.light, label: Text(t.themePaper)),
              ButtonSegment(value: ThemeMode.dark, label: Text(t.themeNight)),
              ButtonSegment(value: ThemeMode.system, label: Text(t.themeSystem)),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => n.update((s) => s.copyWith(themeMode: v.first)),
          ),
        ),
        _Row(
          label: t.tooltipDetail,
          child: SegmentedButton<TooltipDetail>(
            segments: [
              ButtonSegment(value: TooltipDetail.compact, label: Text(t.tooltipCompact)),
              ButtonSegment(value: TooltipDetail.detailed, label: Text(t.tooltipDetailed)),
            ],
            selected: {s.tooltipDetail},
            onSelectionChanged: (v) => n.update((s) => s.copyWith(tooltipDetail: v.first)),
          ),
        ),
        _Row(
          label: t.hindiSize,
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
          title: Text(t.tts, style: rowText),
          value: s.ttsEnabled,
          activeThumbColor: c.accent,
          onChanged: (v) => n.update((s) => s.copyWith(ttsEnabled: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.prefetch, style: rowText),
          subtitle: Text(t.prefetchHelp, style: helpText),
          value: s.prefetch,
          activeThumbColor: c.accent,
          onChanged: (v) => n.update((s) => s.copyWith(prefetch: v)),
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
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale)),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }
}
