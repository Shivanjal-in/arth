// The sheet a card is written in. Opened from the reader with a draft (the
// word and its meaning, the sentence and its translation, or a blank note
// anchored to the current page), or from a deck to edit a card.

import 'dart:async';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A card not yet saved, with where in the book it's from.
class CardDraft {
  const CardDraft({
    required this.kind,
    this.front = '',
    this.back = '',
    this.note = '',
    this.context,
    this.bookId,
    this.bookTitle,
    this.page,
    this.block,
    this.location,
  });

  final CardKind kind;
  final String front;
  final String back;
  final String note;
  final String? context;
  final int? bookId;
  final String? bookTitle;
  final int? page;
  final int? block;
  final String? location;

  CardDraft at({required int? bookId, required String? bookTitle, required int? page, int? block, String? location}) => CardDraft(
        kind: kind,
        front: front,
        back: back,
        note: note,
        context: context,
        bookId: bookId,
        bookTitle: bookTitle,
        page: page,
        block: block,
        location: location,
      );
}

/// Opens the editor for a new card ([draft]) or an existing one
/// ([existing]). Resolves to the saved card, or null if dismissed.
Future<Flashcard?> showCardEditor(BuildContext context, {CardDraft? draft, Flashcard? existing}) {
  assert((draft == null) != (existing == null), 'pass a draft or a card');
  return showModalBottomSheet<Flashcard>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _CardEditor(draft: draft, existing: existing),
  );
}

class _CardEditor extends ConsumerStatefulWidget {
  const _CardEditor({this.draft, this.existing});

  final CardDraft? draft;
  final Flashcard? existing;

  @override
  ConsumerState<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends ConsumerState<_CardEditor> {
  late CardKind _kind = widget.existing?.kind ?? widget.draft!.kind;
  late final _front = TextEditingController(text: widget.existing?.front ?? widget.draft!.front);
  late final _back = TextEditingController(text: widget.existing?.back ?? widget.draft!.back);
  late final _note = TextEditingController(text: widget.existing?.note ?? widget.draft!.note);
  bool _saving = false;

  String? get _location => widget.existing?.location ?? widget.draft?.location;
  String? get _context => widget.existing?.context ?? widget.draft?.context;
  String get _bookTitle => widget.existing?.bookTitle ?? widget.draft?.bookTitle ?? '';

  @override
  void initState() {
    super.initState();
    // The fields' font follows the script typed (Hindi or English).
    for (final field in [_front, _back, _note]) {
      field.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_front.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    final cards = ref.read(cardsProvider);
    final existing = widget.existing;
    Flashcard saved;
    if (existing != null) {
      saved = existing.copyWith(kind: _kind, front: _front.text.trim(), back: _back.text.trim(), note: _note.text.trim());
      await cards.update(saved);
    } else {
      final d = widget.draft!;
      saved = await cards.add(
        kind: _kind,
        front: _front.text.trim(),
        back: _back.text.trim(),
        note: _note.text.trim(),
        context: d.context,
        bookId: d.bookId,
        bookTitle: d.bookTitle,
        page: d.page,
        block: d.block,
        location: d.location,
      );
    }
    Haptics.commit();
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final t = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final cards = ref.read(cardsProvider);
    await cards.delete(existing.id);
    if (mounted) Navigator.pop(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(t.cardDeleted),
        persist: false,
        action: SnackBarAction(label: t.undo, onPressed: () => unawaited(cards.update(existing))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final (frontHint, backHint) = switch (_kind) {
      CardKind.idea => (t.frontHintIdea, t.backHintIdea),
      CardKind.quote => (t.frontHintQuote, t.backHintQuote),
      CardKind.word => (t.frontHintWord, t.backHintWord),
    };
    final label = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale);
    InputDecoration field(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: uiBody(hindi: t.isHindi, color: c.inkMuted.withValues(alpha: 0.7), scale: scale, size: 16),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: c.rule, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existing == null ? t.newCard : t.editCard,
                    style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale),
                  ),
                ),
                if (widget.existing != null)
                  IconButton(
                    tooltip: t.deleteCard,
                    icon: Icon(Icons.delete_outline_rounded, color: c.inkMuted),
                    onPressed: _delete,
                  ),
                // The sheet can fill the screen with the keyboard up, leaving
                // nothing to tap outside it.
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: Icon(Icons.close_rounded, color: c.inkMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (_bookTitle.isNotEmpty || _location != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: deckInk(_bookTitle), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [if (_bookTitle.isNotEmpty) _bookTitle, ?_location].join('  ·  '),
                        style: EnglishText.label(c.inkMuted, size: 12.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final k in CardKind.values) ...[
                  Expanded(
                    child: _KindChip(
                      kind: k,
                      selected: k == _kind,
                      onTap: () {
                        if (k != _kind) Haptics.choose();
                        setState(() => _kind = k);
                      },
                    ),
                  ),
                  if (k != CardKind.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Text(t.cardFront, style: label),
            TextField(
              controller: _front,
              autofocus: widget.existing == null && widget.draft!.front.isEmpty,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: scriptStyle(_front.text, color: c.ink, scale: scale, size: 18, italic: _kind == CardKind.quote),
              decoration: field(frontHint),
            ),
            const SizedBox(height: 14),
            Text(t.cardBack, style: label),
            TextField(
              controller: _back,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              style: scriptStyle(_back.text, color: c.ink, scale: scale, size: 17),
              decoration: field(backHint),
            ),
            const SizedBox(height: 14),
            Text(t.cardNote, style: label),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              style: scriptStyle(_note.text, color: c.ink, scale: scale, italic: true),
              decoration: field(t.noteHint),
            ),
            if (_context != null && _kind != CardKind.quote) ...[
              const SizedBox(height: 16),
              Text(t.fromTheBook, style: label),
              const SizedBox(height: 4),
              Text(_context!, style: EnglishText.italic(c.inkMuted, size: 14), maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _front.text.trim().isEmpty || _saving ? null : _save,
                child: Text(t.saveCard, style: uiLabel(hindi: t.isHindi, color: c.onAccent, scale: scale).copyWith(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends ConsumerWidget {
  const _KindChip({required this.kind, required this.selected, required this.onTap});

  final CardKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final tint = kindColor(kind, c);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? tint.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? tint : c.rule, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(kindIcon(kind), size: 20, color: selected ? tint : c.inkMuted),
              const SizedBox(height: 4),
              Text(kindLabel(kind, t), style: uiLabel(hindi: t.isHindi, color: selected ? c.ink : c.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
