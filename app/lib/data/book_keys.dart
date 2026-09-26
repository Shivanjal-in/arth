// Content keys for books imported before keys existed (and any whose key
// failed at import), computed in the background at startup.

import 'package:arth/core/book_key.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

Future<void> backfillContentKeys(LocalStore store, String docsDir) async {
  for (final book in await store.booksWithoutKey()) {
    try {
      await store.setContentKey(book.id, await contentKeyOf(p.join(docsDir, book.path)));
    } on Exception catch (e) {
      debugPrint('content key for ${book.path}: $e'); // file gone; the reader reports it
    }
  }
}
