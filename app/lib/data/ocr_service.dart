// On-device OCR (Google ML Kit, Latin script). Results are cached as JSON
// beside the image so a page is recognised once.

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:arth/core/text/page_text_index.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// One OCR'd page: lines of words with boxes in image pixel coordinates.
class OcrPage {
  const OcrPage({required this.width, required this.height, required this.lines});

  factory OcrPage.fromJson(Map<String, dynamic> j) => OcrPage(
        width: (j['w'] as num).toDouble(),
        height: (j['h'] as num).toDouble(),
        lines: [
          for (final line in j['lines'] as List<dynamic>)
            [
              for (final w in line as List<dynamic>)
                (
                  text: (w as Map<String, dynamic>)['t'] as String,
                  rect: Rect.fromLTRB(
                    (w['l'] as num).toDouble(),
                    (w['tp'] as num).toDouble(),
                    (w['r'] as num).toDouble(),
                    (w['b'] as num).toDouble(),
                  ),
                ),
            ],
        ],
      );

  final double width;
  final double height;
  final List<List<({String text, Rect rect})>> lines;

  int get wordCount => lines.fold(0, (n, l) => n + l.length);

  Map<String, dynamic> toJson() => {
        'w': width,
        'h': height,
        'lines': [
          for (final line in lines)
            [
              for (final w in line)
                {'t': w.text, 'l': w.rect.left, 'tp': w.rect.top, 'r': w.rect.right, 'b': w.rect.bottom},
            ],
        ],
      };

  PageTextIndex index() => PageTextIndex.fromLines(lines);
}

class OcrService {
  OcrService() : _recognizer = TextRecognizer();

  final TextRecognizer _recognizer;

  /// Recognises [imagePath]; reads/writes `<imagePath>.ocr.json` as a cache.
  Future<OcrPage> recognize(String imagePath, {required Size imageSize}) async {
    final cache = File('$imagePath.ocr.json');
    if (cache.existsSync()) {
      try {
        return OcrPage.fromJson(jsonDecode(await cache.readAsString()) as Map<String, dynamic>);
      } on Exception {
        // corrupt cache: recognise again
      }
    }
    final result = await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    final lines = <List<({String text, Rect rect})>>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final words = [
          for (final el in line.elements)
            if (el.text.trim().isNotEmpty) (text: el.text, rect: el.boundingBox),
        ];
        if (words.isNotEmpty) lines.add(words);
      }
    }
    // Reading order: ML Kit groups by block; sort lines top-to-bottom so the
    // reconstructed text follows the page.
    lines.sort((a, b) => a.first.rect.top.compareTo(b.first.rect.top));
    final page = OcrPage(width: imageSize.width, height: imageSize.height, lines: lines);
    await cache.writeAsString(jsonEncode(page.toJson()));
    return page;
  }

  Future<void> close() => _recognizer.close();
}
