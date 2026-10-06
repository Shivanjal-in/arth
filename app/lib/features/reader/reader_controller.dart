// Tooltip state for the reader: what is open, anchored where, and how far the
// local → context → translation pipeline has got.

import 'dart:async';
import 'dart:ui';

import 'package:arth/app/account_providers.dart';
import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/core/models/contracts.dart';
import 'package:arth/core/text/page_text_index.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/dictionary_repo.dart';
import 'package:arth/data/local_store.dart';
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
    this.contextErrorCode,
    this.contextOffered = false,
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

  /// The API's code when /context failed; `UNAUTHORIZED` or
  /// `QUOTA_EXCEEDED` turn the in-context block into a prompt.
  final String? contextErrorCode;

  /// A common word: the AI sense-pick waits for the reader to ask for it.
  final bool contextOffered;

  /// Word rects to highlight (the phrase, when one matched).
  final List<Rect>? highlight;

  bool get loading => outcome == null;

  WordTooltipState copyWith({
    LookupOutcome? outcome,
    ContextResult? context,
    bool? contextLoading,
    String? contextError,
    String? contextErrorCode,
    bool? contextOffered,
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
        contextErrorCode: contextErrorCode ?? this.contextErrorCode,
        contextOffered: contextOffered ?? this.contextOffered,
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
    this.errorCode,
    this.done = false,
  });

  final String text;
  final String? hindi;
  final String? simpleMeaning;
  final List<BilingualPair>? difficultWords;
  /// Server (Hindi) message; the widget localizes via [errorCode].
  final String? error;
  final String? errorCode;
  final bool done;

  SentenceTooltipState copyWith({
    String? hindi,
    String? simpleMeaning,
    List<BilingualPair>? difficultWords,
    String? error,
    String? errorCode,
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
        errorCode: errorCode ?? this.errorCode,
        done: done ?? this.done,
      );
}

/// The highlighter's colour bar, over a selected run of words or an existing
/// highlight.
class HighlightBarState extends ReaderTooltip {
  const HighlightBarState({
    required super.anchor,
    required super.page,
    required this.text,
    this.existing,
  });

  /// The selected text (for the translate action).
  final String text;

  /// The highlight being edited, or null for a new selection.
  final Highlight? existing;
}

/// Words ranked at or above this (1 = most common) show their dictionary entry
/// on a tap; the AI sense-pick is one more tap away.
const int kAiOnRequestRank = 8000;

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
    ({int id, String title})? book,
  }) async {
    final gen = ++_generation;
    unawaited(_translation?.cancel());
    Haptics.open();
    state = WordTooltipState(
      anchor: word.rect,
      page: page,
      token: word.text,
      key: word.key,
      sentence: sentence,
      highlight: [word.rect],
    );

    final outcome = await _repo.lookupAt(tokens, index);
    _trackLookup(outcome, 'reader');
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
        // Common words are answered from the dictionary; asking the AI which
        // sense fits is the reader's call (it counts against their allowance).
        // With AI lookup off, every word waits for that tap.
        final rank = await ref.read(localStoreProvider).rankOf(outcome.lemma);
        if (gen != _generation) return;
        if (!ref.read(settingsProvider).aiLookup || (rank != null && rank <= kAiOnRequestRank)) {
          state = s.copyWith(contextOffered: true);
          return;
        }
        // Signed out or out of allowance: say so rather than ask the server.
        final blocked = _blockedCode('word');
        if (blocked != null) {
          state = s.copyWith(contextErrorCode: blocked);
          return;
        }
        s = s.copyWith(contextLoading: true);
        state = s;
        unawaited(_resolveContext(gen, outcome.lemma, sentence));
        return;
      }
    }
    state = s;
  }

  /// The reader asked which sense fits this sentence (common words only
  /// offer it; rarer ones resolve on their own).
  void explainInContext() {
    final s = state;
    if (s is! WordTooltipState || s.outcome is! LookupFound) return;
    final blocked = _blockedCode('word');
    if (blocked != null) {
      state = s.copyWith(contextOffered: false, contextErrorCode: blocked);
      return;
    }
    state = s.copyWith(contextOffered: false, contextLoading: true);
    unawaited(_resolveContext(_generation, (s.outcome! as LookupFound).lemma, s.sentence));
  }

  Future<void> _resolveContext(int gen, String lemma, String sentence) async {
    ref.read(analyticsProvider).track('AI Lookup', {'kind': 'word'});
    try {
      final r = await _repo.contextFor(word: lemma, sentence: sentence);
      if (gen != _generation) return;
      final s = state;
      if (s is WordTooltipState) {
        state = s.copyWith(context: r, contextLoading: false);
      }
    } on ApiFailure catch (e) {
      // Step 5: the dictionary entry stays; never replace a meaning with an error.
      _onAiFailure(e);
      if (gen != _generation) return;
      final s = state;
      if (s is WordTooltipState) {
        state = s.copyWith(contextLoading: false, contextError: e.message, contextErrorCode: e.code);
      }
    }
  }

  /// `UNAUTHORIZED` / `QUOTA_EXCEEDED` when AI answers aren't available to
  /// this reader right now; null when they are.
  /// Tracked as an AI request turned away, of [kind] (word / sentence).
  String? _blockedCode(String kind) {
    final code = switch (ref.read(aiAccessProvider)) {
      AiAccess.signedOut => 'UNAUTHORIZED',
      AiAccess.exhausted => (ref.read(usageProvider)?.phone ?? false) ? 'QUOTA_PHONE' : 'QUOTA_EXCEEDED',
      AiAccess.open || AiAccess.allowed => null,
    };
    if (code != null) ref.read(analyticsProvider).track('AI Blocked', {'kind': kind, 'reason': code});
    return code;
  }

  void _trackLookup(LookupOutcome outcome, String from) => ref.read(analyticsProvider).track('Word Looked Up', {
        'from': from,
        'found': outcome is LookupFound,
        if (outcome is LookupFound) 'source': outcome.source.name,
        if (outcome is LookupFound) 'phrase': outcome.phrase != null,
      });

  /// The server says the allowance ran out (another device used it, say):
  /// refetch the account so every screen shows the real count.
  void _onAiFailure(ApiFailure e) {
    if (e.code == 'QUOTA_EXCEEDED' || e.code == 'QUOTA_PHONE') ref.invalidate(accountProvider);
  }

  /// A run of words was selected (or an existing highlight long-pressed).
  void showHighlightBar({
    required Rect anchor,
    required int page,
    required String text,
    Highlight? existing,
  }) {
    _generation++;
    unawaited(_translation?.cancel());
    Haptics.choose();
    state = HighlightBarState(anchor: anchor, page: page, text: text, existing: existing);
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
    final blocked = _blockedCode('sentence');
    if (blocked != null) {
      state = SentenceTooltipState(anchor: anchor, page: page, text: text, error: '', errorCode: blocked, done: true);
      return;
    }
    state = SentenceTooltipState(anchor: anchor, page: page, text: text);
    ref.read(analyticsProvider).track('AI Lookup', {'kind': 'sentence'});
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
              errorCode: (ev.data['code'] as String?) ?? 'UPSTREAM_FAILED',
              done: true,
            );
        }
      },
      onError: (Object e) {
        if (e is ApiFailure) _onAiFailure(e);
        if (gen != _generation) return;
        final s = state;
        if (s is! SentenceTooltipState) return;
        state = s.copyWith(
          error: e is ApiFailure ? e.message : 'अनुवाद नहीं हो पाया।',
          errorCode: e is ApiFailure ? e.code : 'INTERNAL',
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
