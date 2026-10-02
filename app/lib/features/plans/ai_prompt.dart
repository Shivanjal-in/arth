// What the word and translation cards show instead of an AI answer when
// the reader can't have one: signed out, or out of allowance.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/features/reader/reader_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Which AI feature is asking, for the sign-in wording.
enum AiFeature { context, translate, rareWord }

bool isAiBlock(String? code) => aiBlockCodes.contains(code);

class AiPrompt extends ConsumerWidget {
  const AiPrompt({required this.code, required this.feature, super.key});

  /// `UNAUTHORIZED` or `QUOTA_EXCEEDED`.
  final String code;
  final AiFeature feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final signIn = code == 'UNAUTHORIZED';
    final usage = ref.watch(usageProvider);
    final resets = usage?.resetsAt;
    final message = signIn
        ? switch (feature) {
            AiFeature.context => t.aiSignInContext,
            AiFeature.translate => t.aiSignInTranslate,
            AiFeature.rareWord => t.aiSignInRareWord,
          }
        : code == 'QUOTA_PHONE'
            ? t.aiQuotaPhone
            : resets != null
                ? t.aiQuotaResets('${resets.day}/${resets.month}')
                : t.aiQuotaUsed;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.07),
        border: Border(left: BorderSide(color: c.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(signIn ? Icons.lock_outline_rounded : Icons.hourglass_empty_rounded, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14))),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                ref.read(readerControllerProvider.notifier).dismiss();
                unawaited(context.push(signIn ? '/signin' : '/plans'));
              },
              style: TextButton.styleFrom(foregroundColor: c.accent, visualDensity: VisualDensity.compact),
              child: Text(signIn ? t.signIn : t.seePlans, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale)),
            ),
          ),
        ],
      ),
    );
  }
}
