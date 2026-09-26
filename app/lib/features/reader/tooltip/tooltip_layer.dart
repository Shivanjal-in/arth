// The tooltip layer shared by every reader (PDF, scanned image).
//
// A reader supplies two coordinate mappings and gets back: the overlay
// widgets to place inside its content coordinate space (word highlight +
// the LayerLink target), and the follower to mount in an OverlayPortal.

import 'package:arth/app/feel.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/card_editor.dart';
import 'package:arth/features/reader/highlights/highlight_bar.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:arth/features/reader/tooltip/sentence_tooltip.dart';
import 'package:arth/features/reader/tooltip/tooltip_card.dart';
import 'package:arth/features/reader/tooltip/tooltip_placement.dart';
import 'package:arth/features/reader/tooltip/word_tooltip.dart';
import 'package:flutter/material.dart';

/// Highlight rects and the LayerLink target, in the reader's local space.
List<Widget> tooltipOverlays({
  required BuildContext context,
  required ReaderTooltip? tooltip,
  required LayerLink link,
  required Rect Function(Rect documentRect) toLocal,
}) {
  final t = tooltip;
  if (t == null) return const [];
  final c = context.colors;
  final highlights = t is WordTooltipState ? (t.highlight ?? [t.anchor]) : const <Rect>[];
  return [
    for (final r in highlights)
      Positioned.fromRect(
        rect: toLocal(r).inflate(1.5),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(color: c.highlight, borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
    Positioned.fromRect(
      rect: toLocal(t.anchor),
      child: IgnorePointer(child: CompositedTransformTarget(link: link, child: const SizedBox.expand())),
    ),
  ];
}

/// What a reader does with the highlighter. Readers without one (scans)
/// pass null. A reader that never shows the bar (the PDF reader, which
/// highlights from the translation card) leaves the bar callbacks null.
class HighlightActions {
  const HighlightActions({this.onColor, this.onRemove, this.onTranslate, this.onSentenceColor});

  final void Function(HighlightBarState s, HighlightColor color)? onColor;
  final void Function(HighlightBarState s)? onRemove;
  final void Function(HighlightBarState s)? onTranslate;

  /// Highlight the sentence a translation card is showing, when the reader
  /// knows where that sentence is.
  final void Function(SentenceTooltipState s, HighlightColor color)? onSentenceColor;
}

/// The tooltip card, following the LayerLink target; flips above/below and
/// clamps to the screen using the anchor's on-screen rect.
class TooltipFollower extends StatelessWidget {
  const TooltipFollower({
    required this.tooltip,
    required this.link,
    required this.anchorOnScreen,
    required this.onShowDetails,
    required this.onSuggestion,
    required this.onTranslateSentence,
    super.key,
    this.bookId,
    this.bookTitle,
    this.highlightActions,
    this.onMakeCard,
  });

  final ReaderTooltip? tooltip;
  final LayerLink link;

  /// The anchor in screen coordinates (for placement only; the follower
  /// itself tracks the target).
  final Rect anchorOnScreen;
  final int? bookId;
  final String? bookTitle;
  final void Function(WordTooltipState) onShowDetails;
  final ValueChanged<String> onSuggestion;
  final void Function(WordTooltipState) onTranslateSentence;
  final HighlightActions? highlightActions;

  /// Turn what the card shows into a flashcard; the reader adds where in
  /// the book it is and opens the editor.
  final void Function(CardDraft draft)? onMakeCard;

  @override
  Widget build(BuildContext context) {
    final t = tooltip;
    if (t == null) return const SizedBox.shrink();
    final actions = highlightActions;
    if (t is HighlightBarState && actions?.onColor == null) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final usable = Size(screen.width, screen.height - padding.bottom);
    // Place for the worst case (the height cap): a measured height would already
    // be clipped by the previous placement and shrink on every rebuild.
    final placement = placeTooltip(
      anchor: anchorOnScreen,
      tooltipSize: Size(340, usable.height * 0.45),
      screen: usable,
    );
    final dx = placement.offset.dx + placement.width / 2 - anchorOnScreen.center.dx;

    final child = switch (t) {
      WordTooltipState() => WordTooltip(
          state: t,
          bookId: bookId,
          bookTitle: bookTitle,
          onShowDetails: () => onShowDetails(t),
          onSuggestion: onSuggestion,
          onTranslateSentence: () => onTranslateSentence(t),
          onMakeCard: onMakeCard == null ? null : () => onMakeCard!(wordDraft(t)),
        ),
      SentenceTooltipState() => SentenceTooltip(
          state: t,
          onTapWord: onSuggestion,
          onHighlight: actions?.onSentenceColor == null ? null : (color) => actions!.onSentenceColor!(t, color),
          onMakeCard: onMakeCard == null
              ? null
              : () => onMakeCard!(CardDraft(kind: CardKind.quote, front: t.text, back: t.hindi ?? '', context: t.text)),
        ),
      HighlightBarState() => HighlightBar(
          selected: t.existing?.color,
          onColor: (color) => actions!.onColor!(t, color),
          onTranslate: () => actions!.onTranslate?.call(t),
          onRemove: t.existing == null ? null : () => actions!.onRemove?.call(t),
        ),
    };

    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: placement.above ? Alignment.topCenter : Alignment.bottomCenter,
        followerAnchor: placement.above ? Alignment.bottomCenter : Alignment.topCenter,
        offset: Offset(dx, 0),
        // Rises out of the word (or drops from it) when a new card opens;
        // content arriving later (the in-context meaning) doesn't replay it.
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_identity(t)),
          tween: Tween(begin: 0, end: 1),
          duration: Motion.of(context, Motion.quick),
          curve: Motion.arrive,
          builder: (_, v, card) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, (placement.above ? 6 : -6) * (1 - v)),
              child: Transform.scale(
                scale: 0.96 + 0.04 * v,
                alignment: placement.above ? Alignment.bottomCenter : Alignment.topCenter,
                child: card,
              ),
            ),
          ),
          child: TooltipCard(
            width: placement.width,
            maxHeight: placement.maxHeight,
            above: placement.above,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A word card from a looked-up word: the word, its meaning in this sentence
/// (or its first sense), and the sentence.
CardDraft wordDraft(WordTooltipState s) {
  final outcome = s.outcome;
  if (outcome is! LookupFound) return CardDraft(kind: CardKind.word, front: s.token, context: s.sentence);
  return CardDraft(
    kind: CardKind.word,
    front: outcome.entry.word,
    back: s.context?.meaning ?? outcome.entry.senses.firstOrNull?.meaning ?? '',
    context: s.sentence,
  );
}

/// What makes a tooltip a new one, rather than the same one updating.
Object _identity(ReaderTooltip t) => switch (t) {
      WordTooltipState() => ('word', t.page, t.key, t.sentence),
      SentenceTooltipState() => ('sentence', t.page, t.text),
      HighlightBarState() => ('bar', t.page, t.text),
    };
