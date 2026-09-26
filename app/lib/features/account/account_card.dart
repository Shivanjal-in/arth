// The top of the You tab: an invitation to sign in, or who you are with
// the sync status. Hidden entirely when accounts are off.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:arth/features/plans/plans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A round profile photo, or the name's initial on the lac-red ground.
class Avatar extends StatelessWidget {
  const Avatar({required this.name, required this.size, super.key, this.url});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = name.trim().isEmpty ? 'अ' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
      child: Text(initial, style: EnglishText.word(c.onAccent, size: size * 0.42)),
    );
    final u = url;
    if (u == null) return fallback;
    return ClipOval(
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) => progress == null ? child : SizedBox(width: size, height: size, child: fallback),
      ),
    );
  }
}

String tierLabel(Tier tier, AppStrings t) => switch (tier) {
      Tier.free => t.tierFree,
      Tier.pro => t.tierPro,
      Tier.superTier => t.tierSuper,
    };

class AccountCard extends ConsumerWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(firebaseReadyProvider)) return const SizedBox.shrink();
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final user = ref.watch(authUserProvider).valueOrNull;
    final account = ref.watch(accountProvider).valueOrNull;
    final sync = ref.watch(syncProvider);
    final usage = ref.watch(usageProvider);

    final Widget body;
    if (user == null) {
      body = Row(
        children: [
          Icon(Icons.cloud_sync_outlined, color: c.accent, size: 30),
          const SizedBox(width: 14),
          Expanded(child: Text(t.signInPitch, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14.5))),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => context.push('/signin'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            child: Text(t.signIn),
          ),
        ],
      );
    } else {
      final name = account?.label ?? user.displayName ?? user.phoneNumber ?? user.email ?? '';
      final status = switch (sync.phase) {
        SyncPhase.syncing => t.syncing,
        SyncPhase.failed => t.syncFailed,
        SyncPhase.idle => sync.lastSyncedAt == null ? t.notSyncedYet : t.syncedAgo(DateTime.now().difference(sync.lastSyncedAt!)),
      };
      body = InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/profile'),
        child: Row(
          children: [
            Avatar(name: name, url: account?.photoUrl ?? user.photoURL, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(name, style: EnglishText.word(c.ink, size: 19), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (account != null) ...[
                        const SizedBox(width: 8),
                        _Chip(label: tierLabel(account.tier, t), color: account.tier == Tier.free ? c.inkMuted : c.marigold),
                        if (account.isAdmin) ...[const SizedBox(width: 6), _Chip(label: t.admin, color: c.accent)],
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        sync.phase == SyncPhase.failed ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                        size: 15,
                        color: sync.phase == SyncPhase.failed ? c.accent : c.inkMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: Text(status, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13))),
                    ],
                  ),
                ],
              ),
            ),
            if (sync.phase == SyncPhase.syncing)
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
            else
              IconButton(
                tooltip: t.syncNow,
                icon: Icon(Icons.sync_rounded, color: c.inkMuted),
                onPressed: () => unawaited(ref.read(syncProvider.notifier).run()),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.rule)),
        child: Column(
          children: [
            body,
            if (user != null && usage != null) ...[
              const SizedBox(height: 10),
              Divider(color: c.rule, height: 1),
              InkWell(
                onTap: () => context.push('/plans'),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, size: 17, color: usage.exhausted ? c.accent : c.marigold),
                      const SizedBox(width: 8),
                      Expanded(child: Text(usageLine(usage, t), style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 13.5))),
                      Text(t.seePlans, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: EnglishText.label(color, size: 11.5)),
      );
}
