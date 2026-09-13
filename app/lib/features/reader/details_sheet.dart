// Full-details bottom sheet: DraggableScrollableSheet snapping at 0.55 / 0.92.

import 'package:arth/app/theme.dart';
import 'package:arth/core/models/contracts.dart';
import 'package:arth/features/dictionary/entry_widgets.dart';
import 'package:flutter/material.dart';

Future<void> showEntryDetailsSheet(
  BuildContext context, {
  required DictionaryEntry entry,
  ContextResult? contextResult,
  bool contextLoading = false,
  String? sentence,
  int? bookId,
  String? bookTitle,
  ValueChanged<String>? onTapWord,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.55, 0.92],
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: ctx.colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const _GrabHandle(),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                child: EntryDetails(
                  entry: entry,
                  context: contextResult,
                  contextLoading: contextLoading,
                  sentence: sentence,
                  bookId: bookId,
                  bookTitle: bookTitle,
                  onTapWord: onTapWord == null
                      ? null
                      : (w) {
                          Navigator.of(ctx).pop();
                          onTapWord(w);
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.colors.rule,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}
