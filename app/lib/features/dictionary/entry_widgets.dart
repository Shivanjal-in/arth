// Shared rendering of a DictionaryEntry: used by the tooltip (compact), the
// full-details sheet, the dictionary word screen and saved words.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/models/contracts.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/reader/highlights/highlight_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SectionLabel extends ConsumerWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text,
        style: uiLabel(hindi: settings.language == UiLanguage.hi, color: c.inkMuted, scale: settings.hindiScale),
      ),
    );
  }
}

/// Bookmark toggle for an entry: icon-only in headers, or with a label.
class SaveWordButton extends ConsumerWidget {
  const SaveWordButton({
    required this.entry,
    super.key,
    this.sentence,
    this.bookId,
    this.bookTitle,
    this.labelled = false,
  });

  final DictionaryEntry entry;
  final String? sentence;
  final int? bookId;
  final String? bookTitle;
  final bool labelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final saved = ref.watch(savedWordsProvider).valueOrNull?.any((w) => w.lemma == entry.word && w.bookId == bookId) ?? false;
    void toggle() {
      final notifier = ref.read(savedWordsProvider.notifier);
      if (saved) {
        unawaited(notifier.unsave(entry.word, bookId: bookId));
      } else {
        unawaited(
          notifier.save(
            SavedWord(
              lemma: entry.word,
              meaning: entry.senses.first.meaning,
              sentence: sentence,
              bookId: bookId,
              bookTitle: bookTitle,
              savedAt: DateTime.now(),
            ),
          ),
        );
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(saved ? t.unsave : '${t.saved}: ${entry.word}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final icon = Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: c.accent);
    if (!labelled) {
      return IconButton(tooltip: saved ? t.unsave : t.save, icon: icon, onPressed: toggle);
    }
    return TextButton.icon(
      onPressed: toggle,
      style: TextButton.styleFrom(foregroundColor: c.accent),
      icon: icon,
      label: Text(saved ? t.saved : t.save, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: settings.hindiScale)),
    );
  }
}

/// Word, IPA, Devanagari pronunciation, speaker and save buttons.
class EntryHeader extends ConsumerWidget {
  const EntryHeader({
    required this.entry,
    super.key,
    this.sentence,
    this.bookId,
    this.bookTitle,
    this.compact = false,
    this.copyable = false,
  });

  final DictionaryEntry entry;
  final String? sentence;
  final int? bookId;
  final String? bookTitle;
  final bool compact;

  /// A copy button beside the speaker.
  final bool copyable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final tts = ref.watch(ttsProvider);
    final t = ref.watch(stringsProvider);
    final showTts = settings.ttsEnabled && tts.hasEnglish;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.word, style: EnglishText.word(c.ink, size: compact ? 22 : 30)),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  if (entry.ipa.isNotEmpty)
                    Text('/${entry.ipa}/', style: EnglishText.ipa(c.inkMuted)),
                  if (entry.hindiPronunciation.isNotEmpty)
                    Text(
                      entry.hindiPronunciation,
                      style: HindiText(settings.hindiScale).small(c.inkMuted),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (showTts)
          IconButton(
            tooltip: t.listen,
            icon: Icon(Icons.volume_up_rounded, color: c.accent),
            onPressed: () => tts.speakEnglish(entry.word),
          ),
        if (copyable)
          IconButton(
            tooltip: t.copy,
            icon: Icon(Icons.copy_rounded, color: c.accent),
            onPressed: () => copyText(context, entry.word),
          ),
        SaveWordButton(entry: entry, sentence: sentence, bookId: bookId, bookTitle: bookTitle),
      ],
    );
  }
}

/// The "इस वाक्य में" block. Space is reserved while loading so the tooltip
/// doesn't jump when the context result lands.
class InContextBlock extends ConsumerWidget {
  const InContextBlock({
    required this.result,
    required this.loading,
    super.key,
    this.entry,
  });

  final ContextResult? result;
  final bool loading;
  final DictionaryEntry? entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final h = HindiText(settings.hindiScale);
    final t = ref.watch(stringsProvider);
    final r = result;
    final content = r == null
        ? const SizedBox(height: 48)
        : Column(
            key: const ValueKey('ctx'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.meaning, style: h.headline(c.ink)),
              if (r.note.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(r.note, style: h.body(c.ink)),
              ],
            ],
          );
    if (r == null && !loading) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: c.marigold.withValues(alpha: 0.13),
        border: Border(left: BorderSide(color: c.marigold, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.inThisSentence, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: settings.hindiScale)),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: content,
          ),
        ],
      ),
    );
  }
}

