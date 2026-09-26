// A book's recap: its cards as a timeline in reading order, grouped by
// chapter or page, under a header in the book's cover ink. Built for the
// glance after finishing — the story of the book in the reader's own notes —
// with replay (every card, in order) and practice (flip and rate) on top.

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/card_editor.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/cards/deck_pdf.dart';
import 'package:arth/features/community/publish_sheet.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:arth/features/library/library_screen.dart';
import 'package:arth/features/settings/settings_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The route for a deck. A removed book's deck is addressed by title.
String deckRoute(DeckRef deck) => Uri(
      path: '/deck',
      queryParameters: {
        if (deck.bookId != null) 'book': '${deck.bookId}',
        if (deck.bookTitle != null) 'title': deck.bookTitle,
      },
    ).toString();

DeckRef deckRefFrom(Map<String, String> q) => (bookId: int.tryParse(q['book'] ?? ''), bookTitle: q['title']);

class DeckScreen extends ConsumerStatefulWidget {
  const DeckScreen({required this.deck, super.key});

  final DeckRef deck;

  @override
  ConsumerState<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends ConsumerState<DeckScreen> {
  CardKind? _filter;

  /// Two ways to share a recap: a PDF for anyone, or the community.
  Future<void> _share(BuildContext button, {required String title, required String? bookKey, required List<Flashcard> cards}) async {
    final t = ref.read(stringsProvider);
    final box = button.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final c = ctx.colors;
        final scale = ref.read(settingsProvider).hindiScale;
        Widget option(String value, IconData icon, String label, String hint) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Icon(icon, color: c.accent),
              title: Text(label, style: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 16)),
              subtitle: Text(hint, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13.5)),
              onTap: () => Navigator.pop(ctx, value),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pick how the cards look, then share them that way.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.cardFont, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                      const SizedBox(height: 8),
                      const CardFontPicker(),
                    ],
                  ),
                ),
                option('pdf', Icons.picture_as_pdf_outlined, t.exportPdf, t.exportPdfHint),
                option('community', Icons.public_rounded, t.shareToCommunity, t.shareToCommunityHint),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    Haptics.choose();
    if (choice == 'pdf') {
      await exportDeckPdf(context, ref, bookTitle: title, cards: cards, origin: origin);
    } else {
      await shareRecap(context, ref, bookTitle: title, bookKey: bookKey, cards: cards);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final books = ref.watch(libraryProvider).valueOrNull ?? const <Book>[];
    final book = books.where((b) => b.id == widget.deck.bookId).firstOrNull;
    final title = book?.title ?? widget.deck.bookTitle ?? '';
    final ink = deckInk(title);
    final cards = ref.watch(flashcardsProvider(widget.deck)).valueOrNull;
    final shown = cards?.where((card) => _filter == null || card.kind == _filter).toList() ?? const <Flashcard>[];

    // Consecutive cards from the same place share one timeline stop.
    final groups = <(String?, int?, int?, List<Flashcard>)>[];
    for (final card in shown) {
      final last = groups.lastOrNull;
      if (last != null && last.$1 == card.location && last.$2 == card.page) {
        last.$4.add(card);
      } else {
        groups.add((card.location, card.page, card.block, [card]));
      }
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        icon: const Icon(Icons.add_rounded),
        label: Text(t.newCard, style: uiLabel(hindi: t.isHindi, color: c.onAccent, scale: scale)),
        onPressed: () => showCardEditor(
          context,
          draft: CardDraft(kind: CardKind.idea, bookId: widget.deck.bookId, bookTitle: title),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 250,
            backgroundColor: ink,
            foregroundColor: Colors.white,
            title: Text(t.recap, style: EnglishText.heading(Colors.white, size: 18)),
            actions: [
              if (cards != null && cards.isNotEmpty)
                Builder(
                  builder: (button) => IconButton(
                    tooltip: t.share,
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => _share(button, title: title, bookKey: book?.contentKey ?? cards.first.bookKey, cards: cards),
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _Header(title: title, ink: ink, book: book, cards: cards ?? const []),
            ),
          ),
          if (cards != null && cards.isNotEmpty) ...[
            SliverToBoxAdapter(child: _Actions(deck: widget.deck, cards: cards, ink: ink)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final k in [null, ...CardKind.values])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(k == null ? t.all : kindLabel(k, t), style: uiLabel(hindi: t.isHindi, color: _filter == k ? c.onAccent : c.ink, scale: scale)),
                          avatar: k == null ? null : Icon(kindIcon(k), size: 16, color: _filter == k ? c.onAccent : kindColor(k, c)),
                          selected: _filter == k,
                          showCheckmark: false,
                          selectedColor: c.ink,
                          backgroundColor: c.card,
                          side: BorderSide(color: _filter == k ? c.ink : c.rule),
                          onSelected: (_) {
                            if (_filter != k) Haptics.choose();
                            setState(() => _filter = k);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (cards == null)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (cards.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(t.cardsEmptyBody, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale), textAlign: TextAlign.center),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
              sliver: SliverList.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final (location, page, block, group) = groups[i];
                  return _TimelineStop(
                    location: location,
                    ink: ink,
                    first: i == 0,
                    last: i == groups.length - 1,
                    onOpen: book == null || page == null ? null : () => context.push(bookRoute(book, page: page, block: block)),
                    children: [
                      for (final card in group)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CardTile(card: card, onTap: () => showCardEditor(context, existing: card)),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.title, required this.ink, required this.book, required this.cards});

  final String title;
  final Color ink;
  final Book? book;
  final List<Flashcard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final onInk = Colors.white.withValues(alpha: 0.92);
    final soft = Colors.white.withValues(alpha: 0.72);
    final fraction = book?.readFraction;
    final counts = {for (final k in CardKind.values) k: cards.where((c) => c.kind == k).length};
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ink, Color.lerp(ink, Colors.black, 0.35)!],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: BlockPrintTexture(title: title, cell: 58, opacity: 0.065)),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(title, style: EnglishText.title(onInk, size: 30), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (book?.finishedAt != null) ...[
                        Icon(Icons.check_circle_rounded, size: 16, color: soft),
                        const SizedBox(width: 6),
                        Text(t.finishedReading, style: uiLabel(hindi: t.isHindi, color: soft, scale: scale)),
                      ] else if (fraction != null)
                        Text(t.readPercent((fraction * 100).round()), style: uiLabel(hindi: t.isHindi, color: soft, scale: scale))
                      else if (book == null)
                        Text(t.bookRemoved, style: uiLabel(hindi: t.isHindi, color: soft, scale: scale)),
                    ],
                  ),
                  if (fraction != null && book?.finishedAt == null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: fraction, minHeight: 3, color: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.2)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      for (final k in CardKind.values)
                        if (counts[k]! > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(kindIcon(k), size: 16, color: soft),
                              const SizedBox(width: 6),
                              Text(t.kindCount(CardKindName.values.byName(k.name), counts[k]!), style: uiLabel(hindi: t.isHindi, color: onInk, scale: scale)),
                            ],
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.deck, required this.cards, required this.ink});

  final DeckRef deck;
  final List<Flashcard> cards;
  final Color ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final due = cards.where((card) => card.isDue).length;
    Widget action({required IconData icon, required String title, required String hint, required String mode, required bool primary}) => Expanded(
          child: Material(
            color: primary ? c.ink : c.card,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push(reviewRoute(deck, mode: mode)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: primary ? null : Border.all(color: c.rule)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: primary ? c.marigold : c.accent),
                    const SizedBox(height: 10),
                    Text(title, style: uiLabel(hindi: t.isHindi, color: primary ? c.paper : c.ink, scale: scale).copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(hint, style: uiBody(hindi: t.isHindi, color: primary ? c.paper.withValues(alpha: 0.7) : c.inkMuted, scale: scale, size: 12.5)),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            action(icon: Icons.auto_stories_outlined, title: t.replayInOrder, hint: t.replayInOrderHint, mode: 'replay', primary: true),
            const SizedBox(width: 12),
            action(
              icon: Icons.style_outlined,
              title: t.practice,
              hint: due > 0 ? t.dueCount(due) : t.practiceHint,
              mode: 'practice',
              primary: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// One place in the book: a dot on the timeline's line, the place's name,
/// and the cards made there.
class _TimelineStop extends ConsumerWidget {
  const _TimelineStop({
    required this.location,
    required this.ink,
    required this.first,
    required this.last,
    required this.children,
    this.onOpen,
  });

  final String? location;
  final Color ink;
  final bool first;
  final bool last;
  final List<Widget> children;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(width: 2, height: 10, color: first ? Colors.transparent : c.rule),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: c.paper, shape: BoxShape.circle, border: Border.all(color: ink, width: 3)),
                ),
                Expanded(child: Container(width: 2, color: last ? Colors.transparent : c.rule)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          location ?? '—',
                          style: EnglishText.label(c.inkMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onOpen != null)
                        IconButton(
                          tooltip: t.openInBook,
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          icon: Icon(Icons.open_in_new_rounded, color: c.inkMuted),
                          onPressed: onOpen,
                        ),
                    ],
                  ),
                ),
                ...children,
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The review route for a deck; [mode] is `replay` or `practice`.
String reviewRoute(DeckRef deck, {required String mode}) => Uri(
      path: '/deck/review',
      queryParameters: {
        if (deck.bookId != null) 'book': '${deck.bookId}',
        if (deck.bookTitle != null) 'title': deck.bookTitle,
        'mode': mode,
      },
    ).toString();
