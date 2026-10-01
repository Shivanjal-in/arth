// App-bar pieces every reader shares: the bookmark ribbon for the current
// place, and the overflow menu (highlights, bookmarks, a note card, the
// book's cards, and whether a selection may call the model).

import 'dart:async';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/features/account/ai_lookup_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookmarkButton extends ConsumerWidget {
  const BookmarkButton({required this.marked, required this.onPressed, super.key});

  /// Whether the current place already has a bookmark.
  final bool marked;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    return IconButton(
      tooltip: marked ? t.removeBookmark : t.addBookmark,
      onPressed: onPressed == null
          ? null
          : () {
              Haptics.commit();
              onPressed!();
            },
      icon: AnimatedSwitcher(
        duration: Motion.of(context, Motion.quick),
        // The ribbon drops into place when marked.
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, -0.35), end: Offset.zero).chain(CurveTween(curve: Motion.arrive)).animate(a), child: child),
        ),
        child: marked
            ? Icon(Icons.bookmark_rounded, key: const ValueKey(true), color: c.accent)
            : const Icon(Icons.bookmark_border_rounded, key: ValueKey(false)),
      ),
    );
  }
}

enum _MenuItem { highlights, bookmarks, note, cards, words, aiLookup }

class ReaderMoreMenu extends ConsumerWidget {
  const ReaderMoreMenu({required this.onNote, required this.onCards, super.key, this.onHighlights, this.onBookmarks, this.onWords});

  final VoidCallback? onHighlights;
  final VoidCallback? onBookmarks;
  final VoidCallback onNote;
  final VoidCallback onCards;

  /// The words looked up in this book (vocabulary).
  final VoidCallback? onWords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final scale = settings.hindiScale;
    final ai = settings.aiLookup;
    PopupMenuItem<_MenuItem> item(_MenuItem value, IconData icon, String label, {bool checked = false}) => PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 20, color: checked ? c.accent : c.inkMuted),
              const SizedBox(width: 14),
              Text(label, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 15)),
              if (checked) ...[
                const SizedBox(width: 16),
                Icon(Icons.check_rounded, size: 18, color: c.accent),
              ],
            ],
          ),
        );
    return PopupMenuButton<_MenuItem>(
      tooltip: t.more,
      icon: const Icon(Icons.more_vert_rounded),
      color: c.card,
      onSelected: (v) {
        switch (v) {
          case _MenuItem.highlights:
            onHighlights?.call();
          case _MenuItem.bookmarks:
            onBookmarks?.call();
          case _MenuItem.note:
            onNote();
          case _MenuItem.cards:
            onCards();
          case _MenuItem.words:
            onWords?.call();
          case _MenuItem.aiLookup:
            unawaited(setAiLookup(context, ref, on: !ai));
        }
      },
      itemBuilder: (_) => [
        item(_MenuItem.note, Icons.edit_note_rounded, t.addNote),
        item(_MenuItem.cards, Icons.style_outlined, t.cardsForBook),
        if (onWords != null) item(_MenuItem.words, Icons.spellcheck_rounded, t.wordsFromBook),
        if (onBookmarks != null) item(_MenuItem.bookmarks, Icons.bookmarks_outlined, t.bookmarks),
        if (onHighlights != null) item(_MenuItem.highlights, Icons.border_color_outlined, t.highlights),
        const PopupMenuDivider(),
        item(_MenuItem.aiLookup, Icons.auto_awesome_outlined, t.aiLookup, checked: ai),
      ],
    );
  }
}
