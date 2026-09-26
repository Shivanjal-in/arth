// A book's cards as a PDF to share or print. Each card is drawn by Flutter
// off screen — so Hindi is shaped and the app's fonts are used — captured as
// a picture, and laid out on A4 pages (core/pdf/image_pdf.dart). Always the
// light theme: it's meant for paper.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/pdf/image_pdf.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _margin = 40.0;
const _gap = 10.0;
const double _contentWidth = a4Width - 2 * _margin;

/// Render resolution: pixels per point. Sharp in print, and a few hundred
/// KB per card once compressed.
const _pixelRatio = 2.0;

/// Builds the PDF for [cards] of [bookTitle] and opens the share sheet.
/// [origin] is where the share sheet points from on an iPad.
Future<void> exportDeckPdf(BuildContext context, WidgetRef ref, {required String bookTitle, required List<Flashcard> cards, Rect? origin}) async {
  final t = ref.read(stringsProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 18),
              Expanded(child: Text(t.preparingPdf)),
            ],
          ),
        ),
      ),
    ),
  );
  File? file;
  try {
    final settings = ref.read(settingsProvider);
    final bytes = await buildDeckPdf(bookTitle: bookTitle, cards: cards, strings: t, scale: settings.hindiScale, font: settings.cardFont);
    final dir = await getTemporaryDirectory();
    final name = bookTitle.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
    file = File('${dir.path}/${name.isEmpty ? 'Arth' : name} - cards.pdf');
    await file.writeAsBytes(bytes, flush: true);
  } on Exception catch (e) {
    debugPrint('pdf export failed: $e');
  } finally {
    navigator.pop();
  }
  if (file == null) {
    messenger?.showSnackBar(SnackBar(content: Text(t.pdfFailed)));
    return;
  }
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], subject: t.pdfSubject(bookTitle), sharePositionOrigin: origin),
  );
}

/// The PDF itself: a title block, then every card in reading order.
Future<Uint8List> buildDeckPdf({
  required String bookTitle,
  required List<Flashcard> cards,
  required AppStrings strings,
  required double scale,
  CardFont font = CardFont.montserrat,
}) async {
  Widget page(Widget child) => _PrintFrame(strings: strings, child: child);
  final header = page(_Header(bookTitle: bookTitle, count: cards.length, strings: strings));
  final tiles = [for (final card in cards) page(_PrintCard(card: card, strings: strings, scale: scale, font: font))];

  // Styles ask Google Fonts for their files on first use: draw once to ask,
  // wait for them, then draw for real.
  await _capture(header);
  if (tiles.isNotEmpty) await _capture(tiles.first);
  await GoogleFonts.pendingFonts();

  final pages = <PdfPageSpec>[];
  var y = double.infinity;
  const bottom = a4Height - _margin - 12; // room for the footer
  void place(PdfImage img) {
    var w = _contentWidth;
    var h = img.height / _pixelRatio;
    const full = bottom - _margin;
    if (h > full) {
      // Taller than a page (a very long note): shrink to fit.
      w *= full / h;
      h = full;
    }
    if (y + h > bottom) {
      pages.add(PdfPageSpec(footer: 'Made with Arth'));
      y = _margin;
    }
    pages.last.placements.add((image: img, x: _margin, y: y, w: w, h: h));
    y += h + _gap;
  }

  place(await _capture(header));
  y += 8;
  for (final tile in tiles) {
    place(await _capture(tile));
  }
  final numbered = [
    for (final (i, p) in pages.indexed) PdfPageSpec(footer: 'Made with Arth   |   ${i + 1} / ${pages.length}')..placements.addAll(p.placements),
  ];
  return buildImagePdf(numbered, title: bookTitle);
}

