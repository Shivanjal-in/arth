// A book's highlights, in reading order: tap to jump, trash to remove.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/reader/highlights/highlight_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showHighlightsSheet(
  BuildContext context, {
  required int bookId,
  required String Function(Highlight h) locationOf,
  required void Function(Highlight h) onJump,
  required String emptyText,
}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => _HighlightsList(
          bookId: bookId,
          scroll: scroll,
          locationOf: locationOf,
          emptyText: emptyText,
          onJump: (h) {
            Navigator.pop(ctx);
            onJump(h);
          },
        ),
      ),
    );

class _HighlightsList extends ConsumerWidget {
  const _HighlightsList({
    required this.bookId,
    required this.scroll,
    required this.locationOf,
    required this.onJump,
    required this.emptyText,
  });

  final int bookId;
  final ScrollController scroll;
  final String Function(Highlight h) locationOf;
  final void Function(Highlight h) onJump;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final items = ref.watch(highlightsProvider(bookId)).valueOrNull ?? const <Highlight>[];
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      itemCount: items.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: items.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.highlights, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
                      const SizedBox(height: 12),
                      Text(emptyText, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                    ],
                  )
                : Text(t.highlights, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
          );
        }
        final h = items[i - 1];
        return ListTile(
          onTap: () => onJump(h),
          leading: Container(
            width: 6,
            height: 44,
            decoration: BoxDecoration(color: HighlightPalette.swatch(h.color), borderRadius: BorderRadius.circular(3)),
          ),
          title: Text(h.text, style: EnglishText.body(c.ink), maxLines: 3, overflow: TextOverflow.ellipsis),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(locationOf(h), style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13)),
          ),
          trailing: IconButton(
            tooltip: t.removeHighlight,
            icon: Icon(Icons.delete_outline_rounded, color: c.inkMuted),
            onPressed: () => unawaited(ref.read(highlightsProvider(bookId).notifier).remove(h.id)),
          ),
        );
      },
    );
  }
}
