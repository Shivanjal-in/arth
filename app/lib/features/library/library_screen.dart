// Library: the reader's PDFs, imported with the system file picker and copied
// into the app's documents directory so they survive picker-cache cleanup.

import 'dart:async';
import 'dart:io';

import 'package:arth/app/providers.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final h = HindiText(s.hindiScale);
    final books = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('किताबें')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: c.accent,
        foregroundColor: c.paper,
        onPressed: () => _import(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? _Empty(h: h)
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
  const _Empty({required this.h});

  final HindiText h;

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
            Text('अभी कोई किताब नहीं है', style: h.headline(c.ink), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'नीचे + दबाकर कोई अंग्रेज़ी PDF जोड़ें। पढ़ते हुए किसी भी शब्द पर टैप करें।',
              style: h.body(c.inkMuted),
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
    final h = HindiText(ref.watch(settingsProvider).hindiScale);
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
              Text('पृष्ठ ${book.lastPage} / $pages', style: h.small(c.inkMuted)),
            ] else
              Text('अभी शुरू नहीं किया', style: h.small(c.inkMuted)),
          ],
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: c.inkMuted),
      onTap: () => context.push('/read/${book.id}'),
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('किताब हटाएँ?', style: h.headline(c.ink)),
            content: Text(book.title, style: EnglishText.body(c.ink)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('नहीं')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('हटाएँ')),
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
