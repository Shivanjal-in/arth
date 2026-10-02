import 'dart:async';
import 'dart:math' as math;

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/features/plans/plans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Who made Arth, and how to reach them.
const _portfolioUrl = 'https://zethyst.netlify.app/';
const _whatsAppNumber = '918318876136'; // +91 83188 76136, as wa.me wants it

/// The signature's mauve, the same in both themes.
const _mauve = Color(0xFF9A6A8E);

/// Mauve, deepened toward the ends: 65% mauve with the page's ink at 0% and
/// 100%, pure mauve at the middle, along a 100° line.
LinearGradient _signatureGradient(Color ink) {
  final edge = Color.lerp(ink, _mauve, 0.65)!;
  // CSS 100deg: pointing right and a little down.
  const angle = 100 * math.pi / 180;
  final dx = math.sin(angle);
  final dy = -math.cos(angle);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: [edge, _mauve, edge],
  );
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final scale = ref.watch(settingsProvider).hindiScale;
    final t = ref.watch(stringsProvider);

    Future<void> open(Uri uri) async {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.linkFailed)));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Arth')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('अर्थ', style: const HindiText(1).headline(c.accent).copyWith(fontSize: 48, height: 1.1)),
          const SizedBox(height: 8),
          Text(t.aboutTagline, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale)),
          const SizedBox(height: 28),
          Text('Data sources', style: EnglishText.heading(c.ink, size: 18)),
          const SizedBox(height: 10),
          Text(
            'Dictionary senses, pronunciations, inflected forms and phrases are derived from '
            'the English Wiktionary (en.wiktionary.org), via the kaikki.org machine-readable '
            'extract by Tatu Ylonen. Wiktionary text is available under the Creative Commons '
            'Attribution-ShareAlike License (CC BY-SA 4.0). Hindi explanations are generated '
            'and edited for Arth.',
            style: EnglishText.body(c.ink),
          ),
          const SizedBox(height: 12),
          Text(
            'Word frequencies from wordfreq by Robyn Speer (MIT License). '
            'PDF rendering by pdfrx / PDFium. Fonts: Montserrat, Literata, Mukta, Noto Sans Devanagari, Quintessential and Bricolage Grotesque (SIL Open Font License).',
            style: EnglishText.body(c.ink),
          ),
          const SizedBox(height: 16),
          const LegalLinks(),
          const SizedBox(height: 20),
          Divider(color: c.rule),
          const SizedBox(height: 24),
          // The signature: who made it, the name set as the one bright thing.
          // "Made with ♥ by" — Hindi puts it the other way round: "♥ से बनाया".
          Builder(
            builder: (_) {
              final label = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale);
              final heart = Icon(Icons.favorite_rounded, size: 15, color: c.accent, semanticLabel: t.love);
              return Row(
                children: t.isHindi
                    ? [heart, const SizedBox(width: 5), Text(t.madeWith, style: label)]
                    : [Text(t.madeWith, style: label), const SizedBox(width: 5), heart, const SizedBox(width: 5), Text(t.madeBy, style: label)],
              );
            },
          ),
          const SizedBox(height: 4),
          Semantics(
            link: true,
            label: 'Zethyst, opens zethyst.netlify.app',
            child: Pressable(
              onTap: () => unawaited(open(Uri.parse(_portfolioUrl))),
              scale: 0.98,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => _signatureGradient(c.ink).createShader(bounds),
                    // The mask covers only the child's box; a brush script's
                    // swashes reach past it, so pad the box to take them in.
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 10, 10),
                      child: Text('Zethyst', style: GoogleFonts.kaushanScript(fontSize: 40, height: 1.4, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new_rounded, size: 18, color: _mauve),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Haptics.open();
              unawaited(open(Uri.https('wa.me', '/$_whatsAppNumber', {'text': t.whatsAppHello})));
            },
            icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
            label: Text(t.chatOnWhatsApp, style: uiLabel(hindi: t.isHindi, color: c.ink, scale: scale).copyWith(fontSize: 15)),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }
}
