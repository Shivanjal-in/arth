// Dictionary tab: search (local prefix matches as you type, full lookup on
// submit), recent lookups, and a word of the day.

import 'dart:async';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/feel.dart';
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

  Future<void> _forgetRecent(String word) async {
    final t = ref.read(stringsProvider);
    final c = context.colors;
    final scale = ref.read(settingsProvider).hindiScale;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(t.removeRecent, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
        content: Text(word, style: EnglishText.body(c.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.no)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(localStoreProvider).removeRecentLookup(word);
    ref.invalidate(recentLookupsProvider);
  }

  Future<void> _open(String word) async {
    setState(() => _busy = true);
    final outcome = await ref.read(dictionaryRepoProvider).lookupWord(word);
    ref.read(analyticsProvider).track('Word Looked Up', {
      'from': 'dictionary',
      'found': outcome is LookupFound,
      if (outcome is LookupFound) 'source': outcome.source.name,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case LookupFound(:final lemma):
        unawaited(ref.read(localStoreProvider).addRecentLookup(lemma));
        ref.invalidate(recentLookupsProvider);
        unawaited(context.push('/word/$lemma'));
      case LookupMissing(:final suggestions, :final offline):
        final t = ref.read(stringsProvider);
        final scale = ref.read(settingsProvider).hindiScale;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              offline
                  ? t.offline
                  : suggestions.isEmpty
                      ? t.notFound
                      : '${t.notFound} ${t.didYouMean}: ${suggestions.join(', ')}',
              style: uiBody(hindi: t.isHindi, color: context.colors.paper, scale: scale, size: 13.5),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final h = HindiText(settings.hindiScale);
    final t = ref.watch(stringsProvider);
    final recent = ref.watch(recentLookupsProvider).valueOrNull ?? const [];
    final wotd = ref.watch(wordOfTheDayProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            Text(t.dictionaryTitle, style: uiTitle(hindi: t.isHindi, color: c.ink, scale: settings.hindiScale)),
            const SizedBox(height: 18),
            TextField(
              controller: _text,
              style: EnglishText.word(c.ink, size: 26),
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.searchHint,
                hintStyle: t.isHindi ? h.body(c.inkMuted).copyWith(fontSize: 20) : EnglishText.body(c.inkMuted, size: 20),
                prefixIcon: Icon(Icons.search_rounded, color: c.inkMuted),
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
              Text(t.notOnDevice, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: settings.hindiScale, size: 13)),
            ],
            if (_text.text.isEmpty) ...[
              if (recent.isNotEmpty) ...[
                SectionLabel(t.recent),
                for (final w in recent) _WordRow(word: w, onTap: () => _open(w), onLongPress: () => _forgetRecent(w)),
              ],
              if (wotd != null) ...[
                SectionLabel(t.wordOfTheDay),
                Pressable.card(
                  onTap: () => context.push('/word/${wotd.word}'),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(wotd.word, style: EnglishText.word(c.accent, size: 32)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (wotd.ipa.isNotEmpty) Text('/${wotd.ipa}/', style: EnglishText.ipa(c.inkMuted)),
                              Text(wotd.senses.first.partOfSpeech, style: h.small(c.inkMuted)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SenseList(senses: wotd.senses, max: 1),
                        ],
                      ),
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
  const _WordRow({required this.word, required this.onTap, this.onLongPress});

  final String word;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rule))),
        child: Text(word, style: EnglishText.body(c.ink, size: 20)),
      ),
    );
  }
}
