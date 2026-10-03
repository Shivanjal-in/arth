// A book's cover, printed rather than drawn: every book gets a dye and a
// hand-block motif from its title, the way cloth from Sanganer or Bagru is
// dyed and stamped. The same title always gets the same cover, on every
// phone, so a book is recognisable wherever it appears — the library, a
// deck, the recap, the end of the book.
//
// Motifs, in the pale "discharge" colour a block leaves on dyed cloth:
//   buti      rows of small four-petalled flowers, alternate rows offset
//   jaal      a diamond lattice with a dot in every cell
//   leheriya  diagonal waves, the Rajasthani tie-dye stripe

import 'dart:io';
import 'dart:math' as math;

import 'package:arth/app/theme.dart';
import 'package:arth/data/covers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FNV-1a over the title's code units: stable across runs and devices
/// (String.hashCode makes no such promise).
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The dye a book of this title is printed on.
Color coverInk(String title) => kCoverInks[stableHash(title) % kCoverInks.length];

enum BlockMotif { buti, jaal, leheriya }

BlockMotif motifOf(String title) => BlockMotif.values[(stableHash(title) >> 7) % BlockMotif.values.length];

/// The motif, repeated over the whole area; [cell] is the block's size.
class BlockPrintPainter extends CustomPainter {
  BlockPrintPainter({required this.motif, required this.color, required this.cell});

  final BlockMotif motif;
  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, cell * 0.06)
      ..strokeCap = StrokeCap.round;
    switch (motif) {
      case BlockMotif.buti:
        final r = cell * 0.13;
        var row = 0;
        for (var y = cell * 0.5; y < size.height + cell; y += cell * 0.9, row++) {
          for (var x = (row.isOdd ? cell : cell * 0.5); x < size.width + cell; x += cell) {
            for (var k = 0; k < 4; k++) {
              final a = k * math.pi / 2 + math.pi / 4;
              canvas.drawCircle(Offset(x + math.cos(a) * r * 1.3, y + math.sin(a) * r * 1.3), r, fill);
            }
            canvas.drawCircle(Offset(x, y), r * 0.55, Paint()..color = color.withValues(alpha: color.a * 0.6));
          }
        }
      case BlockMotif.jaal:
        final path = Path();
        for (var d = -size.height; d < size.width + size.height; d += cell) {
          path
            ..moveTo(d, 0)
            ..lineTo(d + size.height, size.height)
            ..moveTo(d, size.height)
            ..lineTo(d + size.height, 0);
        }
        canvas.drawPath(path, stroke);
        // A dot at the centre of every diamond.
        var row = 0;
        for (var y = 0.0; y < size.height + cell; y += cell / 2, row++) {
          for (var x = row.isEven ? cell / 2 : 0.0; x < size.width + cell; x += cell) {
            canvas.drawCircle(Offset(x, y), cell * 0.08, fill);
          }
        }
      case BlockMotif.leheriya:
        final amp = cell * 0.14;
        for (var d = -size.height; d < size.width + size.height; d += cell * 0.55) {
          final path = Path()..moveTo(d, size.height);
          const steps = 24;
          for (var i = 1; i <= steps; i++) {
            final t = i / steps;
            // Along the diagonal, wobbling across it.
            final along = t * (size.height * 1.42);
            final wobble = math.sin(t * math.pi * 10) * amp;
            path.lineTo(d + along * 0.7071 + wobble * 0.7071, size.height - along * 0.7071 + wobble * 0.7071);
          }
          canvas.drawPath(path, stroke);
        }
    }
  }

  @override
  bool shouldRepaint(BlockPrintPainter old) => old.motif != motif || old.color != color || old.cell != cell;
}

/// A cover: dyed cloth, the title's motif, a spine, and a printed label
/// with the initial (or a camera, for a scan).
class BookCover extends ConsumerWidget {
  const BookCover({required this.title, required this.width, super.key, this.scan = false, this.elevation = 1, this.read = false});

  final String title;
  final double width;
  final bool scan;
  final bool read;
  final double elevation;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CoverArt(
        title: title,
        width: width,
        scan: scan,
        elevation: elevation,
        read: read,
        // A real cover, when one has been found for this title.
        photo: scan ? null : ref.watch(coverFileProvider(title)).valueOrNull,
      );
}

/// The cover itself, drawn from what it is given: dyed cloth with the title's
/// motif, a spine and a printed label, or a photo of the real cover. Needs
/// no app services, so it also draws in the deck PDF.
class CoverArt extends StatelessWidget {
  const CoverArt({required this.title, required this.width, super.key, this.scan = false, this.elevation = 1, this.read = false, this.photo});

  final String title;
  final double width;
  final bool scan;

  /// A marigold corner with a tick: the reader has finished it.
  final bool read;

  /// 0: flat (inside a card); 1: resting on the page.
  final double elevation;

  /// The real cover, if there is one.
  final File? photo;

  static const _scanInk = Color(0xFF4A5A6A);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final photo = this.photo;
    final ink = scan ? _scanInk : coverInk(title);
    final height = width * 1.38;
    final initial = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    // The block's pale print: paper, thinned, so every dye shows through.
    final print = c.paper.withValues(alpha: 0.2);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ink,
        border: Border.all(color: c.ink, width: 2),
        boxShadow: elevation == 0 ? null : [BoxShadow(color: c.shadow, offset: Offset(3 * elevation, 3 * elevation))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo == null)
            CustomPaint(
              painter: BlockPrintPainter(motif: scan ? BlockMotif.jaal : motifOf(title), color: print, cell: width * 0.34),
            )
          else
            Image.file(
              photo,
              fit: BoxFit.cover,
              // Sized to what's drawn, not to the file's pixels.
              cacheWidth: (width * 3).round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
                opacity: frame == null && !sync ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                child: child,
              ),
            ),
          // Spine: a darker band with a highlight where the cover bends.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: width * 0.11,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withValues(alpha: 0.32), Colors.black.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.10)],
                  stops: const [0, 0.7, 1],
                ),
              ),
            ),
          ),
          // The label: a paper cartouche the way a printer stamps a mark
          // (a real cover has its own).
          if (photo == null)
          Center(
            child: Padding(
              padding: EdgeInsets.only(left: width * 0.08),
              child: Container(
                width: width * 0.5,
                height: width * 0.5,
                decoration: BoxDecoration(
                  color: c.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: ink.withValues(alpha: 0.35), width: math.max(1, width * 0.02)),
                ),
                alignment: Alignment.center,
                child: scan
                    ? Icon(Icons.photo_camera_outlined, size: width * 0.24, color: ink)
                    : Text(initial, style: EnglishText.word(ink, size: width * 0.27).copyWith(height: 1)),
              ),
            ),
          ),
          if (read)
            Positioned(
              top: 0,
              right: 0,
              width: width * 0.46,
              height: width * 0.46,
              child: CustomPaint(
                painter: _CornerPainter(c.marigold),
                child: Align(
                  alignment: const Alignment(0.55, -0.55),
                  child: Icon(Icons.check_rounded, size: width * 0.2, color: c.ink),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

/// The book's motif as a faint texture over a band of its dye (the recap
/// header).
class BlockPrintTexture extends StatelessWidget {
  const BlockPrintTexture({required this.title, super.key, this.cell = 64, this.opacity = 0.09});

  final String title;
  final double cell;
  final double opacity;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: BlockPrintPainter(
      motif: motifOf(title),
      color: Colors.white.withValues(alpha: opacity),
      cell: cell,
    ),
  );
}
