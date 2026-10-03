// Real book covers. A cover is looked up once per title (our server asks Open
// Library), downloaded to the phone, and remembered, so a title costs one
// lookup ever and the library draws from files after that. A title with no
// good match is remembered for a few days, so the server isn't asked again
// on every launch; a lookup that failed (offline) isn't remembered at all.

import 'dart:io';

import 'package:arth/app/providers.dart';
import 'package:arth/data/api_client.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

const _retryMissAfter = Duration(days: 3);

/// What identifies a book for its cover: the title's words, lower-cased.
String coverKeyOf(String title) {
  final words = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return sha1.convert(words.join(' ').codeUnits).toString();
}

/// The downloaded cover for a title, or null: covers are off, there's no
/// good match, or it couldn't be fetched (yet).
// ignore: specify_nonobvious_property_types
final coverFileProvider = FutureProvider.family<File?, String>((ref, title) async {
  if (title.trim().length < 2) return null;
  final store = ref.read(localStoreProvider);
  final key = coverKeyOf(title);
  final dir = Directory(p.join(ref.read(documentsDirProvider), 'covers'));
  final file = File(p.join(dir.path, '$key.jpg'));

  final known = await store.get('cover:$key');
  if (known == 'file' && file.existsSync()) return file;
  if (known != null && known.startsWith('none:')) {
    final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(known.substring(5)) ?? 0);
    if (DateTime.now().difference(at) < _retryMissAfter) return null;
  }

  try {
    final url = await ref.read(apiClientProvider).coverUrl(title: title);
    if (url == null) {
      await store.set('cover:$key', 'none:${DateTime.now().millisecondsSinceEpoch}');
      return null;
    }
    await dir.create(recursive: true);
    final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 15)));
    final bytes = res.data;
    // Open Library answers a missing image with a 1-pixel placeholder.
    if (bytes == null || bytes.length < 2000) {
      await store.set('cover:$key', 'none:${DateTime.now().millisecondsSinceEpoch}');
      return null;
    }
    await file.writeAsBytes(bytes, flush: true);
    await store.set('cover:$key', 'file');
    return file;
  } on ApiFailure {
    return null; // offline or the server is down: try again next time
  } on DioException {
    return null;
  } on FileSystemException catch (e) {
    debugPrint('cover save failed: $e');
    return null;
  }
});
