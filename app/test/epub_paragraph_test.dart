import 'package:arth/features/epub/epub_paragraph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = GlobalKey();
  Future<RenderParagraphBlock> pump(WidgetTester tester, String text, {double width = 200}) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ParagraphText(
              key: key,
              span: TextSpan(text: text, style: const TextStyle(fontSize: 20)),
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      ),
    );
    return key.currentContext!.findRenderObject()! as RenderParagraphBlock;
  }

  testWidgets('sizes to the wrapped text and indexes words with rects', (tester) async {
    final r = await pump(tester, 'It is a truth universally acknowledged, that a single man');
    expect(r.size.width, 200);
    expect(r.size.height, greaterThan(40), reason: 'wrapped onto several lines');
    final idx = r.index;
    expect(idx.words.map((w) => w.text).take(3), ['It', 'is', 'a']);
    expect(idx.words.every((w) => !w.rect.isEmpty), isTrue);
    // A word on a later line sits lower than the first.
    expect(idx.words.last.rect.top, greaterThan(idx.words.first.rect.bottom - 1));
    // Hit-testing the first word's centre finds it.
    expect(idx.wordAt(idx.words.first.rect.center)?.text, 'It');
  });

  testWidgets('a word broken across lines is not one column-wide rect', (tester) async {
    final r = await pump(tester, 'supercalifragilisticexpialidocious', width: 120);
    final idx = r.index;
    expect(idx.words.single.rect.height, greaterThan(30), reason: 'union spans both lines');
    // Per-character rects, so the highlight of the run follows the break.
    expect(idx.words.single.rect.width, lessThanOrEqualTo(120));
  });

  testWidgets('index is rebuilt after a relayout', (tester) async {
    final r = await pump(tester, 'one two three four five six seven eight nine ten');
    final before = r.index;
    await pump(tester, 'one two three four five six seven eight nine ten', width: 400);
    expect(identical(r.index, before), isFalse);
    expect(r.index.words.last.rect.top, lessThan(before.words.last.rect.top), reason: 'fewer lines when wider');
  });
}
