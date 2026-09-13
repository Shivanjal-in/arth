import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/features/dictionary/entry_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final AutoDisposeFutureProviderFamily<LookupOutcome, String> wordLookupProvider =
    FutureProvider.autoDispose.family<LookupOutcome, String>(
  (ref, word) => ref.watch(dictionaryRepoProvider).lookupWord(word),
);

class WordScreen extends ConsumerWidget {
  const WordScreen({required this.word, super.key});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final t = ref.watch(stringsProvider);
    final body = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale);
    final outcome = ref.watch(wordLookupProvider(word));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: Text(t.back, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
        titleSpacing: 0,
      ),
      body: outcome.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(t.somethingWrong, style: body)),
        data: (o) => switch (o) {
          LookupFound(:final entry) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: EntryDetails(entry: entry, onTapWord: (w) => context.push('/word/$w')),
            ),
          LookupMissing(:final suggestions, :final offline) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(word, style: EnglishText.word(c.ink, size: 30)),
                  const SizedBox(height: 8),
                  Text(offline ? t.offline : t.notFound, style: body),
                  if (suggestions.isNotEmpty) ...[
                    SectionLabel(t.didYouMean),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in suggestions)
                          ActionChip(label: Text(s), onPressed: () => context.pushReplacement('/word/$s')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        },
      ),
    );
  }
}
