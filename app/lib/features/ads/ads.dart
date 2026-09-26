// Banner ads for the free tier, never inside the reader: the Library,
// Dictionary and Cards tabs carry one above the navigation bar. Pro and
// Super see none.
//
// Consent first (Google's UMP: a form where the law requires one, e.g. the
// EEA/UK), then the SDK. Ad units come from dart-defines; without them,
// Google's test units, which are safe to tap:
//   --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-xxxx/yyyy
//   --dart-define=ADMOB_BANNER_IOS=ca-app-pub-xxxx/zzzz
// The AdMob *app* id is native config: see android/app/build.gradle.kts and
// ios/Flutter/AdMob.xcconfig.

import 'dart:async';
import 'dart:io';

import 'package:arth/app/account_providers.dart';
import 'package:arth/data/account.dart';
import 'package:arth/features/ads/interstitials.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _bannerAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/9214589741');
const _bannerIos = String.fromEnvironment('ADMOB_BANNER_IOS', defaultValue: 'ca-app-pub-3940256099942544/2435281174');

/// True once consent is settled and the SDK is up; set by [initAds].
final adsReadyProvider = NotifierProvider<AdsReady, bool>(AdsReady.new);

class AdsReady extends Notifier<bool> {
  @override
  bool build() => false;

  void markReady() => state = true;
}

/// Whether this reader sees ads: the free tier, or not signed in.
final showAdsProvider = Provider<bool>((ref) {
  if (!ref.watch(adsReadyProvider)) return false;
  final tier = ref.watch(accountProvider).valueOrNull?.tier ?? Tier.free;
  return tier == Tier.free;
});

/// Asks for consent where required, then starts the SDK. Runs after the
/// first frame; ads simply don't appear until it finishes (or if it fails).
Future<void> initAds(ProviderContainer container) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await _consent();
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.initialize();
    // A reading app for learners: keep ads to general audiences.
    await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg));
    container.read(adsReadyProvider.notifier).markReady();
    // Preload the first full-screen ad so a break never waits on the network.
    container.read(interstitialsProvider);
  } on Exception catch (e) {
    debugPrint('ads off: $e');
  }
}

Future<void> _consent() {
  final done = Completer<void>();
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () => ConsentForm.loadAndShowConsentFormIfRequired((_) {
      if (!done.isCompleted) done.complete();
    }),
    (_) {
      // Couldn't reach the consent service: canRequestAds() decides.
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future;
}

/// A screen-wide anchored banner; takes no space until an ad has loaded.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  /// What the loaded ad actually measures (inline adaptive ads choose).
  AdSize? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width != _width) {
      _width = width;
      unawaited(_load(width));
    }
  }

  Future<void> _load(int width) async {
    // Capped at 60dp: a strip, not a billboard, under a reading app's tabs.
    final size = AdSize.getInlineAdaptiveBannerAdSize(width, 60);
    await _ad?.dispose();
    _loaded = false;
    final ad = BannerAd(
      adUnitId: Platform.isIOS ? _bannerIos : _bannerAndroid,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loaded) async {
          final actual = await (loaded as BannerAd).getPlatformAdSize();
          if (mounted) {
            setState(() {
              _size = actual ?? size;
              _loaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, _) => unawaited(ad.dispose()),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    unawaited(_ad?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final size = _size;
    if (!_loaded || ad == null || size == null) return const SizedBox.shrink();
    return SizedBox(
      width: size.width.toDouble(),
      height: size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
