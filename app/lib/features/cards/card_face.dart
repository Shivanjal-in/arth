// How a flashcard looks. A card is an index card from a school notebook:
// faint ruled lines, a lac-red margin, the book's own cover ink along the
// top edge so a deck reads as that book's. Front and back are the two faces
// the review screen flips between; CardTile is the compact form the recap
// timeline lists.

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

/// The dye the book of this title is printed on (see book_cover.dart).
Color deckInk(String title) => coverInk(title);

final _devanagari = RegExp(r'[\u0900-\u097F]', unicode: true);

bool isHindiText(String s) => _devanagari.hasMatch(s);

IconData kindIcon(CardKind k) => switch (k) {
      CardKind.idea => Icons.lightbulb_outline_rounded,
      CardKind.quote => Icons.format_quote_rounded,
      CardKind.word => Icons.translate_rounded,
    };

String kindLabel(CardKind k, AppStrings t) => switch (k) {
      CardKind.idea => t.kindIdea,
      CardKind.quote => t.kindQuote,
      CardKind.word => t.kindWord,
    };

Color kindColor(CardKind k, ArthColors c) => switch (k) {
      CardKind.idea => c.marigold,
      CardKind.quote => c.accent,
      CardKind.word => c.inkMuted,
    };

/// Kind icon + label, and where in the book, on one line.
class CardMeta extends ConsumerWidget {
  const CardMeta({required this.card, super.key, this.showLocation = true});

