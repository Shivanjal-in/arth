// Push notifications (Firebase Cloud Messaging).
//
// The phone's token is sent to the API only once a reader is signed in —
// registering at launch would race the restored session and save nothing —
// and again whenever FCM rotates it or the interface language changes (the
// server writes each notification in the phone's language). Signing out
// removes it, so a shared phone stops getting the last reader's pushes.
//
// While the app is open, Android shows no banner for a push by itself, so
// one is posted locally; iOS is told to present its own. Tapping either
// opens the screen the push names (`route`).

import 'dart:async';
import 'dart:io';

import 'package:arth/data/api_client.dart';
import 'package:arth/data/local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';


class PushService {
  PushService({required this.api, required this.language, required this.local});

  final ApiClient Function() api;

  /// The interface language, 'en' or 'hi'.
  final String Function() language;

  /// Posts the banner for a push that arrives while the app is open.
  final LocalNotifications local;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _refresh;
  String? _registered;
  String? _registeredLang;

  /// Where a tapped notification wants to go; the router listens.
  final StreamController<String> routes = StreamController<String>.broadcast();

  /// A tap that opened the app from closed, before the router was ready.
  String? pendingRoute;

  Future<void> init() async {
    if (!Platform.isAndroid) {
      await _messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    }
    FirebaseMessaging.onMessage.listen(_showInForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) pendingRoute = initial.data['route'] as String?;
  }

  void _open(RemoteMessage m) {
    final route = m.data['route'] as String?;
    if (route != null && route.isNotEmpty) routes.add(route);
  }

  Future<void> _showInForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null || !Platform.isAndroid || !local.ready) return;
    await local.plugin.show(
      id: m.messageId.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: LocalNotifications.details,
      payload: m.data['route'] as String?,
    );
  }

  /// Signed in (or the language changed): ask permission once, then give
  /// the API this phone's token. Quietly does nothing if refused.
  Future<void> register() async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await _messaging.getToken();
      if (token == null) return; // iOS without an APNs key; see the setup guide
      await _send(token);
      await _refresh?.cancel();
      _refresh = _messaging.onTokenRefresh.listen((t) => unawaited(_send(t)));
    } on Exception catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  Future<void> _send(String token) async {
    final lang = language();
    if (token == _registered && lang == _registeredLang) return;
    await api().registerPushToken(token: token, platform: Platform.isIOS ? 'ios' : 'android', lang: lang);
    _registered = token;
    _registeredLang = lang;
  }

  /// After the account was deleted: the server has already forgotten this
  /// phone's token, so only drop it here (asking the API would be refused).
  Future<void> forgetLocally() async {
    await _refresh?.cancel();
    _refresh = null;
    _registered = null;
    _registeredLang = null;
    try {
      await _messaging.deleteToken();
    } on Exception catch (e) {
      debugPrint('push forget failed: $e');
    }
  }

  /// Signing out: stop this phone getting the account's pushes. Called
  /// while still signed in, so the API accepts the request.
  Future<void> unregister() async {
    await _refresh?.cancel();
    _refresh = null;
    final token = _registered;
    _registered = null;
    _registeredLang = null;
    try {
      if (token != null) await api().unregisterPushToken(token);
      await _messaging.deleteToken();
    } on Exception catch (e) {
      debugPrint('push unregister failed: $e');
    }
  }
}
