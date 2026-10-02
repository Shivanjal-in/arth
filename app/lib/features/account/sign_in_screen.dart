// Sign in with Google, or a phone number and SMS code. Phone numbers
// default to India (+91); a number typed with its own + code is used as is.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/auth_service.dart';
import 'package:arth/features/account/google_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phone sign-in is switched off for now: every code is an SMS Firebase
/// bills for. The flow below is complete; set this to true to bring it
/// back (and enable the Phone provider in Firebase).
const bool kPhoneSignIn = false;

/// The number in E.164: "98765 43210" → "+919876543210".
String toE164(String typed, {String countryCode = '+91'}) {
  final digits = typed.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.startsWith('+')) return digits;
  // A leading 0 is the domestic trunk prefix.
  return '$countryCode${digits.replaceFirst(RegExp('^0+'), '')}';
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  CodeSent? _sent;
  String? _sentTo;
  bool _busy = false;
  String? _error;
  Timer? _resendTimer;
  int _resendIn = 0;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  AuthService get _auth => ref.read(authServiceProvider)!;

  Future<void> _attempt(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on AuthFailure catch (e) {
      final message = ref.read(stringsProvider).authError(e.error.name);
      if (mounted) setState(() => _error = message.isEmpty ? null : message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (mounted) unawaited(Navigator.of(context).maybePop());
  }

  Future<void> _google() => _attempt(() async {
        await _auth.signInWithGoogle();
        _done();
      });

  Future<void> _sendCode({bool resend = false}) => _attempt(() async {
        final number = toE164(_phone.text);
        final step = await _auth.sendCode(number, resendToken: resend ? _sent?.resendToken : null);
        switch (step) {
          case AutoVerified():
            _done();
          case CodeSent():
            setState(() {
              _sent = step;
              _sentTo = number;
            });
            _startResendTimer();
        }
      });

  Future<void> _verify() => _attempt(() async {
        await _auth.confirmCode(_sent!.verificationId, _code.text.trim());
        _done();
      });

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final body = uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14.5);
    final sent = _sent;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text('अ', style: const HindiText(1).headline(c.accent).copyWith(fontSize: 56, height: 1)),
            const SizedBox(height: 16),
            Text(t.signInTitle, style: uiTitle(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 28)),
            const SizedBox(height: 8),
            Text(t.signInPitch, style: body),
            const SizedBox(height: 28),
            if (sent == null) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: const GoogleLogo(),
                label: Text(t.continueWithGoogle, style: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 15.5)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
              ),
              if (kPhoneSignIn) ...[
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(child: Divider(color: c.rule)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(t.orPhone, style: body.copyWith(fontSize: 13))),
                    Expanded(child: Divider(color: c.rule)),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+ ]'))],
                  style: EnglishText.body(c.ink, size: 20).copyWith(letterSpacing: 1),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => digits.length >= 10 && !_busy ? _sendCode() : null,
                  decoration: InputDecoration(
                    labelText: t.phoneNumber,
                    prefixText: _phone.text.trim().startsWith('+') ? null : '+91  ',
                    prefixStyle: EnglishText.body(c.inkMuted, size: 20),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy || digits.length < 10 ? null : _sendCode,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: Text(t.sendCode),
                ),
              ],
            ] else ...[
              Text(t.codeSentTo(_sentTo ?? ''), style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale)),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: EnglishText.title(c.ink).copyWith(letterSpacing: 12),
                onChanged: (v) {
                  setState(() {});
                  if (v.length == 6 && !_busy) unawaited(_verify());
                },
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy || _code.text.length != 6 ? null : _verify,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(t.verify),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _sent = null;
                              _code.clear();
                              _error = null;
                            }),
                    style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                    child: Text(t.changeNumber),
                  ),
                  TextButton(
                    onPressed: _busy || _resendIn > 0 ? null : () => _sendCode(resend: true),
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: Text(_resendIn > 0 ? t.resendIn(_resendIn) : t.resendCode),
                  ),
                ],
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 18),
              Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: uiBody(hindi: t.isHindi, color: c.accent, scale: scale, size: 14.5)),
            ],
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: c.inkMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(t.signInPrivacy, style: body.copyWith(fontSize: 13))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
