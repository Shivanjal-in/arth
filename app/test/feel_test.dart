import 'package:arth/app/feel.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: ThemeData(extensions: const [ArthColors.light]),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _opacity(WidgetTester t, Finder of) => t.widget<Opacity>(find.ancestor(of: of, matching: find.byType(Opacity)).first).opacity;

void main() {
  setUp(() => Haptics.enabled = false);

  testWidgets('Pressable sinks while held and springs back', (t) async {
    var taps = 0;
    await t.pumpWidget(_app(Pressable(onTap: () => taps++, child: const SizedBox(width: 100, height: 60, child: Text('book')))));
    double scale() => t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1);
    final gesture = await t.startGesture(t.getCenter(find.text('book')));
    await t.pump();
    expect(scale(), 0.97);
    await gesture.up();
    await t.pumpAndSettle();
    expect(scale(), 1);
    expect(taps, 1);
  });

  testWidgets('SettleIn waits for its turn, then fades and rises in', (t) async {
    await t.pumpWidget(_app(const SettleIn(delay: Duration(milliseconds: 110), child: Text('cover'))));
    expect(_opacity(t, find.text('cover')), 0);
    await t.pump(const Duration(milliseconds: 100));
    expect(_opacity(t, find.text('cover')), 0, reason: 'still waiting its turn');
    await t.pump(const Duration(milliseconds: 20));
    await t.pump(const Duration(milliseconds: 120));
    final mid = _opacity(t, find.text('cover'));
    expect(mid, inExclusiveRange(0, 1), reason: 'mid-way through the arrival');
    await t.pumpAndSettle();
    expect(_opacity(t, find.text('cover')), 1);
  });

  testWidgets('SettleIn is instant with reduced motion', (t) async {
    await t.pumpWidget(_app(const SettleIn(delay: Duration(milliseconds: 300), child: Text('cover')), reduceMotion: true));
    await t.pump();
    expect(_opacity(t, find.text('cover')), 1);
  });

  testWidgets('ReadingBar fills from empty to its value', (t) async {
    await t.pumpWidget(_app(const SizedBox(width: 200, child: ReadingBar(value: 0.6))));
    double v() => t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value!;
    expect(v(), 0);
    await t.pump(const Duration(milliseconds: 200));
    expect(v(), inExclusiveRange(0, 0.6));
    await t.pumpAndSettle();
    expect(v(), closeTo(0.6, 1e-9));
  });

  test('a title always gets the same dye and motif', () {
    expect(stableHash('Godan'), stableHash('Godan'));
    expect(coverInk('Godan'), coverInk('Godan'));
    expect(motifOf('Godan'), motifOf('Godan'));
    // Across a shelf of titles, every motif shows up.
    final motifs = {for (final title in ['Godan', 'The Guide', 'Emma', 'Persuasion', 'Nirmala', 'Malgudi Days', 'Gitanjali', 'Kim']) motifOf(title)};
    expect(motifs, BlockMotif.values.toSet());
  });
}
