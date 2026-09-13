// Single-word tooltip: dictionary entry immediately, "इस वाक्य में" pinned on
// top when /context lands, never replaced by an error.

import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/features/dictionary/entry_widgets.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WordTooltip extends ConsumerWidget {
  const WordTooltip({
    required this.state,
    required this.onShowDetails,
    required this.onSuggestion,
    super.key,
    this.bookId,
    this.bookTitle,
  });

  final WordTooltipState state;
  final VoidCallback onShowDetails;
  final ValueChanged<String> onSuggestion;
  final int? bookId;
  final String? bookTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final h = HindiText(settings.hindiScale);
    final outcome = state.outcome;

    if (outcome == null) {
      return Row(
        children: [
          Text(state.token, style: EnglishText.word(c.ink)),
          const Spacer(),
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
        ],
      );
    }

    return switch (outcome) {
      LookupMissing(:final word, :final suggestions, :final offline) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(word.isEmpty ? state.token : word, style: EnglishText.word(c.ink)),
            const SizedBox(height: 6),
            Text(
              offline
                  ? 'और अर्थ देखने के लिए इंटरनेट चाहिए'
                  : 'यह शब्द शब्दकोश में नहीं मिला।',
              style: h.body(c.inkMuted),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('क्या आपका मतलब था:', style: h.label(c.inkMuted)),
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
              sentence: state.sentence,
              bookId: bookId,
              bookTitle: bookTitle,
            ),
            if (phrase != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('मुहावरा · ${phrase.phrase}', style: h.small(c.inkMuted)),
              ),
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onShowDetails,
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: Text('पूरा अर्थ देखें  ›', style: h.label(c.accent)),
              ),
            ),
          ],
        ),
    };
  }
}
