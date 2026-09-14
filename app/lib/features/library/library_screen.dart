// Library: the reader's PDFs, imported with the system file picker and copied
// into the app's documents directory so they survive picker-cache cleanup.

import 'dart:async';
import 'dart:io';

import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/scan/scan_pages.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;
    final docs = ref.read(documentsDirProvider);
    await Directory(p.join(docs, 'books')).create(recursive: true);
    final rel = p.join('books', '${DateTime.now().millisecondsSinceEpoch}_${file.name}');
    // Stream-copy: the picker's URI may not be a plain file path (Android SAF).
    final sink = File(p.join(docs, rel)).openWrite();
    await sink.addStream(file.readAsByteStream());
    await sink.close();
    final title = p.basenameWithoutExtension(file.name).replaceAll(RegExp('[_-]+'), ' ');
    final book = await ref.read(libraryProvider.notifier).add(title: title, path: rel);
    if (context.mounted) unawaited(context.push('/read/${book.id}'));
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
              leading: Icon(Icons.picture_as_pdf_outlined, color: c.accent),
              title: Text(t.addPdf, style: style),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_importSafely(context, ref));
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: c.accent),
              title: Text(t.takePhoto, style: style),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_scan(context, ref, ScanSource.camera));
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: c.accent),
              title: Text(t.chooseFromGallery, style: style),
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
        onPressed: () => _addMenu(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(t.somethingWrong, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: s.hindiScale))),
        data: (list) => list.isEmpty
            ? _Empty(t: t, scale: s.hindiScale)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => Divider(color: c.rule),
                itemBuilder: (_, i) => _BookTile(book: list[i]),
              ),
      ),
    );
  }
}

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
            Text('अ', style: const HindiText(1).headline(c.rule).copyWith(fontSize: 72, height: 1)),
            const SizedBox(height: 16),
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
    final progress = pages == null || pages == 0 ? null : book.lastPage / pages;
    return InkWell(
      onTap: () => context.push(book.kind == BookKind.scan ? '/scan/${book.id}' : '/read/${book.id}'),
      onLongPress: () => _confirmRemove(context, ref, t, scale),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _Cover(title: book.title, scan: book.kind == BookKind.scan),
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
                  if (progress != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        color: c.marigold,
                        backgroundColor: c.rule,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(t.page(book.lastPage, pages!), style: small),
                  ] else if (book.kind == BookKind.scan && pages != null)
                    Text('$pages ${t.pages}', style: small)
                  else
                    Text(t.notStarted, style: small),
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

/// A book has no cover of its own (it's a PDF), so it gets a spine-coloured
/// one: an ink picked from the title, the first letter set large.
class _Cover extends StatelessWidget {
  const _Cover({required this.title, this.scan = false});

  final String title;
  final bool scan;

  @override
  Widget build(BuildContext context) {
    final ink = scan ? const Color(0xFF4A5A6A) : kCoverInks[title.hashCode.abs() % kCoverInks.length];
    final initial = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();
    return Container(
      width: 54,
      height: 74,
      decoration: BoxDecoration(
        color: ink,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(8)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(2, 3))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 6, color: Colors.black.withValues(alpha: 0.22)),
          ),
          Center(
            child: scan
                ? Icon(Icons.photo_camera_outlined, color: Colors.white.withValues(alpha: 0.92), size: 26)
                : Text(
                    initial,
                    style: EnglishText.word(Colors.white.withValues(alpha: 0.92), size: 28),
                  ),
          ),
        ],
      ),
    );
  }
}
