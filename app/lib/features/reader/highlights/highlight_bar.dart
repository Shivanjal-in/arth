// The highlighter's colour picker: four inks, translate, and — for an
// existing highlight — remove. Sits in the tooltip card over the selection.

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/reader/highlights/highlight_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A row of colour dots. [selected] gets a ring.
class HighlightColorDots extends StatelessWidget {
  const HighlightColorDots({required this.onPick, super.key, this.selected, this.size = 28});

  final ValueChanged<HighlightColor> onPick;
  final HighlightColor? selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in HighlightColor.values)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onPick(color),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: HighlightPalette.swatch(color),
                  shape: BoxShape.circle,
                  border: Border.all(color: color == selected ? c.ink : Colors.transparent, width: 2),
                ),
                child: color == selected ? Icon(Icons.check_rounded, size: size * 0.6, color: c.ink) : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Whether [text] is one word, which gets its meaning rather than a translation.
bool isSingleWord(String text) => !text.trim().contains(RegExp(r'\s'));

/// Put [text] on the clipboard and say so.
Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  final t = ProviderScope.containerOf(context).read(stringsProvider);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.copied), duration: const Duration(seconds: 1)));
}

class HighlightBar extends ConsumerWidget {
  const HighlightBar({
    required this.onColor,
    required this.onTranslate,
    required this.text,
    required this.onCopy,
    super.key,
    this.selected,
    this.onRemove,
  });

  /// The selected text: one word offers its meaning, more offers translation.
  final String text;
  final VoidCallback onCopy;

  final HighlightColor? selected;
  final ValueChanged<HighlightColor> onColor;
  final VoidCallback onTranslate;

  /// Null for a new selection (nothing to remove yet).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    return Row(
      children: [
        HighlightColorDots(selected: selected, onPick: onColor),
        const Spacer(),
        // A single word's copy button is beside the speaker in its tooltip.
        if (!isSingleWord(text))
          IconButton(
            tooltip: t.copy,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded, color: c.accent, size: 20),
            onPressed: onCopy,
          ),
        IconButton(
          tooltip: isSingleWord(text) ? t.meaning : t.translateSentence,
          visualDensity: VisualDensity.compact,
          icon: Icon(isSingleWord(text) ? Icons.menu_book_rounded : Icons.translate_rounded, color: c.accent, size: 20),
          onPressed: onTranslate,
        ),
        if (onRemove != null)
          IconButton(
            tooltip: t.removeHighlight,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, color: c.accent, size: 20),
            onPressed: onRemove,
          ),
      ],
    );
  }
}
