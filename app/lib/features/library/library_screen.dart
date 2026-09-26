// Library: the reader's PDFs, EPUBs and other documents, imported with the
// system file picker
// and copied into the app's documents directory so they survive picker-cache
// cleanup; plus scans photographed in the app.

import 'dart:async';
import 'dart:io';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/book_key.dart';
import 'package:arth/core/formats/reflow_book.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/deck_screen.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:arth/features/plans/paid_gate.dart';
import 'package:arth/features/scan/scan_pages.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// The reader route for a book, by kind.
String routeFor(Book book) => switch (book.kind) {
      BookKind.pdf => '/read/${book.id}',
      BookKind.epub => '/epub/${book.id}',
      BookKind.scan => '/scan/${book.id}',
    };

/// The reader route opening [book] at a page (EPUB: chapter) and block.
String bookRoute(Book book, {required int page, int? block}) =>
    Uri(path: routeFor(book), queryParameters: {'page': '$page', if (block != null) 'block': '$block'}).toString();

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    // Any file, checked here: a custom filter goes through the platform's
    // MIME/UTI tables, which don't know .fb2 and friends and hide them.
    final file = await FilePicker.pickFile();
    if (file == null) return;
    final ext = reflowExtensionOf(file.name);
    if (ext != '.pdf' && !reflowExtensions.contains(ext)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).unsupportedFile)));
      }
      return;
    }
    final kind = ext == '.pdf' ? BookKind.pdf : BookKind.epub;
    final docs = ref.read(documentsDirProvider);
    await Directory(p.join(docs, 'books')).create(recursive: true);
    final rel = p.join('books', '${DateTime.now().millisecondsSinceEpoch}_${file.name}');
    // Stream-copy: the picker's URI may not be a plain file path (Android SAF).
    final sink = File(p.join(docs, rel)).openWrite();
    await sink.addStream(file.readAsByteStream());
    await sink.close();
    var title = p.basenameWithoutExtension(file.name).replaceAll(RegExp('[_-]+'), ' ');
    if (kind == BookKind.epub) title = await _bookTitle(p.join(docs, rel)) ?? title;
    final book = await ref.read(libraryProvider.notifier).add(title: title, path: rel, kind: kind);
    // Cards and bookmarks synced from another device for this book attach now.
    await ref.read(localStoreProvider).setContentKey(book.id, await contentKeyOf(p.join(docs, rel)));
    ref
      ..invalidate(flashcardsProvider)
      ..invalidate(decksProvider)
      ..invalidate(bookmarksProvider);
    if (context.mounted) unawaited(context.push(routeFor(book)));
  }

  /// The title from the book's own metadata, when it has a usable one.
  static Future<String?> _bookTitle(String path) async {
    try {
      final book = await ReflowBook.open(path);
      await book.close();
      return book.title == 'Untitled' ? null : book.title;
    } on Exception {
      return null; // the reader will report the failure when opened
    }
  }

  Future<void> _importSafely(BuildContext context, WidgetRef ref) async {
    try {
      await _import(context, ref);
    } on Exception catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).importFailed)));
    }
  }

  Future<void> _scan(BuildContext context, WidgetRef ref, ScanSource source) async {
    final t0 = ref.read(stringsProvider);
    if (!await ensurePaid(context, ref, title: t0.scanTitlePaid, why: t0.scanNeedsPlan)) return;
    final picked = await pickScanImage(source);
    if (picked == null || !context.mounted) return;
    final t = ref.read(stringsProvider);
    final now = DateTime.now();
    final stamp = '${now.day}/${now.month}/${now.year}';
    final book = await createScan(ref, picked, title: '${t.scanTitle} $stamp');
    if (context.mounted) unawaited(context.push('/scan/${book.id}'));
  }

  Future<void> _addMenu(BuildContext context, WidgetRef ref) async {
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final s = ref.read(settingsProvider);
    final style = uiBody(hindi: t.isHindi, color: c.ink, scale: s.hindiScale, size: 17);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.menu_book_outlined, color: c.accent),
              title: Text(t.addPdf, style: style),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_importSafely(context, ref));
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: c.accent),
              title: Text(t.takePhoto, style: style),
              trailing: const PaidTag(),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_scan(context, ref, ScanSource.camera));
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: c.accent),
              title: Text(t.chooseFromGallery, style: style),
              trailing: const PaidTag(),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_scan(context, ref, ScanSource.gallery));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final books = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.tabLibrary, style: uiTitle(hindi: t.isHindi, color: c.ink, scale: s.hindiScale).copyWith(fontSize: 26)),
        toolbarHeight: 64,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.accent,
        foregroundColor: c.paper,
        onPressed: () {
          Haptics.open();
          unawaited(_addMenu(context, ref));
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(t.somethingWrong, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale))),
        data: (list) {
          if (list.isEmpty) return _Empty(t: t, scale: s.hindiScale);
          // The book in progress that was opened last leads, larger.
          final current = list.where((b) => b.lastOpenedAt != null && b.finishedAt == null && b.kind != BookKind.scan).firstOrNull;
          final rest = [for (final b in list) if (b != current) b];
          // The one orchestrated moment: on the first visit after launch the
          // books settle in one after another, like blocks pressed on cloth.
          final intro = !_introPlayed;
          _introPlayed = true;
          Widget settle(int i, Widget child) =>
              intro && i < 8 ? SettleIn(delay: Motion.stagger * i, child: child) : child;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
            itemCount: rest.length + (current == null ? 0 : 1),
            separatorBuilder: (_, i) => current != null && i == 0 ? const SizedBox(height: 16) : Divider(color: c.rule),
            itemBuilder: (_, i) {
              if (current != null) {
                if (i == 0) return settle(0, _ContinueCard(book: current));
                return settle(i, _BookTile(book: rest[i - 1]));
              }
              return settle(i, _BookTile(book: rest[i]));
            },
          );
        },
      ),
    );
  }
}

