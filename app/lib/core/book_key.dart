// A book's identity across devices: the same file imported on two phones
// gets the same key, whatever it's called or wherever it was saved. So
// synced cards and bookmarks can find "their" book.
//
// SHA-256 over the file's length and its first MiB: enough to tell books
// apart (the first MiB holds the metadata and opening chapters) without
// reading a 200 MB scanned PDF end to end.

import 'dart:io';

import 'package:crypto/crypto.dart';

const int _sample = 1 << 20;

Future<String> contentKeyOf(String path) async {
  final file = File(path);
  final length = await file.length();
  final raf = await file.open();
  try {
    final head = await raf.read(_sample);
    final lengthBytes = List<int>.generate(8, (i) => (length >> (8 * i)) & 0xFF);
    return sha256.convert([...lengthBytes, ...head]).toString();
  } finally {
    await raf.close();
  }
}
