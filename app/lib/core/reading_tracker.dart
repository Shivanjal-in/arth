// Times how long a reader spends on each page of a book.
//
// A page counts when it's looked at for a few seconds (anything quicker is
// flicking past), and not at all when it sat open so long the phone was
// probably put down. Time while the app is in the background never counts.
// What it collects goes out in sessions: when the reader closes, the app is
// backgrounded, or too long passes.

/// One page's worth of reading.
class PageRead {
  const PageRead({required this.key, required this.ms, required this.at});

  /// Which page: a PDF page number, or an EPUB chapter and page folded together.
  final int key;
  final int ms;
  final DateTime at;
}

/// A stretch of reading in one book.
class ReadingSession {
  const ReadingSession({required this.bookId, required this.startedAt, required this.endedAt, required this.pages});

  final int bookId;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<PageRead> pages;

  /// Time spent on counted pages.
  int get activeMs => pages.fold(0, (sum, p) => sum + p.ms);
}

typedef SessionSink = Future<void> Function(ReadingSession session);

class ReadingTracker {
  ReadingTracker({required this.bookId, required this.sink, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final int bookId;
  final SessionSink sink;
  final DateTime Function() _now;

  /// Quicker than this is flicking, not reading.
  static const minPage = Duration(seconds: 3);

  /// Longer than this on one page: the phone was put down.
  static const maxPage = Duration(minutes: 10);

  DateTime? _sessionStart;
  final List<PageRead> _pages = [];
  int? _key;
  DateTime? _since;

  /// The reader is now on page [key]. Calling again for the same page does nothing.
  void visit(int key) {
    if (key == _key && _since != null) return;
    _closePage();
    _key = key;
    _since = _now();
    _sessionStart ??= _since;
  }

  /// The app went to the background: bank the page being read and write out
  /// what there is, in case the app is never opened again.
  Future<void> pause() async {
    _closePage();
    await _flush();
  }

  /// Back in the foreground, still on the same page.
  void resume() {
    if (_key == null || _since != null) return;
    _since = _now();
    _sessionStart ??= _since;
  }

  /// The reader closed the book.
  Future<void> end() async {
    _closePage();
    _key = null;
    await _flush();
  }

  void _closePage() {
    final key = _key;
    final since = _since;
    _since = null;
    if (key == null || since == null) return;
    final now = _now();
    final spent = now.difference(since);
    if (spent < minPage || spent > maxPage) return;
    _pages.add(PageRead(key: key, ms: spent.inMilliseconds, at: since));
  }

  Future<void> _flush() async {
    final start = _sessionStart;
    _sessionStart = null;
    if (start == null || _pages.isEmpty) {
      _pages.clear();
      return;
    }
    final session = ReadingSession(bookId: bookId, startedAt: _pages.first.at, endedAt: _now(), pages: List.of(_pages));
    _pages.clear();
    await sink(session);
  }
}
