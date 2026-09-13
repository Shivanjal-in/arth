import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final h = HindiText(ref.watch(settingsProvider).hindiScale);
    return Scaffold(
      appBar: AppBar(title: const Text('Arth')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('अर्थ', style: EnglishText.word(c.accent, size: 40)),
          const SizedBox(height: 8),
          Text(
            'अंग्रेज़ी किताबें पढ़ते हुए किसी भी शब्द पर टैप करें — उसका मतलब, इसी वाक्य में, आसान हिंदी में।',
            style: h.body(c.ink),
          ),
          const SizedBox(height: 28),
          Text('DATA SOURCES', style: EnglishText.caps(c.inkMuted)),
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
            'PDF rendering by pdfrx / PDFium. Fonts: Literata, Mukta and Noto Sans Devanagari (SIL Open Font License).',
            style: EnglishText.body(c.ink),
          ),
        ],
      ),
    );
  }
}