/// Draws [widget] off screen, [_contentWidth] points wide and as tall as it
/// needs, and returns its pixels flattened onto white.
Future<PdfImage> _capture(Widget widget) async {
  final boundary = RenderRepaintBoundary();
  final view = ui.PlatformDispatcher.instance.implicitView!;
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(const Size(_contentWidth, 4000)),
      devicePixelRatio: _pixelRatio,
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final build = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(container: boundary, child: widget).attachToRenderTree(build);
  build
    ..buildScope(root)
    ..finalizeTree();
  pipeline
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();
  final image = await boundary.toImage(pixelRatio: _pixelRatio);
  final rgba = (await image.toByteData())!.buffer.asUint8List();
  final rgb = Uint8List(image.width * image.height * 3);
  for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    // Premultiplied RGBA over white.
    final a = 255 - rgba[i + 3];
    rgb[j] = rgba[i] + a;
    rgb[j + 1] = rgba[i + 1] + a;
    rgb[j + 2] = rgba[i + 2] + a;
  }
  final out = PdfImage(width: image.width, height: image.height, rgb: rgb);
  image.dispose();
  return out;
}

/// What a widget needs to draw with no app around it.
class _PrintFrame extends StatelessWidget {
  const _PrintFrame({required this.strings, required this.child});

  final AppStrings strings;
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: arthTheme(Brightness.light),
            child: DefaultTextStyle(
              style: const TextStyle(),
              // Unbounded height, as in a list: a Column takes only what it needs.
              child: UnconstrainedBox(
                alignment: Alignment.topLeft,
                constrainedAxis: Axis.horizontal,
                child: SizedBox(width: _contentWidth, child: child),
              ),
            ),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.bookTitle, required this.count, required this.strings});

  final String bookTitle;
  final int count;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          BookCover(title: bookTitle, width: 58, elevation: 0),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bookTitle, style: EnglishText.title(c.ink, size: 26)),
                const SizedBox(height: 4),
                Text(
                  '${strings.cardCount(count)}  ·  ${now.day}/${now.month}/${now.year}',
                  style: uiBody(hindi: strings.isHindi, color: c.inkMuted, size: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A card in full: nothing cut short, as it's the only copy on paper.
class _PrintCard extends StatelessWidget {
  const _PrintCard({required this.card, required this.strings, required this.scale, required this.font});

  final Flashcard card;
  final AppStrings strings;
  final double scale;
  final CardFont font;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = kindColor(card.kind, c);
    final front = switch (card.kind) {
      CardKind.quote => Text('“${card.front}”', style: cardStyle(card.front, font, color: c.ink, scale: scale, italic: true)),
      CardKind.word => Text(card.front, style: cardStyle(card.front, font, color: c.ink, scale: scale, size: 21, weight: FontWeight.w600)),
      CardKind.idea => Text(card.front, style: cardStyle(card.front, font, color: c.ink, scale: scale, weight: FontWeight.w600)),
    };
    final context_ = card.context;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.rule),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(color: ink, borderRadius: const BorderRadius.horizontal(left: Radius.circular(12))),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(kindIcon(card.kind), size: 14, color: ink),
                        const SizedBox(width: 6),
                        Text(kindLabel(card.kind, strings), style: uiLabel(hindi: strings.isHindi, color: c.inkMuted).copyWith(fontSize: 12)),
                        const SizedBox(width: 12),
                        if (card.location != null)
                          Expanded(
                            child: Text(card.location!, style: EnglishText.label(c.inkMuted, size: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    front,
                    if (card.back.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(card.back, style: cardStyle(card.back, font, color: c.ink, scale: scale, size: 15)),
                    ],
                    if (card.note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.only(left: 10),
                        decoration: BoxDecoration(border: Border(left: BorderSide(color: c.marigold, width: 2))),
                        child: Text(card.note, style: cardStyle(card.note, font, color: c.inkMuted, scale: scale, size: 14, italic: true)),
                      ),
                    ],
                    if (context_ != null && context_.isNotEmpty && card.kind != CardKind.quote && context_ != card.front) ...[
                      const SizedBox(height: 8),
                      Text(context_, style: EnglishText.italic(c.inkMuted, size: 12.5)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