/// Whether the library's entrance has played this launch.
bool _introPlayed = false;

class _Empty extends StatelessWidget {
  const _Empty({required this.t, required this.scale});

  final AppStrings t;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Three books fanned out: what the shelf will look like.
            SizedBox(
              width: 170,
              height: 110,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  for (final (title, angle, dx) in const [('Godan', -0.18, -46.0), ('The Guide', 0.16, 46.0), ('Pride and Prejudice', 0.0, 0.0)])
                    Transform.translate(
                      offset: Offset(dx, angle == 0 ? -6 : 0),
                      child: Transform.rotate(angle: angle, child: BookCover(title: title, width: 64)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(t.libraryEmptyTitle, style: uiHeadline(hindi: t.isHindi, color: c.ink, scale: scale), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              t.libraryEmptyBody,
              style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  const _BookTile({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final t = ref.watch(stringsProvider);
    final small = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13);
    final pages = book.pageCount;
    final progress = book.readFraction;
    final cardCount = ref.watch(decksProvider).valueOrNull?.where((d) => d.bookId == book.id).firstOrNull?.count ?? 0;
    return Pressable(
      onTap: () => context.push(routeFor(book)),
      onLongPress: () => _confirmRemove(context, ref, t, scale),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            BookCover(title: book.title, width: 54, scan: book.kind == BookKind.scan),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: EnglishText.word(c.ink, size: 19),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (book.finishedAt != null)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 15, color: c.marigold),
                        const SizedBox(width: 6),
                        Text(t.finishedReading, style: small),
                      ],
                    )
                  else if (progress != null && pages != null && book.kind != BookKind.scan) ...[
                    ReadingBar(value: progress, height: 3),
                    const SizedBox(height: 6),
                    Text(
                      '${book.kind == BookKind.epub ? t.chapter(book.lastPage, pages) : t.page(book.lastPage, pages)}  ·  ${(progress * 100).round()}%',
                      style: small,
                    ),
                  ] else if (book.kind == BookKind.scan && pages != null)
                    Text('$pages ${t.pages}', style: small)
                  else
                    Text(t.notStarted, style: small),
                  if (cardCount > 0) _CardsChip(book: book, count: cardCount),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: c.rule),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, AppStrings t, double scale) async {
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(t.removeBook, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
        content: Text(book.title, style: EnglishText.body(c.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.no)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.remove)),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(libraryProvider.notifier).remove(book.id);
      try {
        final target = p.join(ref.read(documentsDirProvider), book.path);
        if (book.kind == BookKind.scan) {
          await Directory(target).delete(recursive: true);
        } else {
          await File(target).delete();
        }
      } on FileSystemException {
        // already gone
      }
    }
  }
}

/// The book being read, set large: cover, where the reader is, how far, and
/// one tap back in.
class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final progress = book.readFraction ?? 0;
    final pages = book.pageCount;
    final where = pages == null ? null : (book.kind == BookKind.epub ? t.chapter(book.lastPage, pages) : t.page(book.lastPage, pages));
    final cardCount = ref.watch(decksProvider).valueOrNull?.where((d) => d.bookId == book.id).firstOrNull?.count ?? 0;
    final ink = coverInk(book.title);
    return Pressable(
      onTap: () => context.push(routeFor(book)),
      scale: 0.985,
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // The book's own print, faint, across the card: this card is that book.
            Positioned.fill(
              child: CustomPaint(painter: BlockPrintPainter(motif: motifOf(book.title), color: ink.withValues(alpha: 0.035), cell: 40)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  BookCover(title: book.title, width: 76),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.continueReading, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale)),
                        const SizedBox(height: 4),
                        Text(book.title, style: EnglishText.word(c.ink, size: 21), maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (where != null) ...[
                          const SizedBox(height: 4),
                          Text(where, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13)),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ReadingBar(value: progress, height: 6),
                            ),
                            const SizedBox(width: 10),
                            Text('${(progress * 100).round()}%', style: EnglishText.label(c.ink)),
                          ],
                        ),
                        if (cardCount > 0) _CardsChip(book: book, count: cardCount),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "5 cards" under a book, opening its recap.
class _CardsChip extends ConsumerWidget {
  const _CardsChip({required this.book, required this.count});

  final Book book;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push(deckRoute((bookId: book.id, bookTitle: book.title))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style_outlined, size: 15, color: c.accent),
              const SizedBox(width: 6),
              Text(t.cardCount(count), style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale).copyWith(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}
