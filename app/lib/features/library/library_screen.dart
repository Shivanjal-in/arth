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
import 'package:arth/features/library/book_category.dart';
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
        title: Text(
          t.tabLibrary,
          style: uiTitle(hindi: t.isHindi, color: c.ink, scale: s.hindiScale).copyWith(fontSize: 26),
        ),
        toolbarHeight: 64,
        actions: [
          IconButton(
            tooltip: t.readingHabit,
            icon: const Icon(Icons.local_fire_department_outlined),
            onPressed: () => context.push('/habit'),
          ),
          IconButton(
            tooltip: t.archive,
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => context.push('/archive'),
          ),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 60,
        height: 60,
        child: Pressable.card(
          color: c.button,
          onTap: () => unawaited(_addMenu(context, ref)),
          child: Center(child: Icon(Icons.add_rounded, color: c.onButton, size: 28)),
        ),
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            t.somethingWrong,
            style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale),
          ),
        ),
        data: (list) {
          final shelf = [
            for (final b in list)
              if (!b.archived) b,
          ];
          if (shelf.isEmpty) return _Empty(t: t, scale: s.hindiScale, archived: list.isNotEmpty);
          return _Shelf(books: shelf);
        },
      ),
    );
  }
}

/// Whether the library's entrance has played this launch.
bool _introPlayed = false;

class _Shelf extends ConsumerStatefulWidget {
  const _Shelf({required this.books});

  final List<Book> books;

  @override
  ConsumerState<_Shelf> createState() => _ShelfState();
}

enum _ReadFilter { read, unread }

class _ShelfState extends ConsumerState<_Shelf> {
  BookCategory? _filter;
  _ReadFilter? _read;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final used = <BookCategory>[];
    for (final book in widget.books) {
      final category = BookCategory.resolve(book.categoryGroup, book.category);
      if (category != null && !used.contains(category)) used.add(category);
    }
    final anyRead = widget.books.any((b) => b.finishedAt != null);
    final filter = used.contains(_filter) ? _filter : null;
    final read = anyRead ? _read : null;
    final shelf = [
      for (final b in widget.books)
        if ((filter == null || BookCategory.resolve(b.categoryGroup, b.category) == filter) &&
            (read == null || (read == _ReadFilter.read) == (b.finishedAt != null)))
          b,
    ];
    // The book in progress that was opened last leads, larger.
    final current = shelf.where((b) => b.lastOpenedAt != null && b.finishedAt == null && b.kind != BookKind.scan).firstOrNull;
    // Read books sink below the ones still being read; otherwise the store's order (latest first).
    final rest = [
      for (final b in shelf)
        if (b != current && b.finishedAt == null) b,
      for (final b in shelf)
        if (b != current && b.finishedAt != null) b,
    ];
    final intro = !_introPlayed;
    _introPlayed = true;
    Widget settle(int i, Widget child) => intro && i < 8 ? SettleIn(delay: Motion.stagger * i, child: child) : child;
    final t = ref.watch(stringsProvider);

    return Column(
      children: [
        if (used.isNotEmpty || anyRead)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              children: [
                // Tapping a selected one again lets it go.
                if (anyRead)
                  for (final (value, label) in [(_ReadFilter.unread, t.unreadFilter), (_ReadFilter.read, t.readFilter)])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: value == _ReadFilter.read ? Icon(Icons.check_circle_rounded, size: 16, color: c.marigold) : null,
                        label: Text(label),
                        selected: read == value,
                        showCheckmark: false,
                        onSelected: (_) {
                          Haptics.choose();
                          setState(() => _read = read == value ? null : value);
                        },
                      ),
                    ),
                if (anyRead && used.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 10, 10),
                    child: VerticalDivider(width: 1, color: c.rule),
                  ),
                if (used.isNotEmpty)
                  for (final choice in [null, ...used])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(choice == null ? t.allCategories : choice.label(hindi: t.isHindi)),
                        selected: filter == choice,
                        showCheckmark: false,
                        onSelected: (_) {
                          Haptics.choose();
                          setState(() => _filter = choice);
                        },
                      ),
                    ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
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
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.t, required this.scale, this.archived = false});

  final AppStrings t;
  final double scale;

  /// Every book has been archived; the shelf itself is empty.
  final bool archived;

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
                      child: Transform.rotate(
                        angle: angle,
                        child: BookCover(title: title, width: 64),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              archived ? t.shelfClearTitle : t.libraryEmptyTitle,
              style: uiHeadline(hindi: t.isHindi, color: c.ink, scale: scale),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              archived ? t.shelfClearBody : t.libraryEmptyBody,
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
    final finished = book.finishedAt;
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Pressable(
          onTap: () => context.push(routeFor(book)),
          onLongPress: () => showBookMenu(context, ref, book),
          scale: 0.98,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 40, 12),
            child: Row(
              children: [
                BookCover(title: book.title, width: 54, scan: book.kind == BookKind.scan, read: finished != null),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: EnglishText.word(finished == null ? c.ink : c.inkMuted, size: 19),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (BookCategory.resolve(book.categoryGroup, book.category) case final category?)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            category.label(hindi: t.isHindi),
                            style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale).copyWith(fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (finished != null)
                        Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 15, color: c.marigold),
                            const SizedBox(width: 6),
                            Text(t.readOn(finished), style: small),
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
              ],
            ),
          ),
        ),
        _BookMenuButton(book: book),
      ],
    );
  }
}

