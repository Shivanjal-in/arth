// For the readers: times the pages as the reader turns them (see
// core/reading_tracker.dart) and keeps the habit screen's log up to date.
// Call [trackPage] whenever the reader lands on a page.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/core/reading_tracker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

mixin ReadingTracking<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final ReadingTracker _tracker;
  late final AppLifecycleListener _lifecycle;

  /// The book being read.
  int get trackedBookId;

  @override
  void initState() {
    super.initState();
    // Captured now: `ref` can't be used once the widget is disposing.
    final store = ref.read(localStoreProvider);
    _tracker = ReadingTracker(bookId: trackedBookId, sink: store.saveReadingSession);
    _lifecycle = AppLifecycleListener(
      onResume: _tracker.resume,
      onHide: () => unawaited(_tracker.pause()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_tracker.end());
    super.dispose();
  }

  /// The reader is on page [key] (any int that is the same for the same page).
  void trackPage(int key) => _tracker.visit(key);
}
