// Admin tools, for accounts with the admin role: what readers reported
// (remove it, or keep it and clear the reports), readers (plan, ban), and a
// notification to everyone. The API checks the role on every call; hiding
// the screen from others is only a courtesy.

import 'dart:async';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/community.dart';
import 'package:arth/features/account/account_card.dart';
import 'package:arth/features/plans/plans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.adminTitle),
          bottom: TabBar(
            labelStyle: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 15),
            labelColor: c.ink,
            unselectedLabelColor: c.inkMuted,
            indicatorColor: c.accent,
            dividerColor: c.rule,
            tabs: [Tab(text: t.adminReports), Tab(text: t.adminReaders), Tab(text: t.adminBroadcast)],
          ),
        ),
        body: const TabBarView(children: [_Reports(), _Readers(), _Broadcast()]),
      ),
    );
  }
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

class _Reports extends ConsumerStatefulWidget {
  const _Reports();

  @override
  ConsumerState<_Reports> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<_Reports> {
  List<AdminReportItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiClientProvider).adminReports();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = ref.read(stringsProvider).errorFor(e.code, e.message));
    }
  }

  Future<void> _decide(AdminReportItem item, {required bool remove}) async {
    Haptics.commit();
    setState(() => _items = [for (final x in _items!) if (x.targetId != item.targetId) x]);
    try {
      await ref.read(apiClientProvider).moderate(kind: item.kind, targetId: item.targetId, remove: remove);
    } on ApiFailure catch (e) {
      if (mounted) _snack(context, ref.read(stringsProvider).errorFor(e.code, e.message));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final items = _items;
    if (items == null) return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!));
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                Icon(Icons.verified_outlined, size: 44, color: c.rule),
                const SizedBox(height: 10),
                Center(child: Text(t.noReports, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale))),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final r = items[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.card, border: Border.all(color: r.status == 'hidden' ? c.accent : c.ink, width: 2), boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(4, 4))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(r.kind == 'deck' ? Icons.style_outlined : Icons.mode_comment_outlined, size: 18, color: c.inkMuted),
                          const SizedBox(width: 6),
                          Text(r.kind == 'deck' ? t.kindDeck : t.kindComment, style: uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
                          const SizedBox(width: 8),
                          Text(t.reportsCount(r.count), style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale)),
                          if (r.status == 'hidden') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), border: Border.all(color: c.ink, width: 1.5)),
                              child: Text(t.hiddenBadge, style: EnglishText.label(c.accent, size: 11)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: r.deckId == null ? null : () => context.push('/community/deck/${r.deckId}'),
                        child: Text(r.preview, style: EnglishText.body(c.ink), maxLines: 4, overflow: TextOverflow.ellipsis),
                      ),
                      if (r.ownerName != null) ...[
                        const SizedBox(height: 6),
                        Text('${r.ownerName}${r.ownerBanned ? ' · ${t.bannedBadge}' : ''}', style: EnglishText.label(c.inkMuted, size: 12)),
                      ],
                      if (r.reasons.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final reason in r.reasons.take(5))
                          Text('“$reason”', style: EnglishText.italic(c.inkMuted, size: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => _decide(r, remove: false), child: Text(t.keepIt)),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: () => _decide(r, remove: true), child: Text(t.removeIt)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Readers extends ConsumerStatefulWidget {
  const _Readers();

  @override
  ConsumerState<_Readers> createState() => _ReadersState();
}

class _ReadersState extends ConsumerState<_Readers> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<AdminUser> _users = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final users = await ref.read(apiClientProvider).adminUsers(_q.text);
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(context, ref.read(stringsProvider).errorFor(e.code, e.message));
    }
  }

  Future<void> _update(AdminUser u, {String? tier, bool? banned}) async {
    Haptics.commit();
    try {
      final updated = await ref.read(apiClientProvider).adminUpdateUser(u.uid, tier: tier, banned: banned);
      if (mounted) setState(() => _users = [for (final x in _users) x.uid == u.uid ? updated : x]);
    } on ApiFailure catch (e) {
      if (mounted) _snack(context, ref.read(stringsProvider).errorFor(e.code, e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _q,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => unawaited(_search()));
            },
            decoration: InputDecoration(hintText: t.searchReaders, prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted)),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _users.length,
                  separatorBuilder: (_, _) => Divider(color: c.rule),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Avatar(name: u.label, url: u.photoUrl, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${u.label}${u.isAdmin ? ' · ${t.admin}' : ''}${u.banned ? ' · ${t.bannedBadge}' : ''}',
                                  style: EnglishText.label(u.banned ? c.accent : c.ink, size: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (u.email != null || u.phone != null)
                                  Text(u.email ?? u.phone!, style: EnglishText.label(c.inkMuted, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (u.usage != null) Text(usageLine(u.usage!, t), style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 12)),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            color: c.card,
                            tooltip: t.setPlan,
                            onSelected: (v) => switch (v) {
                              'ban' => unawaited(_update(u, banned: true)),
                              'unban' => unawaited(_update(u, banned: false)),
                              _ => unawaited(_update(u, tier: v)),
                            },
                            itemBuilder: (_) => [
                              for (final (value, tier) in [('free', Tier.free), ('pro', Tier.pro), ('super', Tier.superTier)])
                                CheckedPopupMenuItem(value: value, checked: u.tier == tier, child: Text(tierLabel(tier, t))),
                              const PopupMenuDivider(),
                              if (!u.isAdmin) PopupMenuItem(value: u.banned ? 'unban' : 'ban', child: Text(u.banned ? t.unban : t.ban)),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(border: Border.all(color: c.ink, width: 1.5)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(tierLabel(u.tier, t), style: EnglishText.label(c.ink)),
                                  Icon(Icons.expand_more_rounded, size: 18, color: c.inkMuted),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Broadcast extends ConsumerStatefulWidget {
  const _Broadcast();

  @override
  ConsumerState<_Broadcast> createState() => _BroadcastState();
}

class _BroadcastState extends ConsumerState<_Broadcast> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _tier;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final who = switch (_tier) {
      'pro' => t.tierPro,
      'super' => t.tierSuper,
      'free' => t.tierFree,
      _ => t.everyone,
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        content: Text(t.broadcastConfirm(who), style: uiBody(hindi: t.isHindi, color: c.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.send)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    try {
      final r = await ref.read(apiClientProvider).broadcast(title: _title.text.trim(), body: _body.text.trim(), tier: _tier);
      Haptics.commit();
      if (!mounted) return;
      _snack(context, t.broadcastSent(r.readers));
      _title.clear();
      _body.clear();
    } on ApiFailure catch (e) {
      if (mounted) _snack(context, t.errorFor(e.code, e.message));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final label = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(t.broadcastTitle, style: label),
        TextField(controller: _title, maxLength: 80, onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Text(t.broadcastBody, style: label),
        TextField(controller: _body, maxLength: 240, minLines: 2, maxLines: 5, onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        Text(t.broadcastTo, style: label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final (value, name) in [(null, t.everyone), ('free', t.tierFree), ('pro', t.tierPro), ('super', t.tierSuper)])
              ChoiceChip(
                label: Text(name),
                selected: _tier == value,
                showCheckmark: false,
                onSelected: (_) {
                  Haptics.choose();
                  setState(() => _tier = value);
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _sending || _title.text.trim().isEmpty || _body.text.trim().isEmpty ? null : _send,
          icon: const Icon(Icons.campaign_outlined),
          label: Text(t.send),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ],
    );
  }
}
