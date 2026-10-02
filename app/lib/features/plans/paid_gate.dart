// Features that come with Pro and Super (scanning pages, sharing recaps):
// one check, and one sheet telling a Free or signed-out reader what it
// takes.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Whether the reader has a paid plan (or is an admin), as far as is known
/// right now; for badges. [ensurePaid] waits for the account instead.
bool hasPaidPlan(WidgetRef ref) {
  final account = ref.watch(accountProvider).valueOrNull;
  return account != null && (account.tier != Tier.free || account.isAdmin);
}

/// True if the reader may use a paid feature. Otherwise shows the sheet —
/// sign in first, or see the plans — explaining [why], and returns false.
Future<bool> ensurePaid(BuildContext context, WidgetRef ref, {required String title, required String why}) async {
  final signedIn = ref.read(signedInUidProvider) != null;
  Account? account;
  if (signedIn) {
    try {
      account = await ref.read(accountProvider.future);
    } on Exception {
      account = null;
    }
  }
  if (account != null && (account.tier != Tier.free || account.isAdmin)) return true;
  if (!context.mounted) return false;
  final t = ref.read(stringsProvider);
  final c = context.colors;
  final scale = ref.read(settingsProvider).hindiScale;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.workspace_premium_outlined, color: c.marigold, size: 32),
            const SizedBox(height: 12),
            Text(title, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
            const SizedBox(height: 8),
            Text(why, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(context.push(signedIn ? '/plans' : '/signin'));
                },
                child: Text(signedIn ? t.seePlans : t.signIn),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return false;
}

/// A small "Pro" tag beside a paid feature, for readers without a plan.
class PaidTag extends ConsumerWidget {
  const PaidTag({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hasPaidPlan(ref)) return const SizedBox.shrink();
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.marigold.withValues(alpha: 0.18), border: Border.all(color: c.ink, width: 1.5)),
      child: Text(t.tierPro, style: EnglishText.label(c.ink, size: 11.5)),
    );
  }
}
