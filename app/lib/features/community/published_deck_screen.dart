// A shared recap: the book's dye and motif across the top as on the
// reader's own recap, who made it, like and save, every card, and the
// conversation under it (one level of replies).

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/community.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/community/community_lock.dart';
import 'package:arth/features/community/community_screen.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class PublishedDeckScreen extends ConsumerStatefulWidget {
  const PublishedDeckScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<PublishedDeckScreen> createState() => _PublishedDeckScreenState();
}

class _PublishedDeckScreenState extends ConsumerState<PublishedDeckScreen> {
  PublishedDeck? _deck;
  String? _error;
  bool _liked = false;
  int _likes = 0;
  int _saves = 0;
  bool _saving = false;
  bool _savedHere = false;
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  CommunityComment? _replyTo;
  bool _sending = false;

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _comment.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _api.communityDeck(widget.id);
      if (!mounted) return;
      setState(() {
        _deck = d;
        _liked = d.summary.liked;
        _likes = d.summary.likes;
        _saves = d.summary.saves;
        _error = null;
      });
    } on ApiFailure catch (e) {
      if (e.code == 'NEEDS_PLAN' || e.code == 'UNAUTHORIZED') ref.invalidate(accountProvider);
      if (mounted) setState(() => _error = ref.read(stringsProvider).errorFor(e.code, e.message));
    }
  }

  void _snack(String text, {SnackBarAction? action}) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), action: action, persist: false));

  bool get _signedIn => ref.read(signedInUidProvider) != null;

  /// Signed out: explain, and offer sign-in. True when the action may go ahead.
  bool _requireSignIn() {
    if (_signedIn) return true;
    final t = ref.read(stringsProvider);
    _snack(t.signInToJoin, action: SnackBarAction(label: t.signIn, onPressed: () => context.push('/signin')));
    return false;
  }

  Future<void> _toggleLike() async {
    if (!_requireSignIn()) return;
    Haptics.choose();
    // Optimistic: the heart answers at once, the server confirms.
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    try {
      final r = await _api.toggleLike(widget.id);
      if (mounted) {
        setState(() {
          _liked = r.liked;
          _likes = r.likes;
        });
      }
    } on ApiFailure {
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likes += _liked ? 1 : -1;
        });
      }
    }
  }

  Future<void> _save() async {
    final d = _deck;
    if (d == null || _saving || !_requireSignIn()) return;
    final t = ref.read(stringsProvider);
    setState(() => _saving = true);
    try {
      final n = await ref.read(cardsProvider).saveDeck(
            bookTitle: d.summary.bookTitle,
            bookKey: d.bookKey,
            cards: [for (final c in d.cards) (kind: c.kind, front: c.front, back: c.back, note: c.note, location: c.location)],
          );
      Haptics.commit();
      final saves = await _api.markSaved(widget.id);
      if (!mounted) return;
      setState(() {
        _saves = saves;
        _savedHere = true;
      });
      _snack(t.savedCards(n), action: SnackBarAction(label: t.openMyCopy, onPressed: () => context.push('/cards')));
    } on ApiFailure catch (e) {
      if (mounted) _snack(t.errorFor(e.code, e.message));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending || !_requireSignIn()) return;
    final t = ref.read(stringsProvider);
    setState(() => _sending = true);
    try {
      await _api.addComment(widget.id, text, parentId: _replyTo?.id);
      Haptics.commit();
      _comment.clear();
      _commentFocus.unfocus();
      setState(() => _replyTo = null);
      await _load();
    } on ApiFailure catch (e) {
      if (mounted) _snack(e.code == 'FORBIDDEN' ? t.bannedNotice : t.errorFor(e.code, e.message));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report(String kind, String targetId) async {
    if (!_requireSignIn()) return;
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(t.reportTitle, style: uiHeading(hindi: t.isHindi, color: c.ink)),
        content: TextField(controller: reason, maxLength: 300, decoration: InputDecoration(hintText: t.reportHint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.report)),
        ],
      ),
    );
    final why = reason.text;
    reason.dispose();
    if (ok != true) return;
    try {
      await _api.report(kind: kind, targetId: targetId, reason: why);
      if (mounted) _snack(t.reported);
    } on ApiFailure catch (e) {
      if (mounted) _snack(t.errorFor(e.code, e.message));
    }
  }

  Future<void> _deleteComment(String id) async {
    try {
      await _api.deleteComment(id);
      await _load();
    } on ApiFailure catch (e) {
      if (mounted) _snack(ref.read(stringsProvider).errorFor(e.code, e.message));
    }
  }

  Future<void> _deleteDeck() async {
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        content: Text(t.deleteDeckConfirm, style: uiBody(hindi: t.isHindi, color: c.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deletePublishedDeck(widget.id);
      if (!mounted) return;
      _snack(t.deleted);
      unawaited(Navigator.of(context).maybePop());
    } on ApiFailure catch (e) {
      if (mounted) _snack(t.errorFor(e.code, e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final d = _deck;
    // Opened from a notification or a link without a plan: say what it takes.
    ref.listen(communityAccessProvider, (was, now) {
      if (now == CommunityAccess.open && was != CommunityAccess.open && _deck == null) unawaited(_load());
    });
    final access = ref.watch(communityAccessProvider);
    if (access == CommunityAccess.locked) return Scaffold(appBar: AppBar(), body: const CommunityLock());
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(padding: const EdgeInsets.all(32), child: Text(_error!, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale), textAlign: TextAlign.center)),
        ),
      );
    }
    final s = d.summary;
    final ink = coverInk(s.bookTitle);
    final onInk = Colors.white.withValues(alpha: 0.94);
    final soft = Colors.white.withValues(alpha: 0.74);
    final isAdmin = ref.watch(accountProvider).valueOrNull?.isAdmin ?? false;
    final top = [for (final x in d.comments) if (x.parentId == null) x];
    List<CommunityComment> repliesTo(String id) => [for (final x in d.comments) if (x.parentId == id) x];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 250,
            backgroundColor: ink,
            foregroundColor: Colors.white,
            actions: [
              PopupMenuButton<String>(
                iconColor: Colors.white,
                color: c.card,
                onSelected: (v) => switch (v) {
                  'delete' => unawaited(_deleteDeck()),
                  _ => unawaited(_report('deck', widget.id)),
                },
                itemBuilder: (_) => [
                  if (d.mine || isAdmin) PopupMenuItem(value: 'delete', child: Text(t.delete)),
                  if (!d.mine) PopupMenuItem(value: 'report', child: Text(t.report)),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [ink, Color.lerp(ink, Colors.black, 0.35)!])),
                child: Stack(
                  children: [
                    Positioned.fill(child: BlockPrintTexture(title: s.bookTitle, cell: 58, opacity: 0.065)),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 64, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(s.bookTitle, style: EnglishText.title(onInk, size: 30), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (s.title.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(s.title, style: EnglishText.italic(soft, size: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 12),
                            DefaultTextStyle.merge(
                              style: TextStyle(color: onInk),
                              child: Theme(
                                data: Theme.of(context).copyWith(extensions: [c.copyWith(ink: onInk, inkMuted: soft)]),
                                child: AuthorLine(author: s.author, trailing: ago(s.createdAt, t), size: 26),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.hidden)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: Text(t.heldForReview, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14)),
                    ),
                  if (s.blurb.isNotEmpty) ...[
                    Text(s.blurb, style: EnglishText.body(c.ink, size: 16)),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      _Action(
                        icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: _liked ? c.accent : c.ink,
                        label: '$_likes',
                        onTap: _toggleLike,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: Icon(_savedHere ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined, size: 20),
                          label: Text(t.saveToMyCards),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${t.cardCount(s.cardCount)}  ·  ${t.savesCount(_saves)}',
                    style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: d.cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => CardTile(card: d.cards[i].asFlashcard(i), showLocation: true, font: d.summary.font),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
              child: Row(
                children: [
                  Text(t.comments, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
                  const SizedBox(width: 8),
                  Text('${d.comments.length}', style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                ],
              ),
            ),
          ),
          if (top.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(t.noComments, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14.5)),
              ),
            ),
          SliverList.list(
            children: [
              for (final x in top) ...[
                _CommentView(
                  comment: x,
                  canDelete: x.mine || d.mine || isAdmin,
                  onReply: () {
                    if (!_requireSignIn()) return;
                    setState(() => _replyTo = x);
                    _commentFocus.requestFocus();
                  },
                  onDelete: () => _deleteComment(x.id),
                  onReport: () => _report('comment', x.id),
                ),
                for (final r in repliesTo(x.id))
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: _CommentView(
                      comment: r,
                      canDelete: r.mine || d.mine || isAdmin,
                      onReply: () {
                        if (!_requireSignIn()) return;
                        setState(() => _replyTo = x);
                        _commentFocus.requestFocus();
                      },
                      onDelete: () => _deleteComment(r.id),
                      onReport: () => _report('comment', r.id),
                    ),
                  ),
              ],
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      bottomNavigationBar: _composer(context),
    );
  }

  Widget _composer(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final signedIn = ref.watch(signedInUidProvider) != null;
    return Container(
      decoration: BoxDecoration(color: c.paper, border: Border(top: BorderSide(color: c.rule))),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: !signedIn
              ? Row(
                  children: [
                    Expanded(child: Text(t.signInToJoin, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14))),
                    TextButton(onPressed: () => context.push('/signin'), child: Text(t.signIn)),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_replyTo != null)
                      Row(
                        children: [
                          Icon(Icons.reply_rounded, size: 16, color: c.inkMuted),
                          const SizedBox(width: 6),
                          Expanded(child: Text(t.replyingTo(_replyTo!.author.name), style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13))),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close_rounded, size: 18, color: c.inkMuted),
                            onPressed: () => setState(() => _replyTo = null),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _comment,
                            focusNode: _commentFocus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1000,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => setState(() {}),
                            style: scriptStyle(_comment.text, color: c.ink, scale: scale, size: 15),
                            decoration: InputDecoration(
                              hintText: t.writeComment,
                              hintStyle: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14.5),
                              counterText: '',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: t.send,
                          onPressed: _comment.text.trim().isEmpty || _sending ? null : _sendComment,
                          icon: Icon(Icons.send_rounded, color: _comment.text.trim().isEmpty ? c.rule : c.accent),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      haptic: null,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.rule)),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: Motion.of(context, Motion.quick),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(icon, key: ValueKey(icon), color: color, size: 22),
            ),
            const SizedBox(width: 8),
            Text(label, style: EnglishText.label(c.ink, size: 15)),
          ],
        ),
      ),
    );
  }
}

class _CommentView extends ConsumerWidget {
  const _CommentView({required this.comment, required this.canDelete, required this.onReply, required this.onDelete, required this.onReport});

  final CommunityComment comment;
  final bool canDelete;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final link = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale).copyWith(fontSize: 12.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Opacity(
        opacity: comment.hidden ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuthorLine(author: comment.author, trailing: ago(comment.createdAt, t)),
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comment.text, style: scriptStyle(comment.text, color: c.ink, scale: scale, size: 15)),
                  if (comment.hidden) Text(t.heldForReview, style: uiBody(hindi: t.isHindi, color: c.accent, scale: scale, size: 12)),
                  Row(
                    children: [
                      TextButton(onPressed: onReply, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)), child: Text(t.reply, style: link)),
                      const SizedBox(width: 12),
                      if (canDelete)
                        TextButton(onPressed: onDelete, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)), child: Text(t.delete, style: link))
                      else
                        TextButton(onPressed: onReport, style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)), child: Text(t.report, style: link)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
