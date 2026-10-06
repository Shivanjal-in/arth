// Selection tooltip: streamed translation — हिंदी अनुवाद first, then भावार्थ,
// then the difficult words.

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/models/contracts.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/plans/ai_prompt.dart';
import 'package:arth/features/reader/highlights/highlight_bar.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SentenceTooltip extends ConsumerWidget {
  const SentenceTooltip({
    required this.state,
    required this.onTapWord,
    super.key,
    this.onHighlight,
    this.onMakeCard,
  });

  final SentenceTooltipState state;
  final ValueChanged<String> onTapWord;

  /// Highlight this sentence in the book; null when the reader can't place it.
  final ValueChanged<HighlightColor>? onHighlight;

  /// Keep this sentence and its translation as a quote card.
  final VoidCallback? onMakeCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final h = HindiText(settings.hindiScale);
    final tts = ref.watch(ttsProvider);
    final t = ref.watch(stringsProvider);
    TextStyle label(Color color) => uiLabel(hindi: t.isHindi, color: color, scale: settings.hindiScale);

    Widget fade(Widget child, {required bool show}) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: show ? child : const SizedBox.shrink(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(t.translation, style: label(c.accent)),
            const Spacer(),
            if (settings.ttsEnabled && tts.hasHindi && state.hindi != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.volume_up_rounded, color: c.accent, size: 20),
                onPressed: () => tts.speakHindi(state.hindi!),
              ),
            IconButton(
              tooltip: t.copy,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_rounded, color: c.accent, size: 20),
              onPressed: () => copyText(context, state.text),
            ),
            if (!state.done)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
              ),
          ],
        ),
        Text(
          state.text,
          style: EnglishText.italic(c.inkMuted, size: 13.5),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        // Highlighting doesn't wait for the translation: it's the first
        // thing under the sentence.
        if (onHighlight != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Text(t.highlight, style: label(c.inkMuted)),
                const SizedBox(width: 12),
                HighlightColorDots(onPick: onHighlight!, size: 26),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (isAiBlock(state.errorCode))
          AiPrompt(code: state.errorCode!, feature: AiFeature.translate)
        else if (state.error != null && state.hindi == null)
          Text(
            state.errorCode == null ? state.error! : t.errorFor(state.errorCode!, state.error!),
            style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: settings.hindiScale),
          )
        else ...[
          fade(
            Text(state.hindi ?? '', style: h.meaning(c.ink)),
            show: state.hindi != null,
          ),
          fade(
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.simpleMeaning, style: label(c.inkMuted)),
                  Text(state.simpleMeaning ?? '', style: h.body(c.ink)),
                ],
              ),
            ),
            show: state.simpleMeaning != null,
          ),
          fade(
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.difficultWords, style: label(c.inkMuted)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final w in state.difficultWords ?? const <BilingualPair>[])
                        InkWell(
                          onTap: () => onTapWord(w.en),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: c.ink, width: 1.5),
                            ),
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(text: w.en, style: EnglishText.body(c.accent, size: 14)),
                                  TextSpan(text: '  ${w.hi}', style: h.small(c.ink)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            show: (state.difficultWords ?? const []).isNotEmpty,
          ),
        ],
        if (onMakeCard != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Spacer(),
                TextButton.icon(
                    // The quote's back is the translation: wait for it.
                    onPressed: state.done ? onMakeCard : null,
                    style: TextButton.styleFrom(foregroundColor: c.accent, visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.style_outlined, size: 18),
                    label: Text(t.makeCard, style: label(state.done ? c.accent : c.inkMuted)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
