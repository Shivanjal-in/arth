// The Community tab: recaps other readers have shared, newest or most
// loved first, searchable by book. Each one is shown as its book (the same
// block-print cover the reader's own library would give it), who made it,
// and a glimpse of three cards.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/community.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/account/account_card.dart';
import 'package:arth/features/cards/card_face.dart';
import 'package:arth/features/community/community_lock.dart';
import 'package:arth/features/library/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "5m", "3h", "2d", or a date.
String ago(DateTime at, AppStrings t) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return t.justNow;
  if (d.inHours < 1) return t.minutesAgo(d.inMinutes);
  if (d.inDays < 1) return t.hoursAgo(d.inHours);
  if (d.inDays < 30) return t.daysAgo(d.inDays);
  return '${at.day}/${at.month}/${at.year}';
}

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _sort = 'recent';
  final List<PublishedDeckSummary> _decks = [];
  bool _loading = false;
  bool _more = true;
  int _page = 0;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) unawaited(_load());
    });
    if (ref.read(communityAccessProvider) == CommunityAccess.open) unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _generation++;
      _page = 0;
      _more = true;
      _decks.clear();
      _error = null;
      _loading = false;
    }
    if (_loading || !_more) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref.read(apiClientProvider).communityDecks(sort: _sort, query: _search.text, page: _page);
      if (!mounted || gen != _generation) return;
      setState(() {
        _decks.addAll(page.decks);
        _more = page.more;
        _page++;
        _loading = false;
      });
    } on ApiFailure catch (e) {
      if (!mounted || gen != _generation) return;
      // The plan changed under us: refresh the account and the lock shows.
      if (e.code == 'NEEDS_PLAN' || e.code == 'UNAUTHORIZED') ref.invalidate(accountProvider);
      setState(() {
        _error = ref.read(stringsProvider).errorFor(e.code, e.message);
        _loading = false;
      });
    }
  }

  /// Coming back from a recap: its likes, saves and comments may have moved,
  /// or it may be gone.
  Future<void> _refreshOne(String id) async {
    try {
      final fresh = await ref.read(apiClientProvider).communityDeck(id);
      if (!mounted) return;
      setState(() {
        final i = _decks.indexWhere((d) => d.id == id);
        if (fresh.removed) {
          _decks.removeWhere((d) => d.id == id);
        } else if (i >= 0) {
          _decks[i] = fresh.summary;
        }
      });
    } on ApiFailure catch (e) {
      if (mounted && e.code == 'NOT_FOUND') setState(() => _decks.removeWhere((d) => d.id == id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    // Signing in or upgrading opens the community: load it then.
    ref.listen(communityAccessProvider, (was, now) {
      if (now == CommunityAccess.open && was != CommunityAccess.open) unawaited(_load(reset: true));
    });
    final access = ref.watch(communityAccessProvider);
    final appBar = AppBar(
      title: Text(t.communityTitle, style: uiTitle(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 26)),
      toolbarHeight: 64,
    );
    if (access == CommunityAccess.loading) return Scaffold(appBar: appBar, body: const Center(child: CircularProgressIndicator()));
    if (access == CommunityAccess.locked) return Scaffold(appBar: appBar, body: const CommunityLock());
    return Scaffold(
      appBar: appBar,
      body: RefreshIndicator(
        color: c.accent,
        onRefresh: () => _load(reset: true),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            Text(t.communityIntro, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              style: EnglishText.body(c.ink, size: 16),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => unawaited(_load(reset: true)));
              },
              decoration: InputDecoration(
                hintText: t.searchBooks,
                hintStyle: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 15),
                prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
                filled: true,
                fillColor: c.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (value, label) in [('recent', t.sortRecent), ('popular', t.sortPopular)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: uiLabel(hindi: t.isHindi, color: _sort == value ? c.onAccent : c.ink, scale: scale)),
                      selected: _sort == value,
                      showCheckmark: false,
                      selectedColor: c.ink,
                      backgroundColor: c.card,
                      side: BorderSide(color: _sort == value ? c.ink : c.rule),
                      onSelected: (_) {
                        if (_sort == value) return;
                        Haptics.choose();
                        setState(() => _sort = value);
                        unawaited(_load(reset: true));
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            for (final d in _decks)
              Padding(padding: const EdgeInsets.only(bottom: 14), child: PublishedDeckTile(deck: d, onReturn: () => _refreshOne(d.id))),
            if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (!_loading && _error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(_error!, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale), textAlign: TextAlign.center),
                    TextButton(onPressed: () => _load(reset: true), child: Text(t.retry)),
                  ],
                ),
              ),
            if (!_loading && _error == null && _decks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.diversity_3_rounded, size: 48, color: c.rule),
                    const SizedBox(height: 12),
                    Text(
                      _search.text.trim().isEmpty ? t.communityEmpty : t.communityNoMatches,
                      style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale),
                      textAlign: TextAlign.center,
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

/// A shared recap in a list: its book, whose it is, a glimpse of its cards.
class PublishedDeckTile extends ConsumerWidget {
  const PublishedDeckTile({required this.deck, super.key, this.showAuthor = true, this.onReturn});

  final PublishedDeckSummary deck;
  final bool showAuthor;

  /// Called once the reader comes back from the recap's page.
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final small = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 12.5);
    return Pressable(
      onTap: () async {
        await context.push('/community/deck/${deck.id}');
        onReturn?.call();
      },
      scale: 0.985,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.card, border: Border.all(color: c.ink, width: 2), boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(4, 4))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCover(title: deck.bookTitle, width: 52, elevation: 0.7),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deck.bookTitle, style: EnglishText.word(c.ink, size: 19), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (deck.title.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(deck.title, style: EnglishText.italic(c.inkMuted, size: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      if (showAuthor) ...[
                        const SizedBox(height: 8),
                        AuthorLine(author: deck.author, trailing: ago(deck.createdAt, t)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final p in deck.preview)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Icon(kindIcon(p.kind), size: 15, color: kindColor(p.kind, c)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.kind == CardKind.quote ? '“${p.front}”' : p.front,
                        style: cardStyle(p.front, deck.font, color: c.ink, scale: scale, size: 14.5, italic: p.kind == CardKind.quote),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(t.cardCount(deck.cardCount), style: small),
                const Spacer(),
                Icon(deck.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 16, color: deck.liked ? c.accent : c.inkMuted),
                const SizedBox(width: 4),
                Text('${deck.likes}', style: small),
                const SizedBox(width: 14),
                Icon(Icons.bookmark_added_outlined, size: 16, color: c.inkMuted),
                const SizedBox(width: 4),
                Text('${deck.saves}', style: small),
                const SizedBox(width: 14),
                Icon(Icons.mode_comment_outlined, size: 16, color: c.inkMuted),
                const SizedBox(width: 4),
                Text('${deck.comments}', style: small),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small avatar, the name, a plan badge for paid readers, and a time.
class AuthorLine extends ConsumerWidget {
  const AuthorLine({required this.author, super.key, this.trailing, this.size = 22});

  final Author author;
  final String? trailing;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final name = author.name.isEmpty ? 'Reader' : author.name;
    return Row(
      children: [
        Avatar(name: name, url: author.photoUrl, size: size),
        const SizedBox(width: 8),
        Flexible(child: Text(name, style: EnglishText.label(c.ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (author.tier != Tier.free) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: c.marigold.withValues(alpha: 0.16), border: Border.all(color: c.ink, width: 1.5)),
            child: Text(tierLabel(author.tier, t), style: EnglishText.label(c.ink, size: 10.5)),
          ),
        ],
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text('·  $trailing', style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 12)),
        ],
      ],
    );
  }
}
