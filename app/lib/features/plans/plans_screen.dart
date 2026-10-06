// Free, Pro, Super: what each gets, which one you're on, how much of its AI
// allowance is left — and, where the build can sell plans (RevenueCat), the
// store's own prices, trials and intro offers, yearly first. Without a
// RevenueCat key, upgrading falls back to an email.

import 'dart:async';
import 'dart:io';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/billing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where upgrade requests go when plans can't be bought in the app:
///   --dart-define=ARTH_SUPPORT_EMAIL=help@example.com
const String kSupportEmail = String.fromEnvironment('ARTH_SUPPORT_EMAIL');

/// "37 of 100 AI answers left" for the account card and this screen.
String usageLine(Usage usage, AppStrings t) {
  final limit = usage.limit;
  if (limit == null) return t.aiUnlimited;
  return usage.monthly ? t.aiLeftMonth(usage.left!, limit) : t.aiLeft(usage.left!, limit);
}

/// The store's plans, or null when they can't be sold or loaded.
final AutoDisposeFutureProvider<List<PlanOffer>?> planOffersProvider =
    FutureProvider.autoDispose<List<PlanOffer>?>((ref) => ref.watch(billingProvider).offers());

/// How much the yearly price saves over twelve months, as a whole percent.
int? yearlySaving(List<PlanOffer> offers, Tier tier) {
  final y = offers.where((o) => o.tier == tier && o.yearly).firstOrNull;
  final m = offers.where((o) => o.tier == tier && !o.yearly).firstOrNull;
  if (y == null || m == null || m.price <= 0) return null;
  final pct = ((1 - y.price / (m.price * 12)) * 100).round();
  return pct > 0 ? pct : null;
}

/// "₹50": whole units from 10 up (an approximate monthly figure needn't
/// show paise), two decimals below that.
String approxMoney(double amount, String currency) =>
    NumberFormat.simpleCurrency(name: currency, decimalDigits: amount >= 10 ? 0 : 2).format(amount >= 10 ? amount.roundToDouble() : amount);

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _yearly = true;
  bool _busy = false;

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  /// After the store says yes: the API applies the plan now (the webhook
  /// would, a little later), and every screen refetches the account.
  Future<void> _applyPurchase() async {
    try {
      await ref.read(apiClientProvider).billingSync();
    } on ApiFailure catch (e) {
      debugPrint('billing sync: $e'); // the webhook still applies it
    }
    ref.invalidate(accountProvider);
  }

  Future<void> _buy(PlanOffer offer, String planName) async {
    final t = ref.read(stringsProvider);
    if (ref.read(signedInUidProvider) == null) {
      _snack(t.signInToBuy);
      unawaited(context.push('/signin'));
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref.read(billingProvider).buy(offer);
    ref.read(analyticsProvider).track('Plan Purchase', {'plan': offer.tier.name, 'yearly': offer.yearly, 'outcome': outcome.name});
    if (outcome == BuyOutcome.bought) {
      unawaited(Haptics.finish());
      await _applyPurchase();
      if (mounted) _snack(t.welcomeTo(planName));
    } else if (outcome == BuyOutcome.failed && mounted) {
      _snack(t.purchaseFailed);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final t = ref.read(stringsProvider);
    setState(() => _busy = true);
    final ok = await ref.read(billingProvider).restore();
    if (ok) await _applyPurchase();
    if (mounted) {
      setState(() => _busy = false);
      _snack(ok ? t.restored : t.purchaseFailed);
    }
  }

  Future<void> _manage() async {
    final url = await ref.read(billingProvider).managementUrl() ??
        (Platform.isIOS ? 'https://apps.apple.com/account/subscriptions' : 'https://play.google.com/store/account/subscriptions');
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _request(Tier tier, Account? account) async {
    final name = switch (tier) {
      Tier.pro => 'Pro',
      Tier.superTier => 'Super',
      Tier.free => 'Free',
    };
    final who = account == null ? '' : '\n\nAccount: ${account.email ?? account.phone ?? account.uid}\nUser id: ${account.uid}';
    final uri = Uri(scheme: 'mailto', path: kSupportEmail, query: 'subject=${Uri.encodeComponent('Arth $name')}&body=${Uri.encodeComponent('Please upgrade my account to $name.$who')}');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final account = ref.watch(accountProvider).valueOrNull;
    final usage = ref.watch(usageProvider);
    final current = account?.tier;
    final billing = ref.watch(billingProvider);
    final offers = billing.available ? ref.watch(planOffersProvider) : const AsyncData<List<PlanOffer>?>(null);
    final list = offers.valueOrNull;
    final saving = list == null ? null : yearlySaving(list, Tier.pro);
    final store = Platform.isIOS ? 'the App Store' : 'Google Play';

    Widget? buyArea(Tier tier, String name) {
      if (tier == Tier.free) return null;
      if (tier == current) {
        return billing.available ? Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _manage, child: Text(t.manageSubscription))) : null;
      }
      if (!billing.available) {
        return kSupportEmail.isEmpty
            ? null
            : Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => unawaited(_request(tier, account)), child: Text(t.requestUpgrade)));
      }
      if (offers.isLoading) return const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
      final o = list?.where((o) => o.tier == tier && o.yearly == _yearly).firstOrNull;
      if (o == null) return Text(t.plansUnavailable, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13.5));
      final monthlyEquivalent = o.yearly ? approxMoney(o.price / 12, o.currencyCode) : null;
      final trial = o.freeTrialDays;
      return _Price(
        offer: o,
        headline: o.yearly ? t.perYear(o.priceString) : t.perMonth(o.priceString),
        note: o.introPriceString != null && o.introMonths != null
            ? t.introOffer(o.introPriceString!, o.introMonths!, o.priceString)
            : monthlyEquivalent == null
                ? null
                : t.aboutPerMonth(monthlyEquivalent),
        badge: trial == null ? null : t.daysFree(trial),
        button: trial == null ? t.subscribeTo(name) : t.startTrial(trial),
        onBuy: _busy ? null : () => unawaited(_buy(o, name)),
      );
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
          if (billing.available) ...[
            _PeriodSwitch(yearly: _yearly, saving: saving, onChanged: (v) => setState(() => _yearly = v)),
            const SizedBox(height: 16),
          ],
          for (final (tier, name, ai, ads, ink) in [
            (Tier.pro, t.tierPro, t.planProAi, t.planNoAds, c.accent),
            (Tier.superTier, t.tierSuper, t.planSuperAi, t.planNoAds, c.marigold),
            (Tier.free, t.tierFree, t.planFreeAi, t.planAds, c.inkMuted),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PlanCard(
                name: name,
                ink: ink,
                lines: [
                  (Icons.auto_awesome_outlined, ai),
                  (Icons.menu_book_outlined, t.planOfflineDictionary),
                  if (tier != Tier.free) (Icons.document_scanner_outlined, t.planScanShare),
                  (Icons.campaign_outlined, ads),
                ],
                current: tier == current,
                footer: buyArea(tier, name),
              ),
            ),
          if (billing.available) ...[
            Center(child: TextButton(onPressed: _busy ? null : () => unawaited(_restore()), child: Text(t.restorePurchases))),
            Text(t.renewNote(store), style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 12.5)),
            const SizedBox(height: 4),
            const LegalLinks(),
          ] else if (kSupportEmail.isNotEmpty)
            Text(t.upgradeNote, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13.5)),
        ],
      ),
    );
  }
}

