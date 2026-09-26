import 'package:arth/data/account.dart';
import 'package:arth/data/billing.dart';
import 'package:arth/features/plans/plans_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

Period period(PeriodUnit unit, int value, String iso) => Period(unit, value, iso);
Price inr(double rupees) => Price('₹${rupees.round()}', (rupees * 1e6).round(), 'INR');

/// A Google Play product with a default offer made of the given phases.
StoreProduct play(String id, double price, {PricingPhase? free, PricingPhase? intro}) => StoreProduct(
      id,
      '',
      id,
      price,
      '₹${price.round()}',
      'INR',
      defaultOption: SubscriptionOption('opt', id, id, [?free, ?intro], const [], false, null, false, null, free, intro, null, null),
    );

void main() {
  group('offers as the Plans screen tells them', () {
    test('Google Play: a 7-day trial on the yearly plan', () {
      final p = play('pro_yearly', 599, free: PricingPhase(period(PeriodUnit.day, 7, 'P7D'), RecurrenceMode.finiteRecurring, 1, inr(0), OfferPaymentMode.freeTrial));
      final o = planOfferFrom(p, tier: Tier.pro, yearly: true);
      expect(o.freeTrialDays, 7);
      expect(o.introPriceString, isNull);
      expect(o.priceString, '₹599');
    });

    test('Google Play: ₹49 a month for 3 months on Pro monthly', () {
      final p = play('pro_monthly', 79, intro: PricingPhase(period(PeriodUnit.month, 1, 'P1M'), RecurrenceMode.finiteRecurring, 3, inr(49), OfferPaymentMode.discountedRecurringPayment));
      final o = planOfferFrom(p, tier: Tier.pro, yearly: false);
      expect(o.introPriceString, '₹49');
      expect(o.introMonths, 3);
      expect(o.freeTrialDays, isNull);
    });

    test('App Store: a free week, and a paid intro, from the introductory price', () {
      const trial = StoreProduct('super_yearly', '', '', 1199, '₹1,199', 'INR', introductoryPrice: IntroductoryPrice(0, '₹0', 'P1W', 1, PeriodUnit.week, 1));
      expect(planOfferFrom(trial, tier: Tier.superTier, yearly: true).freeTrialDays, 7);
      const intro = StoreProduct('pro_monthly', '', '', 79, '₹79', 'INR', introductoryPrice: IntroductoryPrice(49, '₹49', 'P1M', 3, PeriodUnit.month, 1));
      final o = planOfferFrom(intro, tier: Tier.pro, yearly: false);
      expect((o.introPriceString, o.introMonths, o.freeTrialDays), ('₹49', 3, null));
    });

    test('no offer: just the price', () {
      const p = StoreProduct('super_monthly', '', '', 149, '₹149', 'INR');
      final o = planOfferFrom(p, tier: Tier.superTier, yearly: false);
      expect((o.freeTrialDays, o.introPriceString), (null, null));
    });

    test('yearly saving against twelve months', () {
      const offers = [
        PlanOffer(tier: Tier.pro, yearly: true, price: 599, priceString: '₹599'),
        PlanOffer(tier: Tier.pro, yearly: false, price: 79, priceString: '₹79'),
      ];
      expect(yearlySaving(offers, Tier.pro), 37); // 599 vs 948
      expect(yearlySaving(offers, Tier.superTier), isNull);
    });

    test('about ₹50 a month, not ₹49.92', () {
      expect(approxMoney(599 / 12, 'INR'), '₹50');
      expect(approxMoney(1199 / 12, 'INR'), '₹100');
      expect(approxMoney(4.99 / 12 * 12, 'USD'), r'$4.99');
    });
  });
}
