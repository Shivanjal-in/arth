// Selection tooltip: streamed translation — हिंदी अनुवाद first, then भावार्थ,
// then the difficult words.

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/models/contracts.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SentenceTooltip extends ConsumerWidget {
  const SentenceTooltip({
    required this.state,
    required this.onTapWord,
    super.key,
  });

  final SentenceTooltipState state;
  final ValueChanged<String> onTapWord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final h = HindiText(settings.hindiScale);
    final tts = ref.watch(ttsProvider);

    Widget fade(Widget child, {required bool show}) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: show ? child : const SizedBox.shrink(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('अनुवाद', style: h.label(c.accent)),
            const Spacer(),
            if (settings.ttsEnabled && tts.hasHindi && state.hindi != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.volume_up_rounded, color: c.accent, size: 20),
                onPressed: () => tts.speakHindi(state.hindi!),
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
        const SizedBox(height: 8),
        if (state.error != null && state.hindi == null)
          Text(state.error!, style: h.body(c.inkMuted))
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
                  Text('भावार्थ', style: h.label(c.inkMuted)),
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
                  Text('कठिन शब्द', style: h.label(c.inkMuted)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final w in state.difficultWords ?? const <BilingualPair>[])
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onTapWord(w.en),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: c.rule),
                              borderRadius: BorderRadius.circular(8),
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
      ],
    );
  }
}
