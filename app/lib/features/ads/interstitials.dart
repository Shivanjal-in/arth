// Full-screen ads for the free tier, at natural breaks only: leaving a book
// after real reading, or finishing a Replay / Practice session. Never on
// launch, never mid-reading, and at most one every few minutes.
//
// One ad is kept loaded so it appears instantly at the break; after it's
// shown (or fails) the next one loads. Ad units come from dart-defines;
// without them, Google's test units:
//   --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-xxxx/yyyy
//   --dart-define=ADMOB_INTERSTITIAL_IOS=ca-app-pub-xxxx/zzzz

import 'dart:async';
import 'dart:io';

import 'package:arth/features/ads/ads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const _unitAndroid = String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID', defaultValue: 'ca-app-pub-3940256099942544/1033173712');
const _unitIos = String.fromEnvironment('ADMOB_INTERSTITIAL_IOS', defaultValue: 'ca-app-pub-3940256099942544/4411468910');

/// Where a break happened.
enum AdBreak {
  /// Left a book (only counts after [AdPacing.minReading] of reading).
  closedBook,

  /// Finished a Replay or Practice session.
  finishedReview,
}

/// When a full-screen ad may show. Pure, so it can be tested with a clock.
class AdPacing {
  AdPacing({required this.appStartedAt});

  /// No ad in the first minutes after the app opens.
  static const graceAfterLaunch = Duration(minutes: 2);

  /// At most one ad per this long.
  static const minGap = Duration(minutes: 6);

  /// A book opened and closed quickly (looking something up) isn't a break.
  static const minReading = Duration(minutes: 2);

  final DateTime appStartedAt;
  DateTime? lastShownAt;

  bool allows(AdBreak at, {required DateTime now, Duration? readFor}) {
    if (now.difference(appStartedAt) < graceAfterLaunch) return false;
    final last = lastShownAt;
    if (last != null && now.difference(last) < minGap) return false;
    if (at == AdBreak.closedBook && (readFor == null || readFor < minReading)) return false;
    return true;
  }
}

final interstitialsProvider = Provider<Interstitials>((ref) {
  final i = Interstitials(ref);
  ref.onDispose(i.dispose);
  return i;
});

class Interstitials {
  Interstitials(this._ref) {
    // Load once ads are allowed for this reader; drop the ad if they stop
    // being (an upgrade to Pro mid-session).
    _ref.listen<bool>(showAdsProvider, (_, show) {
      if (show) {
        _load();
      } else {
        unawaited(_ad?.dispose());
        _ad = null;
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  final pacing = AdPacing(appStartedAt: DateTime.now());
  InterstitialAd? _ad;
  bool _loading = false;
  bool _showing = false;

  void _load() {
    if (_ad != null || _loading || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    _loading = true;
    unawaited(
      InterstitialAd.load(
        adUnitId: Platform.isIOS ? _unitIos : _unitAndroid,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _loading = false;
            _ad = ad;
          },
          onAdFailedToLoad: (error) {
            _loading = false;
            debugPrint('interstitial failed to load: $error');
          },
        ),
      ),
    );
  }

  /// A break happened: shows the preloaded ad if this reader sees ads and
  /// the pacing allows. [readFor] is how long the book was open.
  void onBreak(AdBreak at, {Duration? readFor}) {
    final ad = _ad;
    final now = DateTime.now();
    if (ad == null || _showing || !_ref.read(showAdsProvider) || !pacing.allows(at, now: now, readFor: readFor)) return;
    _ad = null;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => pacing.lastShownAt = DateTime.now(),
      onAdDismissedFullScreenContent: (shown) {
        _showing = false;
        unawaited(shown.dispose());
        _load();
      },
      onAdFailedToShowFullScreenContent: (failed, error) {
        _showing = false;
        debugPrint('interstitial failed to show: $error');
        unawaited(failed.dispose());
        _load();
      },
    );
    unawaited(ad.show());
  }

  void dispose() {
    unawaited(_ad?.dispose());
    _ad = null;
  }
}

/// For the readers: when the reader closes, that's a break — if the book
/// was open long enough to count as reading.
mixin AdBreakOnClose<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final DateTime _openedAt = DateTime.now();
  late final Interstitials _interstitials;

  @override
  void initState() {
    super.initState();
    // Captured now: `ref` can't be used once the widget is disposing.
    _interstitials = ref.read(interstitialsProvider);
  }

  @override
  void dispose() {
    final readFor = DateTime.now().difference(_openedAt);
    final interstitials = _interstitials;
    super.dispose();
    // After the reader is gone, over the screen the reader returns to.
    scheduleMicrotask(() => interstitials.onBreak(AdBreak.closedBook, readFor: readFor));
  }
}