/// Yearly (the default, with what it saves) or monthly.
class _PeriodSwitch extends ConsumerWidget {
  const _PeriodSwitch({required this.yearly, required this.saving, required this.onChanged});

  final bool yearly;
  final int? saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    Widget side({required bool isYearly, required String label, String? badge}) {
      final on = yearly == isYearly;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (on) return;
            Haptics.choose();
            onChanged(isYearly);
          },
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.quick),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: on ? c.ink : Colors.transparent),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: uiLabel(hindi: t.isHindi, color: on ? c.paper : c.ink, scale: scale).copyWith(fontSize: 14.5)),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: c.marigold, border: Border.all(color: c.ink, width: 1.5)),
                    child: Text(badge, style: EnglishText.label(const Color(0xFF1B2233), size: 11)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.card, border: Border.all(color: c.ink, width: 2), boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(4, 4))]),
      child: Row(
        children: [
          side(isYearly: true, label: t.yearly, badge: saving == null ? null : t.saveUpTo(saving!)),
          const SizedBox(width: 4),
          side(isYearly: false, label: t.monthly),
        ],
      ),
    );
  }
}

/// A paid plan's price, its offer, and the button.
class _Price extends ConsumerWidget {
  const _Price({required this.offer, required this.headline, required this.button, required this.onBuy, this.note, this.badge});

  final PlanOffer offer;
  final String headline;
  final String? note;
  final String? badge;
  final String button;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(headline, style: EnglishText.heading(c.ink, size: 19))),
              if (badge != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.marigold.withValues(alpha: 0.2), border: Border.all(color: c.ink, width: 1.5)),
                  child: Text(badge!, style: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 12)),
                ),
              ],
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(note!, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 13.5)),
          ],
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: onBuy, child: Text(button))),
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
      decoration: BoxDecoration(color: c.card, border: Border.all(color: c.ink, width: 2), boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(4, 4))]),
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
  const _PlanCard({required this.name, required this.ink, required this.lines, required this.current, this.footer});

  final String name;
  final Color ink;
  final List<(IconData, String)> lines;
  final bool current;
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: current ? ink : c.ink, width: 2),
        boxShadow: [BoxShadow(color: current ? ink : c.shadow, offset: const Offset(5, 5))],
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
                        decoration: BoxDecoration(color: ink.withValues(alpha: 0.15), border: Border.all(color: c.ink, width: 1.5)),
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
                ?footer,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Terms of Use and Privacy Policy, as the stores want them beside a
/// subscription (and in About).
class LegalLinks extends ConsumerWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    Widget link(String label, String page) => TextButton(
          onPressed: () => unawaited(launchUrl(legalUrl(page), mode: LaunchMode.externalApplication)),
          style: TextButton.styleFrom(foregroundColor: c.accent, visualDensity: VisualDensity.compact),
          child: Text(label, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale).copyWith(fontSize: 13)),
        );
    return Wrap(alignment: WrapAlignment.center, spacing: 4, children: [link(t.termsOfUse, 'terms'), link(t.privacyPolicy, 'privacy')]);
  }
}
