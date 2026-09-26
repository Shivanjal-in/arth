// What a signed-out or Free reader sees instead of the community: a blurred
// glimpse of recaps (samples, not real ones — the server shares nothing
// without a plan) under a card that says what the community is and what it
// takes.

import 'dart:async';
import 'dart:ui';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/settings.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/community.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/community/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CommunityLock extends ConsumerWidget {
  const CommunityLock({super.key});

  static final List<(String, String, Tier, String, CardFont, List<(CardKind, String)>)> _samples = [
    ('Pride and Prejudice', 'First impressions', Tier.superTier, 'Meera', CardFont.quintessential, [
      (CardKind.quote, 'It is a truth universally acknowledged'),
      (CardKind.word, 'propriety'),
      (CardKind.idea, 'Why Darcy’s letter changes everything'),
    ]),
    ('The Great Gatsby', 'The green light', Tier.pro, 'Arjun', CardFont.montserrat, [
      (CardKind.idea, 'Nick as the unreliable narrator'),
      (CardKind.word, 'boorish'),
      (CardKind.quote, 'So we beat on, boats against the current'),
    ]),
    ('Godaan', 'होरी की गाय', Tier.pro, 'Sana', CardFont.bricolage, [
      (CardKind.idea, 'The cow as Hori’s whole dignity'),
      (CardKind.word, 'mortgage'),
      (CardKind.idea, 'Village debt, chapter by chapter'),
    ]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final signedIn = ref.watch(signedInUidProvider) != null;
    final now = DateTime.now();
    return Stack(
      children: [
        // The glimpse: real tiles, sample data, blurred and inert.
        Positioned.fill(
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  for (final (i, (book, title, tier, name, font, preview)) in _samples.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: PublishedDeckTile(
                        deck: PublishedDeckSummary(
                          id: 'sample-$i',
                          title: title,
                          bookTitle: book,
                          blurb: '',
                          cardCount: 12 + i * 7,
                          preview: [for (final (kind, front) in preview) (kind: kind, front: front)],
                          likes: 18 - i * 5,
                          saves: 9 - i * 2,
                          comments: 4 + i,
                          createdAt: now.subtract(Duration(hours: 3 + i * 20)),
                          author: Author(uid: 'sample', name: name, tier: tier),
                          liked: false,
                          font: font,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(child: ColoredBox(color: c.paper.withValues(alpha: 0.35))),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.rule),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: c.marigold, size: 26),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t.communityLockedTitle, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(t.communityLockedBody, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale, size: 14.5)),
                  const SizedBox(height: 14),
                  for (final (icon, line) in [
                    (Icons.menu_book_outlined, t.communityPerkBrowse),
                    (Icons.bookmark_add_outlined, t.communityPerkSave),
                    (Icons.forum_outlined, t.communityPerkTalk),
                    (Icons.public_rounded, t.communityPerkShare),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 18, color: c.accent),
                          const SizedBox(width: 10),
                          Expanded(child: Text(line, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 14.5))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => unawaited(context.push(signedIn ? '/plans' : '/signin')),
                      child: Text(signedIn ? t.seePlans : t.signIn),
                    ),
                  ),
                  if (!signedIn)
                    Center(
                      child: TextButton(
                        onPressed: () => unawaited(context.push('/plans')),
                        child: Text(t.seePlans, style: uiLabel(hindi: t.isHindi, color: c.accent, scale: scale)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum CommunityAccess { loading, locked, open }

/// Whether this reader may use the community: Pro, Super or an admin.
final communityAccessProvider = Provider<CommunityAccess>((ref) {
  if (ref.watch(signedInUidProvider) == null) return CommunityAccess.locked;
  final account = ref.watch(accountProvider);
  if (account.isLoading && !account.hasValue) return CommunityAccess.loading;
  final a = account.valueOrNull;
  return a != null && (a.tier != Tier.free || a.isAdmin) ? CommunityAccess.open : CommunityAccess.locked;
});
