// Search inside the open book: type a keyword, get every place it appears
// with a little context, tap one to jump there. Each reader supplies the
// scan (PDF pages, EPUB chapters) and what a jump does.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One match: [page] is the PDF page or the 1-based chapter; [block] the
/// paragraph within a chapter (null for PDFs).
class SearchHit {
  const SearchHit({
    required this.label,
    required this.before,
    required this.match,
    required this.after,
    required this.page,
    this.block,
  });

  final String label;
  final String before;
  final String match;
  final String after;
  final int page;
  final int? block;
}

/// Feeds hits for [query] to [add], stopping once [cancelled] says so.
typedef SearchRunner = Future<void> Function(String query, void Function(SearchHit hit) add, bool Function() cancelled);

const int kSearchMaxHits = 300;
const int kSearchMinChars = 2;

/// Every case-insensitive occurrence of [query] in [text], with context.
Iterable<SearchHit> hitsIn(String text, String query, {required String label, required int page, int? block}) sync* {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  final pattern = RegExp(RegExp.escape(query.trim()), caseSensitive: false, unicode: true);
  for (final m in pattern.allMatches(flat)) {
    final from = (m.start - 40).clamp(0, flat.length);
    final to = (m.end + 60).clamp(0, flat.length);
    yield SearchHit(
      label: label,
      before: '${from > 0 ? '…' : ''}${flat.substring(from, m.start)}',
      match: flat.substring(m.start, m.end),
      after: '${flat.substring(m.end, to)}${to < flat.length ? '…' : ''}',
      page: page,
      block: block,
    );
  }
}

Future<void> showSearchSheet(BuildContext context, {required SearchRunner search, required void Function(SearchHit hit) onJump}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => _SearchSheet(
        search: search,
        onJump: (h) {
          Navigator.pop(ctx);
          onJump(h);
        },
      ),
    );

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet({required this.search, required this.onJump});

  final SearchRunner search;
  final void Function(SearchHit hit) onJump;

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _field = TextEditingController();
  final List<SearchHit> _hits = [];
  Timer? _debounce;
  int _run = 0;
  bool _running = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _run++;
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _run++;
    if (q.trim().length < kSearchMinChars) {
      setState(() {
        _hits.clear();
        _running = false;
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => unawaited(_start(q.trim())));
  }

  Future<void> _start(String query) async {
    final run = ++_run;
    setState(() {
      _hits.clear();
      _running = true;
      _searched = true;
    });
    var pending = false;
    try {
      await widget.search(query, (hit) {
        if (run != _run || !mounted || _hits.length >= kSearchMaxHits) return;
        _hits.add(hit);
        if (!pending) {
          pending = true;
          scheduleMicrotask(() {
            pending = false;
            if (run == _run && mounted) setState(() {});
          });
        }
      }, () => run != _run || !mounted || _hits.length >= kSearchMaxHits);
    } on Exception {
      // a page that won't load just contributes no hits
    }
    if (run == _run && mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: mq.size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _field,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (q) {
                  _debounce?.cancel();
                  if (q.trim().length >= kSearchMinChars) unawaited(_start(q.trim()));
                },
                decoration: InputDecoration(
                  hintText: t.searchInBook,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _running
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : (_field.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _field.clear();
                                _onChanged('');
                              },
                            )),
                ),
              ),
            ),
            Expanded(
              child: _hits.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _searched && !_running ? t.noMatches : t.searchHelp,
                          textAlign: TextAlign.center,
                          style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _hits.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: c.inkMuted.withValues(alpha: 0.2)),
                      itemBuilder: (_, i) {
                        final h = _hits[i];
                        return ListTile(
                          onTap: () => widget.onJump(h),
                          title: Text.rich(
                            TextSpan(
                              style: EnglishText.body(c.ink, size: 14.5),
                              children: [
                                TextSpan(text: h.before),
                                TextSpan(
                                  text: h.match,
                                  style: TextStyle(fontWeight: FontWeight.w700, color: c.accent, backgroundColor: c.highlight),
                                ),
                                TextSpan(text: h.after),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(h.label, style: EnglishText.label(c.inkMuted, size: 12)),
                          ),
                        );
                      },
                    ),
            ),
            if (_hits.length >= kSearchMaxHits)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(t.searchTruncated, style: uiBody(hindi: t.isHindi, color: c.inkMuted, scale: scale)),
              ),
          ],
        ),
      ),
    );
  }
}
