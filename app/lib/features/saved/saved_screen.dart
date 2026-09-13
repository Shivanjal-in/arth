import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final h = HindiText(scale);
    final t = ref.watch(stringsProvider);
    final saved = ref.watch(savedWordsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.savedTitle)),
      body: saved.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(t.somethingWrong, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale))),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    t.savedEmpty,
                    style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final w = list[i];
                  return Dismissible(
                    key: ValueKey(w.lemma),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      color: c.accent,
                      child: Icon(Icons.delete_outline_rounded, color: c.paper),
                    ),
                    onDismissed: (_) => ref.read(savedWordsProvider.notifier).unsave(w.lemma),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      title: Text(w.lemma, style: EnglishText.word(c.ink, size: 20)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.meaning, style: h.meaning(c.ink)),
                          if (w.sentence != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                w.sentence!,
                                style: EnglishText.italic(c.inkMuted, size: 13.5),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (w.bookTitle != null)
                            Text(w.bookTitle!, style: EnglishText.caps(c.inkMuted, size: 10)),
                        ],
                      ),
                      onTap: () => context.push('/word/${w.lemma}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
