// Notifications the phone posts itself: pushes arriving while the app is open
// (Android shows none by itself) and scheduled review reminders. One plugin
// instance, so a tap on either lands on the same route stream.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotifications {
  static const channel = AndroidNotificationChannel(
    'arth_default', // the server's android.notification.channelId
    'Arth',
    description: 'Review reminders and account updates',
    importance: Importance.high,
  );

  final plugin = FlutterLocalNotificationsPlugin();

  /// Where a tapped notification wants to go; the router listens.
  final StreamController<String> routes = StreamController<String>.broadcast();

  /// A tap that opened the app from closed, before the router was ready.
  String? launchRoute;

  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() async {
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_arth'),
          // Asked for when the reader first has something to be reminded
          // of, not at launch.
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) {
          final route = r.payload;
          if (route != null && route.isNotEmpty) routes.add(route);
        },
      );
      await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) launchRoute = launch!.notificationResponse?.payload;
      _ready = true;
    } on Exception catch (e) {
      debugPrint('local notifications init failed: $e');
    }
  }

  /// Asks to show notifications (iOS; Android 13+). True if allowed.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    if (Platform.isIOS) {
      return await plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? true;
  }

  static NotificationDetails get details => NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_arth',
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );
}
