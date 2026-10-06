// Single-word tooltip: dictionary entry immediately, "इस वाक्य में" pinned on
// top when /context lands, never replaced by an error.

import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/features/dictionary/entry_widgets.dart';
import 'package:arth/features/plans/ai_prompt.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WordTooltip extends ConsumerWidget {
  const WordTooltip({
    required this.state,
    required this.onShowDetails,
    required this.onSuggestion,
    required this.onTranslateSentence,
    super.key,
    this.bookId,
    this.bookTitle,
    this.onMakeCard,
  });

  final WordTooltipState state;
  final VoidCallback onShowDetails;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onTranslateSentence;
  final int? bookId;
  final String? bookTitle;
  final VoidCallback? onMakeCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final body = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: settings.hindiScale);
    final label = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: settings.hindiScale);
    final outcome = state.outcome;

    if (outcome == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(state.token, style: EnglishText.word(c.ink)),
              const Spacer(),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(t.lookingUp, style: body),
        ],
      );
    }

    return switch (outcome) {
      LookupMissing(:final word, :final suggestions, :final offline, :final blockedCode) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(word.isEmpty ? state.token : word, style: EnglishText.word(c.ink)),
            if (isAiBlock(blockedCode))
              AiPrompt(code: blockedCode!, feature: AiFeature.rareWord)
            else ...[
              const SizedBox(height: 6),
              Text(offline ? t.offline : t.notFound, style: body),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t.didYouMean, style: label),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s, style: EnglishText.body(c.accent)),
                      side: BorderSide(color: c.rule),
                      backgroundColor: c.card,
                      onPressed: () => onSuggestion(s),
                    ),
                ],
              ),
            ],
          ],
        ),
      LookupFound(:final entry, :final phrase) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EntryHeader(
              entry: entry,
              compact: true,
              copyable: true,
              sentence: state.sentence,
              bookId: bookId,
              bookTitle: bookTitle,
            ),
            if (phrase != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${t.phrase} · ${phrase.phrase}', style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: settings.hindiScale, size: 13)),
              ),
            if (isAiBlock(state.contextErrorCode))
              AiPrompt(code: state.contextErrorCode!, feature: AiFeature.context)
            else if (state.contextOffered)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: ref.read(readerControllerProvider.notifier).explainInContext,
                  style: TextButton.styleFrom(foregroundColor: c.accent, padding: const EdgeInsets.symmetric(horizontal: 4)),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(t.explainInSentence, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: settings.hindiScale)),
                ),
              )
            else
              InContextBlock(
                result: state.context,
                loading: state.contextLoading,
                entry: entry,
              ),
            SenseList(
              senses: entry.senses,
              max: settings.tooltipDetail == TooltipDetail.compact ? 3 : 5,
              detail: settings.tooltipDetail,
              pinnedIndex: state.context?.senseIndex,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Saving is the bookmark in the header; the reader's own
                // action here is the card.
                if (onMakeCard != null)
                  TextButton.icon(
                    onPressed: onMakeCard,
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    icon: const Icon(Icons.style_outlined, size: 20),
                    label: Text(t.makeCard, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: settings.hindiScale)),
                  )
                else
                  SaveWordButton(
                    entry: entry,
                    sentence: state.sentence,
                    bookId: bookId,
                    bookTitle: bookTitle,
                    labelled: true,
                  ),
                const Spacer(),
                IconButton(
                  tooltip: t.translateSentence,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.translate_rounded, color: c.accent, size: 20),
                  onPressed: onTranslateSentence,
                ),
                TextButton(
                  onPressed: onShowDetails,
                  style: TextButton.styleFrom(foregroundColor: c.accent),
                  child: Text(t.seeFullEntry, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: settings.hindiScale)),
                ),
              ],
            ),
          ],
        ),
    };
  }
}
