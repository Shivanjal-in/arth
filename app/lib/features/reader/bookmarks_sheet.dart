// A book's bookmarks, in reading order: tap to jump, trash to remove. And
// the sheet that greets the reader at the end of a book, pointing them at
// the recap their cards make.

import 'dart:async';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/card_editor.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/cards/deck_screen.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Future<void> showBookmarksSheet(BuildContext context, {required int bookId, required void Function(Bookmark b) onJump}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => _BookmarksList(
          bookId: bookId,
          scroll: scroll,
          onJump: (b) {
            Navigator.pop(ctx);
            onJump(b);
          },
        ),
      ),
    );

class _BookmarksList extends ConsumerWidget {
  const _BookmarksList({required this.bookId, required this.scroll, required this.onJump});

  final int bookId;
  final ScrollController scroll;
  final void Function(Bookmark b) onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final items = ref.watch(bookmarksProvider(bookId)).valueOrNull ?? const <Bookmark>[];
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      itemCount: items.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.bookmarks, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
                if (items.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(t.bookmarksEmpty, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                ],
              ],
            ),
          );
        }
        final b = items[i - 1];
        return ListTile(
          onTap: () => onJump(b),
          leading: Icon(Icons.bookmark_rounded, color: c.accent),
          title: Text(b.label ?? '', style: EnglishText.label(c.ink, size: 14)),
          subtitle: b.excerpt == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(b.excerpt!, style: EnglishText.italic(c.inkMuted, size: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
          trailing: IconButton(
            tooltip: t.removeBookmark,
            icon: Icon(Icons.delete_outline_rounded, color: c.inkMuted),
            onPressed: () => unawaited(ref.read(bookmarksProvider(bookId).notifier).remove(b.id)),
          ),
        );
      },
    );
  }
}

/// Shown once, when the reader first reaches the end of [book].
Future<void> showFinishedSheet(BuildContext context, WidgetRef ref, Book book) async {
  final deck = (bookId: book.id, bookTitle: book.title);
  final cards = await ref.read(flashcardsProvider(deck).future);
  if (!context.mounted) return;
  unawaited(Haptics.finish());
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (_) => _FinishedSheet(book: book, cardCount: cards.length, deck: deck, host: context),
  );
}

class _FinishedSheet extends ConsumerWidget {
  const _FinishedSheet({required this.book, required this.cardCount, required this.deck, required this.host});

  final Book book;
  final int cardCount;
  final DeckRef deck;

  /// The reader's context: the sheet's own is gone once it closes.
  final BuildContext host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final ink = deckInk(book.title);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    BookCover(title: book.title, width: 48),
                    // The check lands a beat after the sheet: done.
                    Positioned(
                      right: -8,
                      bottom: -6,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Motion.of(context, const Duration(milliseconds: 520)),
                        curve: const Interval(0.35, 1, curve: Curves.elasticOut),
                        builder: (_, v, child) => Transform.scale(scale: v, child: child),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: c.marigold, shape: BoxShape.circle, border: Border.all(color: c.card, width: 2.5)),
                          child: Icon(Icons.check_rounded, size: 16, color: ink),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(t.finishedTitle(book.title), style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale))),
              ],
            ),
            const SizedBox(height: 14),
            Text(t.finishedBody(cardCount), style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (!host.mounted) return;
                  if (cardCount == 0) {
                    unawaited(showCardEditor(host, draft: CardDraft(kind: CardKind.idea, bookId: book.id, bookTitle: book.title)));
                  } else {
                    unawaited(host.push(deckRoute(deck)));
                  }
                },
                child: Text(cardCount == 0 ? t.addNote : t.seeRecap),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                child: Text(t.later),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
