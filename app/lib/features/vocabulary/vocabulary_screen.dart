// Vocabulary: the words a reader has looked up while reading. For one book,
// the words met there — first the ones new to the reader (never looked up
// in an earlier book); for a lifetime, every word once, with the book it
// was first met in.

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/community/community_screen.dart' show ago;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final AutoDisposeFutureProvider<List<VocabWord>> lifetimeVocabularyProvider = FutureProvider.autoDispose<List<VocabWord>>(
  (ref) => ref.watch(localStoreProvider).lifetimeVocabulary(),
);

final AutoDisposeFutureProviderFamily<List<VocabWord>, int> bookVocabularyProvider = FutureProvider.autoDispose.family<List<VocabWord>, int>(
  (ref, bookId) => ref.watch(localStoreProvider).bookVocabulary(bookId),
);

/// `/vocabulary` (every book) or `/vocabulary?book=ID&title=…` (one book).
class VocabularyScreen extends ConsumerWidget {
  const VocabularyScreen({super.key, this.bookId, this.bookTitle});

  final int? bookId;
  final String? bookTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final id = bookId;
    return Scaffold(
      appBar: AppBar(
        title: Text(id == null ? t.vocabulary : (bookTitle ?? t.wordsFromBook), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (id != null)
            TextButton(
              onPressed: () => context.push('/vocabulary'),
              child: Text(t.seeAllWords, style: uiLabel(hindi: t.isHindi, color: c.accent)),
            ),
        ],
      ),
      body: id == null ? const LifetimeVocabulary() : _BookVocabulary(bookId: id),
    );
  }
}

/// Every word, once. Also the Cards tab's Vocabulary page.
class LifetimeVocabulary extends ConsumerStatefulWidget {
  const LifetimeVocabulary({super.key});

  @override
  ConsumerState<LifetimeVocabulary> createState() => _LifetimeVocabularyState();
}

class _LifetimeVocabularyState extends ConsumerState<LifetimeVocabulary> {
  final _search = TextEditingController();
  bool _az = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final words = ref.watch(lifetimeVocabularyProvider);
    return words.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(t.somethingWrong)),
      data: (all) {
        if (all.isEmpty) return _Empty(text: t.vocabularyEmpty);
        final q = _search.text.trim().toLowerCase();
        final shown = [for (final w in all) if (q.isEmpty || w.lemma.toLowerCase().contains(q) || w.meaning.contains(q)) w];
        if (_az) shown.sort((a, b) => a.lemma.toLowerCase().compareTo(b.lemma.toLowerCase()));
        final books = {for (final w in all) w.bookId}.length;
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(lifetimeVocabularyProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Text(t.lifetimeWords(all.length, books), style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: EnglishText.body(c.ink, size: 16),
                decoration: InputDecoration(
                  hintText: t.searchWords,
                  prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (az, label) in [(false, t.sortRecent), (true, t.sortAz)])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _az == az,
                        showCheckmark: false,
                        onSelected: (_) {
                          Haptics.choose();
                          setState(() => _az = az);
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              for (final w in shown)
                _WordRow(
                  word: w,
                  meta: [
                    t.firstMetIn(w.bookTitle),
                    if (w.books > 1) t.inBooks(w.books),
                    t.lookedUpTimes(w.lookups),
                  ],
                  trailing: ago(w.firstAt, t),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BookVocabulary extends ConsumerStatefulWidget {
  const _BookVocabulary({required this.bookId});

  final int bookId;

  @override
  ConsumerState<_BookVocabulary> createState() => _BookVocabularyState();
}

class _BookVocabularyState extends ConsumerState<_BookVocabulary> {
  bool _onlyNew = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final words = ref.watch(bookVocabularyProvider(widget.bookId));
    return words.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(t.somethingWrong)),
      data: (all) {
        if (all.isEmpty) return _Empty(text: t.bookVocabularyEmpty);
        final fresh = [for (final w in all) if (w.isNew) w];
        final shown = _onlyNew ? fresh : all;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text(t.bookWordsSummary(all.length, fresh.length), style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (onlyNew, label) in [(true, t.newToYou(fresh.length)), (false, t.allWords(all.length))])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _onlyNew == onlyNew,
                      showCheckmark: false,
                      onSelected: (_) {
                        Haptics.choose();
                        setState(() => _onlyNew = onlyNew);
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final w in shown)
              _WordRow(
                word: w,
                meta: [if (!w.isNew) t.metBefore, t.lookedUpTimes(w.lookups)],
                trailing: ago(w.firstAt, t),
                bookId: widget.bookId,
              ),
          ],
        );
      },
    );
  }
}

class _WordRow extends ConsumerWidget {
  const _WordRow({required this.word, required this.meta, required this.trailing, this.bookId});

  final VocabWord word;
  final List<String> meta;
  final String trailing;

  /// Set on a book's list, so holding removes only that meeting.
  final int? bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    return InkWell(
      onTap: () => context.push('/word/${Uri.encodeComponent(word.lemma)}'),
      onLongPress: () => _forget(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rule))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(word.lemma, style: EnglishText.word(c.ink, size: 19))),
                Text(trailing, style: EnglishText.label(c.inkMuted, size: 12)),
              ],
            ),
            if (word.meaning.isNotEmpty) Text(word.meaning, style: HindiText(scale).meaning(c.ink)),
            const SizedBox(height: 2),
            Text(meta.join('  ·  '), style: EnglishText.label(c.inkMuted, size: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final scale = ref.read(settingsProvider).hindiScale;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(t.removeFromVocabulary, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
        content: Text(word.lemma, style: EnglishText.body(c.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.no)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(localStoreProvider).removeVocabulary(word.lemma, bookId: bookId);
    ref
      ..invalidate(lifetimeVocabularyProvider)
      ..invalidate(bookVocabularyProvider);
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, size: 44, color: c.rule),
            const SizedBox(height: 12),
            Text(text, style: uiBody(hindi: t.isHindi, color: c.inkMuted), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