/// Numbered senses. [max] limits the list for the compact tooltip.
class SenseList extends ConsumerWidget {
  const SenseList({
    required this.senses,
    super.key,
    this.max,
    this.detail = TooltipDetail.detailed,
    this.pinnedIndex,
  });

  final List<Sense> senses;
  final int? max;
  final TooltipDetail detail;

  /// The sense picked by /context, shown first and marked.
  final int? pinnedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final h = HindiText(settings.hindiScale);
    final t = ref.watch(stringsProvider);
    var ordered = [...senses];
    if (pinnedIndex != null && pinnedIndex! < ordered.length) {
      final p = ordered.removeAt(pinnedIndex!);
      ordered = [p, ...ordered];
    }
    final shown = max == null ? ordered : ordered.take(max!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in shown) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${s.index + 1}',
                  style: EnglishText.label(c.accent, size: 12.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: h.meaning(c.ink),
                      children: [
                        TextSpan(text: s.meaning),
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: s.partOfSpeech,
                          style: h.small(c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (detail == TooltipDetail.detailed) ...[
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(s.definition, style: h.body(c.ink)),
            ),
            for (final ex in s.examples)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 6),
                child: Container(
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: c.rule, width: 2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex.en, style: EnglishText.italic(c.inkMuted)),
                      Text(ex.hi, style: h.small(c.ink)),
                    ],
                  ),
                ),
              ),
          ],
        ],
        if (max != null && ordered.length > max!)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 22),
            child: Text(
              t.moreSenses(ordered.length - max!),
              style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: settings.hindiScale, size: 13),
            ),
          ),
      ],
    );
  }
}

class PairWrap extends ConsumerWidget {
  const PairWrap(this.pairs, {super.key, this.onTapWord});

  final List<BilingualPair> pairs;
  final ValueChanged<String>? onTapWord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final h = HindiText(ref.watch(settingsProvider).hindiScale);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final p in pairs)
          GestureDetector(
            onTap: onTapWord == null ? null : () => onTapWord!(p.en),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: p.en, style: EnglishText.body(c.ink, size: 16)),
                  const TextSpan(text: ' '),
                  TextSpan(text: p.hi, style: h.small(c.inkMuted)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything about an entry, for the sheet and the word screen.
class EntryDetails extends ConsumerWidget {
  const EntryDetails({
    required this.entry,
    super.key,
    this.context,
    this.contextLoading = false,
    this.sentence,
    this.bookId,
    this.bookTitle,
    this.onTapWord,
  });

  final DictionaryEntry entry;
  final ContextResult? context;
  final bool contextLoading;
  final String? sentence;
  final int? bookId;
  final String? bookTitle;
  final ValueChanged<String>? onTapWord;

  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    final c = ctx.colors;
    final settings = ref.watch(settingsProvider);
    final h = HindiText(settings.hindiScale);
    final t = ref.watch(stringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EntryHeader(
          entry: entry,
          sentence: sentence,
          bookId: bookId,
          bookTitle: bookTitle,
        ),
        if (context != null || contextLoading)
          InContextBlock(result: context, loading: contextLoading, entry: entry),
        SectionLabel(t.meanings),
        SenseList(senses: entry.senses, pinnedIndex: context?.senseIndex),
        if (entry.synonyms.isNotEmpty) ...[
          SectionLabel(t.synonyms),
          PairWrap(entry.synonyms, onTapWord: onTapWord),
        ],
        if (entry.antonyms.isNotEmpty) ...[
          SectionLabel(t.antonyms),
          PairWrap(entry.antonyms, onTapWord: onTapWord),
        ],
        if (entry.forms.isNotEmpty) ...[
          SectionLabel(t.forms),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final f in entry.forms)
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: f.en, style: EnglishText.body(c.ink, size: 16)),
                      TextSpan(text: '  ${f.label} · ${f.hi}', style: h.small(c.inkMuted)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text(
          t.attribution,
          style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: settings.hindiScale, size: 12.5),
        ),
      ],
    );
  }
}
