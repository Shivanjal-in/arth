// A scan is a book made of photographed pages: a directory under
// Documents/scans/<id>/ holding page-NNN.<ext> images and their OCR cache.

import 'dart:io';

import 'package:arth/app/providers.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

enum ScanSource { camera, gallery }

/// Picks one photo. Returns null if the user cancelled or permission was denied.
Future<XFile?> pickScanImage(ScanSource source) async {
  final picker = ImagePicker();
  try {
    return await picker.pickImage(
      source: source == ScanSource.camera ? ImageSource.camera : ImageSource.gallery,
      // Books photographed at full resolution are 12 MP+; OCR needs ~2000 px.
      maxWidth: 2200,
      maxHeight: 2200,
      imageQuality: 90,
      requestFullMetadata: false,
    );
  } on Exception {
    return null;
  }
}

class ScanPages {
  ScanPages(this.docsDir);

  final String docsDir;

  String dirFor(Book book) => p.join(docsDir, book.path);

  /// Page image paths in order.
  List<String> pagesOf(Book book) {
    final dir = Directory(dirFor(book));
    if (!dir.existsSync()) return const [];
    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => RegExp(r'page-\d{3}\.(jpe?g|png|heic)$', caseSensitive: false).hasMatch(p.basename(path)))
        .toList()
      ..sort();
    return files;
  }

  /// Copies a picked image in as the next page; returns its path.
  Future<String> addPage(Book book, XFile picked) async {
    final dir = Directory(dirFor(book));
    await dir.create(recursive: true);
    final n = pagesOf(book).length + 1;
    final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path).toLowerCase();
    final dest = p.join(dir.path, 'page-${n.toString().padLeft(3, '0')}$ext');
    await picked.saveTo(dest);
    return dest;
  }
}

final scanPagesProvider = Provider<ScanPages>((ref) => ScanPages(ref.watch(documentsDirProvider)));

/// Creates a scan book from a first photo and returns it.
Future<Book> createScan(WidgetRef ref, XFile first, {required String title}) async {
  final rel = p.join('scans', DateTime.now().millisecondsSinceEpoch.toString());
  final book = await ref.read(libraryProvider.notifier).add(title: title, path: rel, kind: BookKind.scan);
  await ref.read(scanPagesProvider).addPage(book, first);
  await ref.read(libraryProvider.notifier).touch(book.id, pageCount: 1);
  return book;
}
