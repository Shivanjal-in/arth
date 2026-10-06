// Product analytics through Mixpanel: which screens are used, and a few
// key actions. Never what's being read: no book titles, words or sentences,
// and screens are tracked by their route pattern (/word/:lemma, not the word).
//
// The signed-in reader is identified by their Firebase uid (no email or
// phone); signed out, Mixpanel's own random id. The advertising id isn't
// used, and IP addresses aren't kept for geolocation.
//
// The project token is public (it ships in every app). Debug builds send
// nothing unless asked, so testing doesn't skew the numbers:
//   --dart-define=MIXPANEL_DEBUG=true
//   --dart-define=MIXPANEL_TOKEN=…         (another project, e.g. staging)
//   --dart-define=MIXPANEL_SERVER_URL=…    (optional: https://api-eu.mixpanel.com
//                                           or https://api-in.mixpanel.com for
//                                           an EU/India-resident project)
// Off, every call does nothing.

import 'package:flutter/foundation.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

const _token = String.fromEnvironment('MIXPANEL_TOKEN', defaultValue: 'f4be36e798bf219e1d906aa3194db6f4');
const _inDebug = bool.fromEnvironment('MIXPANEL_DEBUG');
const _serverUrl = String.fromEnvironment('MIXPANEL_SERVER_URL');

class Analytics {
  Mixpanel? _mixpanel;
  String? _lastScreen;

  /// [optedOut]: the reader turned off usage stats in Settings.
  Future<void> init({bool optedOut = false}) async {
    if (_token.isEmpty || (kDebugMode && !_inDebug)) return;
    try {
      final mixpanel = await Mixpanel.init(_token, trackAutomaticEvents: false, optOutTrackingDefault: optedOut);
      if (_serverUrl.isNotEmpty) mixpanel.setServerURL(_serverUrl);
      mixpanel.setUseIpAddressForGeolocation(false);
      _mixpanel = mixpanel;
    } on Exception catch (e) {
      debugPrint('analytics off: $e');
    }
  }

  void track(String event, [Map<String, Object?>? properties]) => _mixpanel?.track(event, properties: properties);

  /// A screen came up; [route] is its pattern. Repeats are dropped (false).
  bool screen(String route) {
    if (route.isEmpty || route == _lastScreen) return false;
    _lastScreen = route;
    track('Screen Viewed', {'screen': route});
    return true;
  }

  Future<void> signedIn(String uid) async => _mixpanel?.identify(uid);

  /// A fresh anonymous id, so the next person on this phone isn't joined to
  /// the last.
  Future<void> signedOut() async => _mixpanel?.reset();

  /// Settings → Usage stats. Off also drops anything queued and not yet sent.
  void allow({required bool on}) {
    final mixpanel = _mixpanel;
    if (mixpanel == null) return;
    if (on) {
      mixpanel.optInTracking();
    } else {
      mixpanel.optOutTracking();
    }
  }

  /// Sent with every from now on (plan, interface language).
  void describe(Map<String, Object?> properties) => _mixpanel?.registerSuperProperties(properties);
}
