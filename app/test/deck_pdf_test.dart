import 'dart:convert';
import 'dart:io';

import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/deck_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  testWidgets('a deck becomes a multi-page PDF, one picture per card', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final made = DateTime(2026, 9, 2);
    final cards = [
      for (var i = 0; i < 14; i++)
        Flashcard(
          id: '$i',
          kind: CardKind.values[i % 3],
          front: i.isEven ? 'solitude' : 'एकांत में रहना',
          back: 'एकांत — being alone, often by choice',
          note: i % 4 == 0 ? 'The keeper chooses it; the town calls it loneliness. ' * 3 : '',
          context: 'He had lived in solitude for eleven years.',
          location: 'Chapter ${i + 1}',
          bookTitle: 'The Lighthouse Keeper',
          createdAt: made,
          updatedAt: made,
        ),
    ];
    final bytes = await tester.runAsync(
      () => buildDeckPdf(bookTitle: 'The Lighthouse Keeper', cards: cards, strings: AppStrings.en, scale: 1, font: CardFont.values.byName(const String.fromEnvironment('PDF_FONT', defaultValue: 'montserrat'))),
    );
    final text = latin1.decode(bytes!);
    expect(text, startsWith('%PDF-1.4'));
    expect(RegExp('/Subtype /Image').allMatches(text), hasLength(cards.length + 1)); // + the title block
    final pages = int.parse(RegExp(r'/Count (\d+)').firstMatch(text)!.group(1)!);
    expect(pages, greaterThan(1));
    const out = String.fromEnvironment('PDF_OUT');
    if (out.isNotEmpty) File(out).writeAsBytesSync(bytes);
  });
}
