// Firebase, configured at build time rather than from checked-in files:
//
//   flutter run \
//     --dart-define=FIREBASE_PROJECT_ID=arth-xxxx \
//     --dart-define=FIREBASE_API_KEY_ANDROID=AIza... \
//     --dart-define=FIREBASE_API_KEY_IOS=AIza... \
//     --dart-define=FIREBASE_MESSAGING_SENDER_ID=1234567890 \
//     --dart-define=FIREBASE_ANDROID_APP_ID=1:1234567890:android:abc \
//     --dart-define=FIREBASE_IOS_APP_ID=1:1234567890:ios:def \
//     --dart-define=GOOGLE_IOS_CLIENT_ID=1234567890-xyz.apps.googleusercontent.com \
//     --dart-define=GOOGLE_SERVER_CLIENT_ID=1234567890-web.apps.googleusercontent.com
//
// (or put them in a file and pass --dart-define-from-file=firebase.json).
// Without them the app runs as before, with accounts hidden.

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
// Firebase makes one API key per platform (google-services.json's
// current_key, GoogleService-Info.plist's API_KEY). FIREBASE_API_KEY, if
// set, is used for both.
const _apiKeyShared = String.fromEnvironment('FIREBASE_API_KEY');
const _apiKeyAndroid = String.fromEnvironment('FIREBASE_API_KEY_ANDROID');
const _apiKeyIos = String.fromEnvironment('FIREBASE_API_KEY_IOS');
const _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

/// iOS OAuth client (GoogleService-Info.plist: CLIENT_ID).
const String kGoogleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

/// The project's Web OAuth client: Android's Credential Manager needs it to
/// return an ID token Firebase accepts.
const String kGoogleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

FirebaseOptions? _options() {
  final appId = Platform.isIOS ? _iosAppId : _androidAppId;
  final platformKey = Platform.isIOS ? _apiKeyIos : _apiKeyAndroid;
  final apiKey = platformKey.isEmpty ? _apiKeyShared : platformKey;
  if (_projectId.isEmpty || apiKey.isEmpty || appId.isEmpty) return null;
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: _senderId,
    projectId: _projectId,
    iosClientId: kGoogleIosClientId.isEmpty ? null : kGoogleIosClientId,
    iosBundleId: 'com.zethyst.arth',
  );
}

/// Initializes Firebase if it's configured. False: accounts are off.
Future<bool> initFirebase() async {
  final options = _options();
  if (options == null) return false;
  try {
    await Firebase.initializeApp(options: options);
    return true;
  } on Exception catch (e) {
    debugPrint('Firebase init failed, accounts off: $e');
    return false;
  }
}
