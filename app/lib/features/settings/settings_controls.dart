// The settings controls, shared by the Settings tab and the reader's sheet.
//
// Language is a pair of tiles that show their own script; appearance is a row
// of small page thumbnails; the segmented pill is ink-on-paper rather than the
// Material default; Hindi size shows a live sample line.

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Section heading: serif, sentence case, generous space above.
class SettingsHeading extends ConsumerWidget {
  const SettingsHeading(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    return Padding(
      padding: EdgeInsets.only(top: first ? 8 : 34, bottom: 12),
      child: Text(text, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: s.hindiScale)),
    );
  }
}

/// Small caption under a control.
class SettingsCaption extends ConsumerWidget {
  const SettingsCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale, size: 13.5)),
    );
  }
}

class LanguageTiles extends ConsumerWidget {
  const LanguageTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: _LanguageTile(
            selected: s.language == UiLanguage.en,
            title: 'English',
            titleStyle: (color) => EnglishText.word(color, size: 24),
            sample: t.languageSampleEn,
            sampleStyle: (color) => EnglishText.body(color, size: 13.5),
            onTap: () => n.update((s) => s.copyWith(language: UiLanguage.en)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _LanguageTile(
            selected: s.language == UiLanguage.hi,
            title: 'हिंदी',
            titleStyle: (color) => const HindiText(1).headline(color).copyWith(fontSize: 26),
            sample: t.languageSampleHi,
            sampleStyle: (color) => const HindiText(1).small(color),
            onTap: () => n.update((s) => s.copyWith(language: UiLanguage.hi)),
          ),
        ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.selected,
    required this.title,
    required this.titleStyle,
    required this.sample,
    required this.sampleStyle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final TextStyle Function(Color) titleStyle;
  final String sample;
  final TextStyle Function(Color) sampleStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onAccent : c.ink;
    return Material(
      color: selected ? c.accent : c.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Haptics.choose();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? c.accent : c.rule, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle(fg)),
              const SizedBox(height: 6),
              Text(sample, style: sampleStyle(selected ? c.onAccent.withValues(alpha: 0.85) : c.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Light / Dark / Phone as small pages.
class AppearancePicker extends ConsumerWidget {
  const AppearancePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final n = ref.read(settingsProvider.notifier);
    final options = [
      (ThemeMode.light, t.themePaper),
      (ThemeMode.dark, t.themeNight),
      (ThemeMode.system, t.themeSystem),
    ];
    return Row(
      children: [
        for (final (mode, label) in options) ...[
          Expanded(
            child: _PageThumb(
              mode: mode,
              label: label,
              selected: s.themeMode == mode,
              onTap: () => n.update((s) => s.copyWith(themeMode: mode)),
            ),
          ),
          if (mode != ThemeMode.system) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _PageThumb extends ConsumerWidget {
  const _PageThumb({required this.mode, required this.label, required this.selected, required this.onTap});

  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return InkWell(
      onTap: () {
        Haptics.choose();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 84,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? c.accent : c.rule, width: selected ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(painter: _PagePainter(mode: mode)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: uiLabel(hindi: t.isHindi, color: selected ? c.accent : c.inkMuted, scale: scale),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A miniature page: paper with text lines and one marigold-highlighted word.
class _PagePainter extends CustomPainter {
  _PagePainter({required this.mode});

  final ThemeMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    void page(Rect r, ArthColors p) {
      canvas.drawRect(r, Paint()..color = p.paper);
      final line = Paint()
        ..color = p.ink.withValues(alpha: 0.55)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final left = r.left + 12;
      final widths = [0.62, 0.78, 0.5, 0.72, 0.4];
      for (var i = 0; i < widths.length; i++) {
        final y = r.top + 16 + i * 12.0;
        final w = (r.width - 24) * widths[i];
        canvas.drawLine(Offset(left, y), Offset(left + w, y), line);
      }
      // The highlighted word on line 2.
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(left + 18, r.top + 22, 22, 8), const Radius.circular(2)),
          Paint()..color = p.marigold.withValues(alpha: 0.6),
        )
        ..drawLine(
          Offset(left + 18, r.top + 28),
          Offset(left + 40, r.top + 28),
          Paint()
            ..color = p.accent
            ..strokeWidth = 2,
        );
    }

    final full = Offset.zero & size;
    switch (mode) {
      case ThemeMode.light:
        page(full, ArthColors.light);
      case ThemeMode.dark:
        page(full, ArthColors.dark);
      case ThemeMode.system:
        page(full, ArthColors.light);
        canvas
          ..save()
          ..clipPath(
            Path()
              ..moveTo(size.width, 0)
              ..lineTo(size.width, size.height)
              ..lineTo(0, size.height)
              ..close(),
          );
        page(full, ArthColors.dark);
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) => old.mode != mode;
}

/// Ink-on-paper segmented pill.
class InkSegmented<T> extends StatelessWidget {
  const InkSegmented({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<(T, Widget)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.rule),
      ),
      child: Row(
        children: [
          for (final (value, child) in options)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Haptics.choose();
                  onChanged(value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == selected ? c.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: value == selected ? c.paper : c.ink),
                    child: IconTheme.merge(
                      data: IconThemeData(color: value == selected ? c.paper : c.ink),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TooltipDetailControl extends ConsumerWidget {
  const TooltipDetailControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget label(String text) => Builder(
          builder: (ctx) => Text(
            text,
            style: uiLabel(hindi: t.isHindi, color: DefaultTextStyle.of(ctx).style.color!, scale: s.hindiScale)
                .copyWith(fontSize: t.isHindi ? null : 14),
          ),
        );
    return InkSegmented<TooltipDetail>(
      options: [
        (TooltipDetail.compact, label(t.tooltipCompact)),
        (TooltipDetail.detailed, label(t.tooltipDetailed)),
      ],
      selected: s.tooltipDetail,
      onChanged: (v) => n.update((s) => s.copyWith(tooltipDetail: v)),
    );
  }
}

class HindiSizeControl extends ConsumerWidget {
  const HindiSizeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget glyph(double size) => Builder(
          builder: (ctx) => Text(
            'अ',
            style: const HindiText(1).meaning(DefaultTextStyle.of(ctx).style.color!).copyWith(fontSize: size, height: 1.2),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkSegmented<HindiSize>(
          options: [
            (HindiSize.small, glyph(15)),
            (HindiSize.medium, glyph(18)),
            (HindiSize.large, glyph(22)),
          ],
          selected: s.hindiSize,
          onChanged: (v) => n.update((s) => s.copyWith(hindiSize: v)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, left: 4),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 160),
            style: HindiText(s.hindiScale).meaning(c.ink),
            child: Text(t.hindiSizeSample),
          ),
        ),
      ],
    );
  }
}

class SettingsSwitch extends ConsumerWidget {
  const SettingsSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    return InkWell(
      onTap: () {
        Haptics.choose();
        onChanged(!value);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: uiBody(hindi: t.isHindi, color: c.ink, scale: s.hindiScale, size: 16.5)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale, size: 13.5),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: value,
              onChanged: (v) {
                Haptics.choose();
                onChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}
