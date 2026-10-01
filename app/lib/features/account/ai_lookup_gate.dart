// Turning AI lookup on is one switch, in the reader menu and in Settings.
// Signed out, that switch doesn't move: a sheet sends them to sign in.
// With no Firebase project there is no sign-in, so the switch just moves.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Future<void> setAiLookup(BuildContext context, WidgetRef ref, {required bool on}) async {
  if (on && ref.read(firebaseReadyProvider) && ref.read(signedInUidProvider) == null) {
    if (!context.mounted) return;
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final scale = ref.read(settingsProvider).hindiScale;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, color: c.accent, size: 32),
              const SizedBox(height: 12),
              Text(t.aiLookup, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
              const SizedBox(height: 8),
              Text(t.aiLookupSignIn, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(context.push('/signin'));
                  },
                  child: Text(t.signIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return;
  }
  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(aiLookup: on));
}
