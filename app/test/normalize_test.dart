import 'dart:convert';
import 'dart:io';

import 'package:arth/core/normalize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('../contracts/normalize-vectors.json');
  final vectors =
      (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['vectors']
          as List<dynamic>;

  test('vector file is not truncated', () {
    expect(vectors.length, greaterThanOrEqualTo(40));
  });

  for (final raw in vectors) {
    final v = raw as Map<String, dynamic>;
    test('normalize vector ${v['id']}', () {
      final expected = v['expected'] as String;
      switch (v['kind']) {
        case 'sentence':
          expect(normalizeSentence(v['input'] as String), expected);
        case 'word':
          expect(normalizeWord(v['input'] as String), expected);
        case 'key':
          if (v['keyKind'] == 'context') {
            expect(
              contextKey(v['word'] as String, v['sentence'] as String),
              expected,
            );
          } else {
            expect(sentenceKey(v['text'] as String), expected);
          }
        default:
          fail('unknown vector kind ${v['kind']}');
      }
    });
  }
}
