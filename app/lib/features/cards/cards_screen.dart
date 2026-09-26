// The Cards tab: a deck per book (each a little stack of index cards in the
// book's cover ink, with how many are waiting for review), and the saved
// words list.

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/cards/deck_screen.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:arth/features/saved/saved_words_list.dart';
import 'package:arth/features/vocabulary/vocabulary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.cardsTitle, style: uiTitle(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 26)),
          toolbarHeight: 64,
          bottom: TabBar(
            labelStyle: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 15),
            unselectedLabelColor: c.inkMuted,
            labelColor: c.ink,
            indicatorColor: c.accent,
            dividerColor: c.rule,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [Tab(text: t.decks), Tab(text: t.words), Tab(text: t.vocabulary)],
          ),
        ),
        body: const TabBarView(children: [_Decks(), SavedWordsList(), LifetimeVocabulary()]),
      ),
    );
  }
}

class _Decks extends ConsumerWidget {
  const _Decks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final decks = ref.watch(decksProvider);
    return decks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(t.somethingWrong, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale))),
      data: (list) => list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.style_outlined, size: 56, color: c.rule),
                    const SizedBox(height: 16),
                    Text(t.cardsEmptyTitle, style: uiHeadline(hindi: t.isHindi, color: c.ink, scale: scale)),
                    const SizedBox(height: 8),
                    Text(t.cardsEmptyBody, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 22),
              itemBuilder: (_, i) => DeckTile(deck: list[i]),
            ),
    );
  }
}

/// A deck as a small stack of cards.
class DeckTile extends ConsumerWidget {
  const DeckTile({required this.deck, super.key});

  final DeckSummary deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final ink = deckInk(deck.bookTitle);
    final ref0 = (bookId: deck.bookId, bookTitle: deck.bookTitle);
    Widget sheet(double inset, double drop, double alpha) => Positioned(
          left: inset,
          right: inset,
          top: drop,
          bottom: -drop,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(c.card, ink, alpha),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.rule),
            ),
          ),
        );
    return Pressable(
      onTap: () => context.push(deckRoute(ref0)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (deck.count > 2) sheet(18, 12, 0.10),
          if (deck.count > 1) sheet(9, 6, 0.05),
          IndexCard(
            ink: ink,
            padding: const EdgeInsets.fromLTRB(28, 22, 18, 18),
            child: Row(
              children: [
                BookCover(title: deck.bookTitle, width: 42, elevation: 0.6),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deck.bookTitle, style: EnglishText.word(c.ink, size: 20), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      // The title gets the full width; counts sit under it.
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(t.cardCount(deck.count), style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                          if (deck.due > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: c.marigold.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                              child: Text(t.dueCount(deck.due), style: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 12)),
                            ),
                          if (deck.bookId == null)
                            Text(t.bookRemoved, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: c.inkMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