class _BookMenuButton extends ConsumerWidget {
  const _BookMenuButton({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return IconButton(
      tooltip: t.more,
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.more_vert_rounded, color: context.colors.inkMuted),
      onPressed: () => showBookMenu(context, ref, book),
    );
  }
}

String _categoryTitle(AppStrings t, Book book) {
  final category = BookCategory.resolve(book.categoryGroup, book.category);
  return category == null ? t.category : category.label(hindi: t.isHindi);
}

/// Category, archive, or delete. Deleting still asks, because it removes the file.
Future<void> showBookMenu(BuildContext context, WidgetRef ref, Book book) async {
  final t = ref.read(stringsProvider);
  final c = context.colors;
  final scale = ref.read(settingsProvider).hindiScale;
  final style = uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 17);
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(book.finishedAt == null ? Icons.check_circle_outline_rounded : Icons.remove_done_rounded, color: c.accent),
            title: Text(book.finishedAt == null ? t.markAsRead : t.markAsUnread, style: style),
            onTap: () => Navigator.pop(ctx, 'read'),
          ),
          ListTile(
            leading: Icon(Icons.category_outlined, color: c.accent),
            title: Text(_categoryTitle(t, book), style: style),
            onTap: () => Navigator.pop(ctx, 'category'),
          ),
          ListTile(
            leading: Icon(book.archived ? Icons.unarchive_outlined : Icons.archive_outlined, color: c.accent),
            title: Text(book.archived ? t.putBack : t.moveToArchive, style: style),
            onTap: () => Navigator.pop(ctx, 'archive'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: c.accent),
            title: Text(t.delete, style: style),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'read') {
    Haptics.commit();
    await ref.read(libraryProvider.notifier).setFinished(book.id, finished: book.finishedAt == null);
    return;
  }
  if (choice == 'category') {
    final current = BookCategory.resolve(book.categoryGroup, book.category);
    final pick = await showCategoryPicker(context, ref, current: current);
    if (pick == null || !context.mounted) return;
    await ref.read(libraryProvider.notifier).setCategory(book.id, group: pick.category?.shelfName, category: pick.category?.id);
    return;
  }
  if (choice == 'archive') {
    final archived = !book.archived;
    await ref.read(libraryProvider.notifier).setArchived(book.id, archived: archived);
    if (!context.mounted || !archived) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.movedToArchive),
        action: SnackBarAction(
          label: t.undo,
          onPressed: () => unawaited(ref.read(libraryProvider.notifier).setArchived(book.id, archived: false)),
        ),
      ),
    );
    return;
  }
  await _confirmRemove(context, ref, book);
}

Future<void> _confirmRemove(BuildContext context, WidgetRef ref, Book book) async {
  final t = ref.read(stringsProvider);
  final scale = ref.read(settingsProvider).hindiScale;
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      title: Text(
        t.removeBook,
        style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale),
      ),
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
    return Stack(
      children: [
        Pressable.card(
          onTap: () => context.push(routeFor(book)),
          onLongPress: () => showBookMenu(context, ref, book),
          child: Stack(
            children: [
              // The book's own print, faint, across the card: this card is that book.
              Positioned.fill(
                child: CustomPaint(
                  painter: BlockPrintPainter(motif: motifOf(book.title), color: ink.withValues(alpha: 0.035), cell: 40),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  children: [
                    BookCover(title: book.title, width: 76),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.continueReading,
                              style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale),
                            ),
                            const SizedBox(height: 4),
                            Text(book.title, style: EnglishText.word(c.ink, size: 21), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (BookCategory.resolve(book.categoryGroup, book.category) case final category?)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  category.label(hindi: t.isHindi),
                                  style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale).copyWith(fontSize: 12.5),
                                ),
                              ),
                            if (where != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                where,
                                style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13),
                              ),
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
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(top: 4, right: 9, child: _BookMenuButton(book: book)),
      ],
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
        onTap: () => context.push(deckRoute((bookId: book.id, bookTitle: book.title))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style_outlined, size: 15, color: c.accent),
              const SizedBox(width: 6),
              Text(
                t.cardCount(count),
                style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale).copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Books moved off the shelf. Opening one still works; the menu puts it back.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final books = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.archive)),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            t.somethingWrong,
            style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale),
          ),
        ),
        data: (list) {
          final archived = [
            for (final b in list)
              if (b.archived) b,
          ];
          if (archived.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.archive_outlined, size: 40, color: c.inkMuted),
                    const SizedBox(height: 16),
                    Text(
                      t.archiveEmptyTitle,
                      style: uiHeadline(hindi: t.isHindi, color: c.ink, scale: scale),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.archiveEmptyBody,
                      style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            itemCount: archived.length,
            separatorBuilder: (_, _) => Divider(color: c.rule),
            itemBuilder: (_, i) => _BookTile(book: archived[i]),
          );
        },
      ),
    );
  }
}
