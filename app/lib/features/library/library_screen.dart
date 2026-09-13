// Library: the reader's PDFs, imported with the system file picker and copied
// into the app's documents directory so they survive picker-cache cleanup.

import 'dart:async';
import 'dart:io';

import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final t = ref.watch(stringsProvider);
    final books = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.tabLibrary)),
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.accent,
        foregroundColor: c.paper,
        onPressed: () => _importSafely(context, ref),
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
                separatorBuilder: (_, _) => const Divider(),
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
            Icon(Icons.menu_book_rounded, size: 48, color: c.rule),
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      title: Text(book.title, style: EnglishText.word(c.ink, size: 20)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            if (progress != null) ...[
              SizedBox(
                width: 80,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: c.accent,
                  backgroundColor: c.rule,
                ),
              ),
              const SizedBox(width: 10),
              Text(t.page(book.lastPage, pages!), style: small),
            ] else
              Text(t.notStarted, style: small),
          ],
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: c.inkMuted),
      onTap: () => context.push('/read/${book.id}'),
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.removeBook, style: uiHeadline(hindi: t.isHindi, color: c.ink, scale: scale)),
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
            await File(p.join(ref.read(documentsDirProvider), book.path)).delete();
          } on FileSystemException {
            // already gone
          }
        }
      },
    );
  }
}
