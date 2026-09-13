// Dictionary tab: search (local prefix matches as you type, full lookup on
// submit), recent lookups, and a word of the day.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/core/models/contracts.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/features/dictionary/entry_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final wordOfTheDayProvider = FutureProvider<DictionaryEntry?>((ref) async {
  final store = ref.watch(localStoreProvider);
  final words = await store.searchWords('', limit: 5000);
  if (words.isEmpty) return null;
  // Deterministic per day, skewed away from the very top (function words).
  final day = DateTime.now().difference(DateTime(2026)).inDays;
  final pool = words.length > 800 ? words.sublist(800) : words;
  return store.entry(pool[day % pool.length]);
});

class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});

  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _text = TextEditingController();
  List<String> _matches = const [];
  Timer? _debounce;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final q = v.trim().toLowerCase();
      final m = q.isEmpty ? const <String>[] : await ref.read(localStoreProvider).searchWords(q, limit: 12);
      if (mounted) setState(() => _matches = m);
    });
  }

  Future<void> _open(String word) async {
    setState(() => _busy = true);
    final outcome = await ref.read(dictionaryRepoProvider).lookupWord(word);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case LookupFound(:final lemma):
        unawaited(ref.read(localStoreProvider).addRecentLookup(lemma));
        ref.invalidate(recentLookupsProvider);
        unawaited(context.push('/word/$lemma'));
      case LookupMissing(:final suggestions, :final offline):
        final h = HindiText(ref.read(settingsProvider).hindiScale);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              offline
                  ? 'और अर्थ देखने के लिए इंटरनेट चाहिए'
                  : suggestions.isEmpty
                      ? 'यह शब्द शब्दकोश में नहीं मिला।'
                      : 'नहीं मिला। क्या आपका मतलब था: ${suggestions.join(', ')}',
              style: h.small(context.colors.paper),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = HindiText(ref.watch(settingsProvider).hindiScale);
    final recent = ref.watch(recentLookupsProvider).valueOrNull ?? const [];
    final wotd = ref.watch(wordOfTheDayProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            Text('शब्दकोश', style: EnglishText.italic(c.inkMuted, size: 22)),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              style: EnglishText.word(c.ink, size: 26),
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'कोई अंग्रेज़ी शब्द',
                hintStyle: h.body(c.inkMuted).copyWith(fontSize: 20),
                suffixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _text.text.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close_rounded, color: c.inkMuted),
                            onPressed: () {
                              _text.clear();
                              _onChanged('');
                            },
                          ),
              ),
              onChanged: _onChanged,
              onSubmitted: (v) => v.trim().isEmpty ? null : _open(v),
            ),
            if (_matches.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final m in _matches)
                _WordRow(word: m, onTap: () => _open(m)),
            ] else if (_text.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('फ़ोन पर नहीं मिला — सर्च दबाकर ऑनलाइन देखें', style: h.small(c.inkMuted)),
            ],
            if (_text.text.isEmpty) ...[
              if (recent.isNotEmpty) ...[
                const SectionLabel('RECENT'),
                for (final w in recent) _WordRow(word: w, onTap: () => _open(w)),
              ],
              if (wotd != null) ...[
                const SectionLabel('WORD OF THE DAY'),
                InkWell(
                  onTap: () => context.push('/word/${wotd.word}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wotd.word, style: EnglishText.word(c.ink, size: 30)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (wotd.ipa.isNotEmpty) Text('/${wotd.ipa}/', style: EnglishText.ipa(c.accent)),
                          Text(wotd.senses.first.partOfSpeech, style: h.small(c.inkMuted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SenseList(senses: wotd.senses, max: 1),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({required this.word, required this.onTap});

  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rule))),
        child: Text(word, style: EnglishText.body(c.ink, size: 20)),
      ),
    );
  }
}
