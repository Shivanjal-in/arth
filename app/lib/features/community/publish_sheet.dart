// Sharing a recap: from a book's recap, a Pro or Super reader picks which
// cards to share, adds an optional title and line, and publishes. Signed-out
// and Free readers are told what it takes instead.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/community.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/plans/paid_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Starts sharing [cards] of [bookTitle]; handles every "you can't yet" case.
Future<void> shareRecap(BuildContext context, WidgetRef ref, {required String bookTitle, required String? bookKey, required List<Flashcard> cards}) async {
  final t = ref.read(stringsProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (ref.read(signedInUidProvider) == null) {
    messenger?.showSnackBar(SnackBar(content: Text(t.signInToShare), persist: false, action: SnackBarAction(label: t.signIn, onPressed: () => context.push('/signin'))));
    return;
  }
  if (!await ensurePaid(context, ref, title: t.shareToCommunity, why: t.publishNeedsPlan)) return;
  if (!context.mounted) return;
  final id = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _PublishSheet(bookTitle: bookTitle, bookKey: bookKey, cards: cards),
  );
  if (id != null && context.mounted) {
    messenger?.showSnackBar(
      SnackBar(content: Text(t.published), persist: false, action: SnackBarAction(label: t.openMyCopy, onPressed: () => context.push('/community/deck/$id'))),
    );
  }
}

class _PublishSheet extends ConsumerStatefulWidget {
  const _PublishSheet({required this.bookTitle, required this.bookKey, required this.cards});

  final String bookTitle;
  final String? bookKey;
  final List<Flashcard> cards;

  @override
  ConsumerState<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends ConsumerState<_PublishSheet> {
  final _title = TextEditingController();
  final _blurb = TextEditingController();
  late final Set<String> _chosen = {for (final c in widget.cards) c.id};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _blurb.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(apiClientProvider).publishDeck(
            bookTitle: widget.bookTitle,
            bookKey: widget.bookKey,
            title: _title.text.trim(),
            blurb: _blurb.text.trim(),
            font: ref.read(settingsProvider).cardFont.name,
            cards: [for (final c in widget.cards) if (_chosen.contains(c.id)) DeckCard.of(c)],
          );
      Haptics.commit();
      if (mounted) Navigator.pop(context, id);
    } on ApiFailure catch (e) {
      final t = ref.read(stringsProvider);
      if (mounted) setState(() => _error = e.code == 'FORBIDDEN' ? t.bannedNotice : t.errorFor(e.code, e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final label = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: c.rule, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Text(t.shareTitle, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale))),
                      IconButton(
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                        icon: Icon(Icons.close_rounded, color: c.inkMuted),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(widget.bookTitle, style: EnglishText.italic(c.inkMuted, size: 15)),
                  const SizedBox(height: 8),
                  Text(t.shareIntro, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14)),
                  const SizedBox(height: 16),
                  TextField(controller: _title, maxLength: 120, style: EnglishText.body(c.ink, size: 17), decoration: InputDecoration(hintText: t.recapTitleHint, counterText: '')),
                  const SizedBox(height: 10),
                  TextField(controller: _blurb, maxLength: 600, minLines: 1, maxLines: 4, style: EnglishText.body(c.ink), decoration: InputDecoration(hintText: t.blurbHint, counterText: '')),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Text(t.cardsChosen(_chosen.length, widget.cards.length), style: label)),
                      TextButton(onPressed: () => setState(() => _chosen.addAll(widget.cards.map((c) => c.id))), child: Text(t.selectAll)),
                      TextButton(onPressed: () => setState(_chosen.clear), child: Text(t.selectNone)),
                    ],
                  ),
                  for (final card in widget.cards)
                    CheckboxListTile(
                      value: _chosen.contains(card.id),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: c.accent,
                      onChanged: (v) {
                        Haptics.choose();
                        setState(() => v == true ? _chosen.add(card.id) : _chosen.remove(card.id));
                      },
                      title: Text(card.front, style: scriptStyle(card.front, color: c.ink, scale: scale, size: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Row(
                        children: [
                          Icon(kindIcon(card.kind), size: 14, color: kindColor(card.kind, c)),
                          const SizedBox(width: 6),
                          Flexible(child: Text(card.location ?? kindLabel(card.kind, t), style: EnglishText.label(c.inkMuted, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: uiBody(hindi: t.isHindi, color: c.accent, scale: scale, size: 14))),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || _chosen.isEmpty ? null : _publish,
                    icon: const Icon(Icons.public_rounded, size: 20),
                    label: Text(t.publish),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