  final Flashcard card;
  final bool showLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final color = kindColor(card.kind, c);
    final location = showLocation ? card.location : null;
    return Row(
      children: [
        Icon(kindIcon(card.kind), size: 16, color: color),
        const SizedBox(width: 6),
        Text(kindLabel(card.kind, t), style: uiLabel(hindi: t.isHindi, color: color)),
        if (location != null) ...[
          Text('  ·  ', style: EnglishText.label(c.inkMuted, size: 12)),
          Flexible(
            child: Text(location, style: EnglishText.label(c.inkMuted, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}

/// The paper: card colour, ruled lines, margin, ink edge, hard shadow.
class IndexCard extends StatelessWidget {
  const IndexCard({required this.ink, required this.child, super.key, this.padding = const EdgeInsets.fromLTRB(28, 22, 22, 22), this.elevated = true});

  final Color ink;
  final Widget child;
  final EdgeInsets padding;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // At night the card takes a wash of the book's colour; its edge stays ink
    // (or the book's colour), its shadow hard.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return HardShadow(
      depth: elevated ? 5 : 0,
      color: dark ? Color.lerp(c.card, ink, 0.10) : c.card,
      border: dark ? Color.lerp(c.ink, ink, 0.5) : c.ink,
      child: CustomPaint(
        painter: _RuledPaper(
          rule: dark ? Color.lerp(c.rule, ink, 0.30)!.withValues(alpha: 0.75) : c.rule,
          margin: c.accent,
          ink: ink,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _RuledPaper extends CustomPainter {
  _RuledPaper({required this.rule, required this.margin, required this.ink});

  final Color rule;
  final Color margin;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 6), Paint()..color = ink);
    final line = Paint()
      ..color = rule.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var y = 52.0; y < size.height - 8; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(
      const Offset(16, 6),
      Offset(16, size.height),
      Paint()
        ..color = margin.withValues(alpha: 0.35)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_RuledPaper old) => old.rule != rule || old.margin != margin || old.ink != ink;
}

/// Text in whichever script it's written in: Mukta for Hindi, the interface
/// font (Montserrat) for English.
TextStyle scriptStyle(String text, {required Color color, required double scale, double size = 16, bool italic = false, FontWeight? weight}) {
  if (isHindiText(text)) {
    final h = HindiText(scale).body(color).copyWith(fontSize: (size + 1) * scale);
    return weight == null ? h : h.copyWith(fontWeight: weight);
  }
  final e = italic ? EnglishText.italic(color, size: size) : EnglishText.body(color, size: size);
  return weight == null ? e : e.copyWith(fontWeight: weight);
}

/// A card's own words in the chosen [CardFont]; Hindi stays in Mukta, which
/// none of the three has letters for.
TextStyle cardStyle(
  String text,
  CardFont font, {
  required Color color,
  required double scale,
  double size = 16,
  bool italic = false,
  FontWeight? weight,
}) {
  if (isHindiText(text)) return scriptStyle(text, color: color, scale: scale, size: size, italic: italic, weight: weight);
  return switch (font) {
    CardFont.montserrat => GoogleFonts.montserrat(
        fontSize: size * 0.93,
        fontWeight: weight,
        fontStyle: italic ? FontStyle.italic : null,
        color: color,
        height: 1.45,
      ),
    // A calligraphic face: one weight, italic by nature, small on its body.
    CardFont.quintessential => GoogleFonts.quintessential(fontSize: size * 1.18, color: color, height: 1.35),
    // No italic cut; its character is in the upright.
    CardFont.bricolage => GoogleFonts.bricolageGrotesque(fontSize: size * 1.02, fontWeight: weight, color: color, height: 1.4),
  };
}

/// A card font's name, as it's shown in the picker.
String cardFontName(CardFont f) => switch (f) {
      CardFont.montserrat => 'Montserrat',
      CardFont.quintessential => 'Quintessential',
      CardFont.bricolage => 'Bricolage Grotesque',
    };

/// The face you see first.
class CardFront extends ConsumerWidget {
  const CardFront({required this.card, required this.ink, super.key, this.hint, this.font});

  final Flashcard card;
  final Color ink;

  /// "Tap to flip", when the card can be flipped.
  final String? hint;

  /// A deck's own font (a published recap); the reader's setting otherwise.
  final CardFont? font;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final t = ref.watch(stringsProvider);
    final f = font ?? ref.watch(settingsProvider).cardFont;
    final main = switch (card.kind) {
      CardKind.quote => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('“', style: EnglishText.title(c.accent.withValues(alpha: 0.5), size: 64).copyWith(height: 0.8)),
            Text(card.front, style: cardStyle(card.front, f, color: c.ink, scale: scale, size: 21, italic: true).copyWith(height: 1.5)),
          ],
        ),
      CardKind.word => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.front, style: cardStyle(card.front, f, color: c.ink, scale: scale, size: 38, weight: FontWeight.w700).copyWith(height: 1.1)),
            if (card.context != null) ...[
              const SizedBox(height: 18),
              _ContextLine(sentence: card.context!, word: card.front),
            ],
          ],
        ),
      CardKind.idea => Text(card.front, style: cardStyle(card.front, f, color: c.ink, scale: scale, size: 24, weight: FontWeight.w500).copyWith(height: 1.35)),
    };
    return IndexCard(
      ink: ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardMeta(card: card),
          Expanded(child: Center(child: SingleChildScrollView(child: SizedBox(width: double.infinity, child: main)))),
          if (hint != null)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_outlined, size: 15, color: c.inkMuted),
                  const SizedBox(width: 6),
                  Text(hint!, style: uiLabel(hindi: t.isHindi, color: c.inkMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The answer face.
class CardBack extends ConsumerWidget {
  const CardBack({required this.card, required this.ink, super.key, this.font});

  final Flashcard card;
  final Color ink;

  /// A deck's own font (a published recap); the reader's setting otherwise.
  final CardFont? font;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final t = ref.watch(stringsProvider);
    final f = font ?? ref.watch(settingsProvider).cardFont;
    return IndexCard(
      ink: ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.front,
                  style: EnglishText.label(c.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (card.back.isNotEmpty)
                        Text(card.back, style: cardStyle(card.back, f, color: c.ink, scale: scale, size: 22, weight: FontWeight.w500).copyWith(height: 1.5))
                      else if (card.note.isEmpty)
                        Text(t.emptyBack, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                      if (card.note.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        NoteBlock(note: card.note, font: f),
                      ],
                      if (card.context != null && card.kind != CardKind.quote) ...[
                        const SizedBox(height: 20),
                        Text(t.fromTheBook, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                        const SizedBox(height: 4),
                        Text(card.context!, style: EnglishText.italic(c.inkMuted, size: 14)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reader's own words: set off with a marigold rule, like a note in the
/// margin.
class NoteBlock extends ConsumerWidget {
  const NoteBlock({required this.note, super.key, this.maxLines, this.font});

  final String note;
  final int? maxLines;
  final CardFont? font;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: c.marigold, width: 3))),
      child: Text(
        note,
        style: cardStyle(note, font ?? ref.watch(settingsProvider).cardFont, color: c.ink, scale: scale, size: 15, italic: true),
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

/// The book's sentence with the card's word set in the accent colour.
class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.sentence, required this.word});

  final String sentence;
  final String word;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = EnglishText.italic(c.inkMuted, size: 15);
    final at = sentence.toLowerCase().indexOf(word.toLowerCase());
    if (at < 0) return Text(sentence, style: base);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: sentence.substring(0, at)),
          TextSpan(text: sentence.substring(at, at + word.length), style: base.copyWith(color: c.accent, fontWeight: FontWeight.w600)),
          TextSpan(text: sentence.substring(at + word.length)),
        ],
      ),
    );
  }
}

/// A card in a list: both sides at a glance.
class CardTile extends ConsumerWidget {
  const CardTile({required this.card, super.key, this.onTap, this.showLocation = false, this.font});

  final Flashcard card;
  final VoidCallback? onTap;
  final bool showLocation;

  /// A deck's own font (a published recap); the reader's setting otherwise.
  final CardFont? font;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final f = font ?? ref.watch(settingsProvider).cardFont;
    final front = switch (card.kind) {
      CardKind.quote => Text('“${card.front}”', style: cardStyle(card.front, f, color: c.ink, scale: scale, italic: true), maxLines: 4, overflow: TextOverflow.ellipsis),
      CardKind.word => Text(card.front, style: cardStyle(card.front, f, color: c.ink, scale: scale, size: 20, weight: FontWeight.w600)),
      CardKind.idea => Text(card.front, style: cardStyle(card.front, f, color: c.ink, scale: scale, weight: FontWeight.w600), maxLines: 3, overflow: TextOverflow.ellipsis),
    };
    return Pressable.card(
      depth: 4,
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardMeta(card: card, showLocation: showLocation),
              const SizedBox(height: 8),
              front,
              if (card.back.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(card.back, style: cardStyle(card.back, f, color: c.inkMuted, scale: scale, size: 15), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              if (card.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                NoteBlock(note: card.note, maxLines: 3, font: f),
              ],
            ],
          ),
        ),
    );
  }
}
