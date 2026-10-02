// A one-time guide to the reader's gestures, shown over a book the first time
// the reader opens one (and again from the reading settings). Wraps the
// reader's body; the guide sits on top until dismissed.

import 'dart:async';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _seenKey = 'reader_guide_seen';

class ReaderGuide extends ConsumerStatefulWidget {
  const ReaderGuide({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReaderGuide> createState() => _ReaderGuideState();
}

class _ReaderGuideState extends ConsumerState<ReaderGuide> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    unawaited(_firstTime());
  }

  Future<void> _firstTime() async {
    final seen = await ref.read(localStoreProvider).get(_seenKey);
    if (seen == null && mounted) setState(() => _show = true);
  }

  void _close() {
    setState(() => _show = false);
    unawaited(ref.read(localStoreProvider).set(_seenKey, 'true'));
  }

  @override
  Widget build(BuildContext context) {
    // The reading settings can ask for the guide again.
    ref.listen(readerGuideRequestProvider, (_, asked) {
      if (!asked) return;
      ref.read(readerGuideRequestProvider.notifier).state = false;
      setState(() => _show = true);
    });
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_show) Positioned.fill(child: _Guide(onClose: _close)),
      ],
    );
  }
}

class _Guide extends ConsumerWidget {
  const _Guide({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final s = ref.watch(settingsProvider);
    final scale = s.hindiScale;
    final rows = <(IconData, String)>[
      if (s.bookPages) (Icons.swipe_rounded, t.guideSwipe) else (Icons.swap_vert_rounded, t.guideScroll),
      (Icons.touch_app_rounded, t.guideTap),
      (Icons.ads_click_rounded, t.guideHold),
      (Icons.bookmark_border_rounded, t.guideBookmark),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: c.ink.withValues(alpha: 0.72),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                // Taps on the card itself don't dismiss; the button does.
                child: GestureDetector(
                  onTap: () {},
                  child: HardShadow(
                    depth: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.guideTitle, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
                          const SizedBox(height: 16),
                          for (final (icon, text) in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: c.marigold.withValues(alpha: 0.35), border: Border.all(color: c.ink, width: 1.5)),
                                    child: Icon(icon, color: c.ink, size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(text, style: uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 15)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(onPressed: onClose, child: Text(t.guideGotIt)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
