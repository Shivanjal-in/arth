// The tooltip layer shared by every reader (PDF, scanned image).
//
// A reader supplies two coordinate mappings and gets back: the overlay
// widgets to place inside its content coordinate space (word highlight +
// the LayerLink target), and the follower to mount in an OverlayPortal.

import 'package:arth/app/theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final t = tooltip;
    if (t == null) return const SizedBox.shrink();
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
        ),
      SentenceTooltipState() => SentenceTooltip(state: t, onTapWord: onSuggestion),
    };

    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: placement.above ? Alignment.topCenter : Alignment.bottomCenter,
        followerAnchor: placement.above ? Alignment.bottomCenter : Alignment.topCenter,
        offset: Offset(dx, 0),
        child: TooltipCard(
          width: placement.width,
          maxHeight: placement.maxHeight,
          above: placement.above,
          child: child,
        ),
      ),
    );
  }
}
