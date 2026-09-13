// Tooltip state for the reader: what is open, anchored where, and how far the
// local → context → translation pipeline has got.

import 'dart:async';
import 'dart:ui';

import 'package:arth/app/providers.dart';
import 'package:arth/core/models/contracts.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class ReaderTooltip {
  const ReaderTooltip({required this.anchor, required this.page});

  /// Document-space rect the tooltip hangs off.
  final Rect anchor;
  final int page;
}

class WordTooltipState extends ReaderTooltip {
  const WordTooltipState({
    required super.anchor,
    required super.page,
    required this.token,
    required this.key,
    required this.sentence,
    this.outcome,
    this.context,
    this.contextLoading = false,
    this.contextError,
    this.highlight,
  });

  /// Raw token as tapped.
  final String token;

  /// Normalized dictionary key.
  final String key;
  final String sentence;
  final LookupOutcome? outcome;
  final ContextResult? context;
  final bool contextLoading;
  final String? contextError;

  /// Word rects to highlight (the phrase, when one matched).
  final List<Rect>? highlight;

  bool get loading => outcome == null;

  WordTooltipState copyWith({
    LookupOutcome? outcome,
    ContextResult? context,
    bool? contextLoading,
    String? contextError,
    List<Rect>? highlight,
    Rect? anchor,
  }) =>
      WordTooltipState(
        anchor: anchor ?? this.anchor,
        page: page,
        token: token,
        key: key,
        sentence: sentence,
        outcome: outcome ?? this.outcome,
        context: context ?? this.context,
        contextLoading: contextLoading ?? this.contextLoading,
        contextError: contextError ?? this.contextError,
        highlight: highlight ?? this.highlight,
      );
}

class SentenceTooltipState extends ReaderTooltip {
  const SentenceTooltipState({
    required super.anchor,
    required super.page,
    required this.text,
    this.hindi,
    this.simpleMeaning,
    this.difficultWords,
    this.error,
    this.done = false,
  });

  final String text;
  final String? hindi;
  final String? simpleMeaning;
  final List<BilingualPair>? difficultWords;
  final String? error;
  final bool done;

  SentenceTooltipState copyWith({
    String? hindi,
    String? simpleMeaning,
    List<BilingualPair>? difficultWords,
    String? error,
    bool? done,
  }) =>
      SentenceTooltipState(
        anchor: anchor,
        page: page,
        text: text,
        hindi: hindi ?? this.hindi,
        simpleMeaning: simpleMeaning ?? this.simpleMeaning,
        difficultWords: difficultWords ?? this.difficultWords,
        error: error ?? this.error,
        done: done ?? this.done,
      );
}

final AutoDisposeNotifierProvider<ReaderController, ReaderTooltip?> readerControllerProvider =
    NotifierProvider.autoDispose<ReaderController, ReaderTooltip?>(ReaderController.new);

class ReaderController extends AutoDisposeNotifier<ReaderTooltip?> {
  int _generation = 0;
  StreamSubscription<SseEvent>? _translation;

  @override
  ReaderTooltip? build() {
    ref.onDispose(() => _translation?.cancel());
    return null;
  }

  DictionaryRepo get _repo => ref.read(dictionaryRepoProvider);

  void dismiss() {
    _generation++;
    unawaited(_translation?.cancel());
    _translation = null;
    state = null;
  }

  /// Tap flow steps 1–5 for one word. [sentence] is already normalized and
  /// stitched across pages; [tokens] are the neighbours for phrase match.
  Future<void> showWord({
    required PageWord word,
    required int page,
    required String sentence,
    required List<String> tokens,
    required int index,
    required List<Rect> Function(int start, int count) rectsForWindow,
  }) async {
    final gen = ++_generation;
    unawaited(_translation?.cancel());
    state = WordTooltipState(
      anchor: word.rect,
      page: page,
      token: word.text,
      key: word.key,
      sentence: sentence,
      highlight: [word.rect],
    );

    final outcome = await _repo.lookupAt(tokens, index);
    if (gen != _generation) return;
    var s = (state! as WordTooltipState).copyWith(outcome: outcome);
    if (outcome is LookupFound && outcome.phrase != null) {
      final p = outcome.phrase!;
      final rects = rectsForWindow(p.start, p.tokenCount);
      s = s.copyWith(
        highlight: rects,
        anchor: rects.fold<Rect?>(null, (a, r) => a == null ? r : a.expandToInclude(r)),
      );
    }
    if (outcome is LookupFound) {
      unawaited(ref.read(localStoreProvider).addRecentLookup(outcome.lemma));
      // Step 4: context, in parallel with showing the entry. Single-sense
      // entries have nothing to disambiguate.
      if (outcome.entry.senses.length > 1) {
        s = s.copyWith(contextLoading: true);
        state = s;
        unawaited(_resolveContext(gen, outcome.lemma, sentence));
        return;
      }
    }
    state = s;
  }

  Future<void> _resolveContext(int gen, String lemma, String sentence) async {
    try {
      final r = await _repo.contextFor(word: lemma, sentence: sentence);
      if (gen != _generation) return;
      final s = state;
      if (s is WordTooltipState) {
        state = s.copyWith(context: r, contextLoading: false);
      }
    } on ApiFailure catch (e) {
      // Step 5: the dictionary entry stays; never replace a meaning with an error.
      if (gen != _generation) return;
      final s = state;
      if (s is WordTooltipState) {
        state = s.copyWith(contextLoading: false, contextError: e.message);
      }
    }
  }

  /// Selection → translation, streamed.
  void showSentence({
    required String text,
    required Rect anchor,
    required int page,
    String? context,
  }) {
    final gen = ++_generation;
    unawaited(_translation?.cancel());
    state = SentenceTooltipState(anchor: anchor, page: page, text: text);
    _translation = _repo.translate(text: text, context: context).listen(
      (ev) {
        if (gen != _generation) return;
        final s = state;
        if (s is! SentenceTooltipState) return;
        switch (ev.event) {
          case 'hindi':
            state = s.copyWith(hindi: ev.data['hindi'] as String?);
          case 'simpleMeaning':
            state = s.copyWith(simpleMeaning: ev.data['simpleMeaning'] as String?);
          case 'difficultWords':
            final list = (ev.data['difficultWords'] as List<dynamic>? ?? const [])
                .map((e) => BilingualPair.fromJson(e as Map<String, dynamic>))
                .toList();
            state = s.copyWith(difficultWords: list);
          case 'done':
            final r = TranslationResult.fromJson(ev.data);
            state = s.copyWith(
              hindi: r.hindi,
              simpleMeaning: r.simpleMeaning,
              difficultWords: r.difficultWords
                  .map((d) => BilingualPair(en: d.en, hi: d.hi))
                  .toList(),
              done: true,
            );
          case 'error':
            state = s.copyWith(
              error: (ev.data['message'] as String?) ?? 'अनुवाद नहीं हो पाया।',
              done: true,
            );
        }
      },
      onError: (Object e) {
        if (gen != _generation) return;
        final s = state;
        if (s is! SentenceTooltipState) return;
        state = s.copyWith(
          error: e is ApiFailure ? e.message : 'अनुवाद नहीं हो पाया।',
          done: true,
        );
      },
      onDone: () {
        if (gen != _generation) return;
        final s = state;
        if (s is SentenceTooltipState && !s.done) {
          state = s.copyWith(done: true);
        }
      },
    );
  }
}
