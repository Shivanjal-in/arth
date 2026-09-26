// Free, Pro, Super: what each gets, which one you're on and how much of
// its AI allowance is left. There's no payment in the app yet — tiers are
// set by the Arth team — so upgrading is an email.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where upgrade requests go:
///   --dart-define=ARTH_SUPPORT_EMAIL=help@example.com
const String kSupportEmail = String.fromEnvironment('ARTH_SUPPORT_EMAIL');

/// "37 of 100 AI answers left" for the account card and this screen.
String usageLine(Usage usage, AppStrings t) {
  final limit = usage.limit;
  if (limit == null) return t.aiUnlimited;
  return usage.monthly ? t.aiLeftMonth(usage.left!, limit) : t.aiLeft(usage.left!, limit);
}

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final account = ref.watch(accountProvider).valueOrNull;
    final usage = ref.watch(usageProvider);
    final current = account?.tier;

    Future<void> request(Tier tier) async {
      final name = switch (tier) {
        Tier.pro => 'Pro',
        Tier.superTier => 'Super',
        Tier.free => 'Free',
      };
      final who = account == null ? '' : '\n\nAccount: ${account.email ?? account.phone ?? account.uid}\nUser id: ${account.uid}';
      final uri = Uri(scheme: 'mailto', path: kSupportEmail, query: 'subject=${Uri.encodeComponent('Arth $name')}&body=${Uri.encodeComponent('Please upgrade my account to $name.$who')}');
      await launchUrl(uri);
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.plans)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(t.plansIntro, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
          if (usage != null) ...[
            const SizedBox(height: 18),
            _Meter(usage: usage),
          ],
          const SizedBox(height: 22),
          for (final (tier, ai, ads, ink) in [
            (Tier.free, t.planFreeAi, t.planAds, c.inkMuted),
            (Tier.pro, t.planProAi, t.planNoAds, c.accent),
            (Tier.superTier, t.planSuperAi, t.planNoAds, c.marigold),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PlanCard(
                name: switch (tier) {
                  Tier.free => t.tierFree,
                  Tier.pro => t.tierPro,
                  Tier.superTier => t.tierSuper,
                },
                ink: ink,
                lines: [(Icons.auto_awesome_outlined, ai), (Icons.menu_book_outlined, t.planOfflineDictionary), (Icons.campaign_outlined, ads)],
                current: tier == current,
                onRequest: tier == Tier.free || tier == current || kSupportEmail.isEmpty ? null : () => unawaited(request(tier)),
              ),
            ),
          if (kSupportEmail.isNotEmpty)
            Text(t.upgradeNote, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13.5)),
        ],
      ),
    );
  }
}

class _Meter extends ConsumerWidget {
  const _Meter({required this.usage});

  final Usage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final limit = usage.limit;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.rule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(usageLine(usage, t), style: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 15)),
          if (limit != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (usage.left! / limit).clamp(0, 1),
                minHeight: 6,
                color: usage.exhausted ? c.accent : c.marigold,
                backgroundColor: c.rule,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.name, required this.ink, required this.lines, required this.current, this.onRequest});

  final String name;
  final Color ink;
  final List<(IconData, String)> lines;
  final bool current;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: current ? ink : c.rule, width: current ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 5, color: ink),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: EnglishText.heading(c.ink, size: 22)),
                    const Spacer(),
                    if (current)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: ink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                        child: Text(t.currentPlan, style: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final (icon, line) in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: ink),
                        const SizedBox(width: 10),
                        Expanded(child: Text(line, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14.5))),
                      ],
                    ),
                  ),
                if (onRequest != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onRequest,
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      child: Text(t.requestUpgrade),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
