// "Go to page": the page counter in a reader's header opens this. Type a
// number, or drag the slider for a long book; Go jumps there.

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The page to go to (1-based), or null if cancelled.
Future<int?> showGoToPage(BuildContext context, {required int current, required int count}) =>
    showDialog<int>(context: context, builder: (_) => _GoToPage(current: current, count: count));

/// The page counter, tappable to open [showGoToPage].
class PageCounter extends StatelessWidget {
  const PageCounter({required this.page, required this.count, required this.onGo, super.key, this.tooltip});

  final int page;

  /// Null while the document is still opening.
  final int? count;
  final ValueChanged<int> onGo;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = count;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: total == null
            ? null
            : () async {
                Haptics.open();
                final to = await showGoToPage(context, current: page, count: total);
                if (to != null) onGo(to);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            '$page / ${total ?? '…'}',
            style: EnglishText.label(c.inkMuted).copyWith(decoration: TextDecoration.underline, decorationColor: c.rule),
          ),
        ),
      ),
    );
  }
}

class _GoToPage extends ConsumerStatefulWidget {
  const _GoToPage({required this.current, required this.count});

  final int current;
  final int count;

  @override
  ConsumerState<_GoToPage> createState() => _GoToPageState();
}

class _GoToPageState extends ConsumerState<_GoToPage> {
  late final _field = TextEditingController(text: '${widget.current}')
    ..selection = TextSelection(baseOffset: 0, extentOffset: '${widget.current}'.length);
  late double _slider = widget.current.toDouble();

  int? get _page {
    final n = int.tryParse(_field.text.trim());
    return n != null && n >= 1 && n <= widget.count ? n : null;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _go() {
    final page = _page;
    if (page == null) return;
    Haptics.commit();
    Navigator.pop(context, page);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final valid = _page != null;
    return AlertDialog(
      title: Text(t.goToPage, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: EnglishText.word(c.ink, size: 24),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              helperText: t.pageRange(widget.count),
              errorText: _field.text.isEmpty || valid ? null : t.pageRange(widget.count),
            ),
            onChanged: (_) => setState(() {
              final p = _page;
              if (p != null) _slider = p.toDouble();
            }),
            onSubmitted: (_) => _go(),
          ),
          if (widget.count > 1) ...[
            const SizedBox(height: 12),
            Slider(
              value: _slider.clamp(1, widget.count.toDouble()),
              min: 1,
              max: widget.count.toDouble(),
              activeColor: c.accent,
              onChanged: (v) => setState(() {
                _slider = v;
                _field.text = '${v.round()}';
              }),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: valid ? _go : null, child: Text(t.go)),
      ],
    );
  }
}
