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

/// AI lookup on/off, right in the reader's app bar. Lit when on.
class AiLookupButton extends ConsumerWidget {
  const AiLookupButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final on = ref.watch(settingsProvider.select((s) => s.aiLookup));
    return IconButton(
      tooltip: t.aiLookup,
      isSelected: on,
      icon: Icon(Icons.auto_awesome_outlined, color: c.inkMuted),
      selectedIcon: Icon(Icons.auto_awesome_rounded, color: c.accent),
      onPressed: () {
        Haptics.choose();
        unawaited(setAiLookup(context, ref, on: !on));
      },
    );
  }
}

enum _MenuItem { highlights, bookmarks, note, cards, words, mode }

class ReaderMoreMenu extends ConsumerWidget {
  const ReaderMoreMenu({required this.onNote, required this.onCards, super.key, this.onHighlights, this.onBookmarks, this.onWords, this.onToggleMode});

  final VoidCallback? onHighlights;
  final VoidCallback? onBookmarks;
  final VoidCallback onNote;
  final VoidCallback onCards;

  /// The words looked up in this book (vocabulary).
  final VoidCallback? onWords;

  /// Switch between reading mode (page turns) and scrolling mode; null where
  /// a reader has only one.
  final VoidCallback? onToggleMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final scale = settings.hindiScale;
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
          case _MenuItem.mode:
            onToggleMode?.call();
        }
      },
      itemBuilder: (_) => [
        if (onToggleMode != null)
          settings.bookPages
              ? item(_MenuItem.mode, Icons.swap_vert_rounded, t.scrollingMode)
              : item(_MenuItem.mode, Icons.auto_stories_outlined, t.readingMode),
        item(_MenuItem.note, Icons.edit_note_rounded, t.addNote),
        item(_MenuItem.cards, Icons.style_outlined, t.cardsForBook),
        if (onWords != null) item(_MenuItem.words, Icons.spellcheck_rounded, t.wordsFromBook),
        if (onBookmarks != null) item(_MenuItem.bookmarks, Icons.bookmarks_outlined, t.bookmarks),
        if (onHighlights != null) item(_MenuItem.highlights, Icons.border_color_outlined, t.highlights),
      ],
    );
  }
}
