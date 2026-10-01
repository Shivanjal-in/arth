// Signing in: Google, or a phone number with an SMS code (how most of our
// readers have an account at all). Firebase Auth holds the session; the API
// sees only its ID tokens.

import 'dart:async';

import 'package:arth/app/firebase_setup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Why sign-in stopped, for the UI to word.
enum AuthError { cancelled, network, invalidPhone, invalidCode, codeExpired, tooManyRequests, unknown }

class AuthFailure implements Exception {
  const AuthFailure(this.error, [this.detail]);

  final AuthError error;
  final String? detail;

  @override
  String toString() => 'AuthFailure($error, $detail)';
}

/// Where phone sign-in stands after sending the number.
sealed class PhoneStep {
  const PhoneStep();
}

/// A code was sent; confirm it with [AuthService.confirmCode].
class CodeSent extends PhoneStep {
  const CodeSent(this.verificationId, this.resendToken);

  final String verificationId;
  final int? resendToken;
}

/// Android read the SMS itself and signed in; nothing to type.
class AutoVerified extends PhoneStep {
  const AutoVerified();
}

class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;
  bool _googleReady = false;

  Stream<User?> get changes => _auth.authStateChanges();

  User? get current => _auth.currentUser;

  /// A fresh ID token for the API (refreshed by Firebase when near expiry).
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(
        clientId: kGoogleIosClientId.isEmpty ? null : kGoogleIosClientId,
        serverClientId: kGoogleServerClientId.isEmpty ? null : kGoogleServerClientId,
      );
      _googleReady = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      // Android reports a misconfigured build (e.g. a signing key Firebase
      // doesn't know) as "canceled" too, so keep the detail.
      debugPrint('Google sign-in: ${e.code} ${e.description}');
      throw AuthFailure(e.code == GoogleSignInExceptionCode.canceled ? AuthError.cancelled : AuthError.unknown, e.description);
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AuthFailure(AuthError.unknown, 'no Google ID token');
    await _guard(() => _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)));
  }

  /// Sends a code to [phoneNumber] (E.164, e.g. +919876543210).
  Future<PhoneStep> sendCode(String phoneNumber, {int? resendToken}) {
    final done = Completer<PhoneStep>();
    unawaited(
      _auth
          .verifyPhoneNumber(
            phoneNumber: phoneNumber,
            forceResendingToken: resendToken,
            timeout: const Duration(seconds: 60),
            verificationCompleted: (credential) async {
              try {
                await _guard(() => _auth.signInWithCredential(credential));
                if (!done.isCompleted) done.complete(const AutoVerified());
              } on AuthFailure catch (e) {
                if (!done.isCompleted) done.completeError(e);
              }
            },
            verificationFailed: (e) {
              if (!done.isCompleted) done.completeError(_failure(e));
            },
            codeSent: (id, token) {
              if (!done.isCompleted) done.complete(CodeSent(id, token));
            },
            codeAutoRetrievalTimeout: (_) {},
          )
          .catchError((Object e) {
            if (!done.isCompleted) done.completeError(e is FirebaseAuthException ? _failure(e) : AuthFailure(AuthError.unknown, '$e'));
          }),
    );
    return done.future;
  }

  Future<void> confirmCode(String verificationId, String code) =>
      _guard(() => _auth.signInWithCredential(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code)));

  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } on Exception {
        // Not signed in with Google.
      }
    }
  }

  Future<void> _guard(Future<Object?> Function() f) async {
    try {
      await f();
    } on FirebaseAuthException catch (e) {
      throw _failure(e);
    }
  }

  static AuthFailure _failure(FirebaseAuthException e) => AuthFailure(
        switch (e.code) {
          'invalid-phone-number' || 'missing-phone-number' => AuthError.invalidPhone,
          'invalid-verification-code' || 'missing-verification-code' => AuthError.invalidCode,
          'session-expired' || 'code-expired' => AuthError.codeExpired,
          'too-many-requests' || 'quota-exceeded' => AuthError.tooManyRequests,
          'network-request-failed' => AuthError.network,
          _ => AuthError.unknown,
        },
        e.message,
      );
}
