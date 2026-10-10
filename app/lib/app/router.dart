import 'dart:async';

import 'package:arth/app/feel.dart';
import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/data/local_store.dart';
import 'package:arth/features/about/about_screen.dart';
import 'package:arth/features/account/profile_screen.dart';
import 'package:arth/features/account/sign_in_screen.dart';
import 'package:arth/features/admin/admin_screen.dart';
import 'package:arth/features/ads/ads.dart';
import 'package:arth/features/cards/cards_screen.dart';
import 'package:arth/features/cards/deck_screen.dart';
import 'package:arth/features/cards/review_screen.dart';
import 'package:arth/features/community/community_screen.dart';
import 'package:arth/features/community/published_deck_screen.dart';
import 'package:arth/features/dictionary/dictionary_screen.dart';
import 'package:arth/features/dictionary/word_screen.dart';
import 'package:arth/features/epub/epub_reader_screen.dart';
import 'package:arth/features/habit/reading_habit_screen.dart';
import 'package:arth/features/library/library_screen.dart';
import 'package:arth/features/plans/plans_screen.dart';
import 'package:arth/features/reader/reader_screen.dart';
import 'package:arth/features/scan/scan_reader_screen.dart';
import 'package:arth/features/seed/seed_screen.dart';
import 'package:arth/features/settings/settings_screen.dart';
import 'package:arth/features/vocabulary/vocabulary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

GoRouter buildRouter({required bool needsSeed}) => GoRouter(
      initialLocation: needsSeed ? '/seed' : '/',
      routes: [
        GoRoute(path: '/seed', builder: (_, _) => const SeedScreen()),
        GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
        GoRoute(path: '/archive', builder: (_, _) => const ArchiveScreen()),
        GoRoute(path: '/signin', builder: (_, _) => const SignInScreen()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(path: '/habit', builder: (_, _) => const ReadingHabitScreen()),
        GoRoute(path: '/plans', builder: (_, _) => const PlansScreen()),
        GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
        GoRoute(path: '/community/deck/:id', builder: (_, s) => PublishedDeckScreen(id: s.pathParameters['id']!)),
        GoRoute(
          path: '/word/:lemma',
          builder: (_, s) => WordScreen(word: s.pathParameters['lemma']!),
        ),
        // Readers take ?page= (EPUB: chapter) and ?block= to open at a place
        // other than where the reader left off (a card, a bookmark).
        GoRoute(
          path: '/read/:id',
          builder: (_, s) => _ReaderRoute(id: int.parse(s.pathParameters['id']!), at: _placeOf(s)),
        ),
        GoRoute(
          path: '/epub/:id',
          builder: (_, s) => _EpubRoute(id: int.parse(s.pathParameters['id']!), at: _placeOf(s)),
        ),
        GoRoute(
          path: '/scan/:id',
          builder: (_, s) => _ScanRoute(id: int.parse(s.pathParameters['id']!), at: _placeOf(s)),
        ),
        GoRoute(
          path: '/vocabulary',
          builder: (_, s) => VocabularyScreen(
            bookId: int.tryParse(s.uri.queryParameters['book'] ?? ''),
            bookTitle: s.uri.queryParameters['title'],
          ),
        ),
        GoRoute(path: '/deck', builder: (_, s) => DeckScreen(deck: deckRefFrom(s.uri.queryParameters))),
        GoRoute(
          path: '/deck/review',
          builder: (_, s) => ReviewScreen(
            deck: deckRefFrom(s.uri.queryParameters),
            mode: s.uri.queryParameters['mode'] == 'practice' ? ReviewMode.practice : ReviewMode.replay,
          ),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => _Shell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const LibraryScreen())]),
            StatefulShellBranch(
              routes: [GoRoute(path: '/dictionary', builder: (_, _) => const DictionaryScreen())],
            ),
            StatefulShellBranch(routes: [GoRoute(path: '/cards', builder: (_, _) => const CardsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/community', builder: (_, _) => const CommunityScreen())]),
            StatefulShellBranch(
              routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())],
            ),
          ],
        ),
      ],
    );

class _Shell extends ConsumerWidget {
  const _Shell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final items = [
      (Icons.menu_book_outlined, Icons.menu_book_rounded, t.tabLibrary),
      (Icons.search_rounded, Icons.search_rounded, t.tabDictionary),
      (Icons.style_outlined, Icons.style_rounded, t.tabCards),
      (Icons.forum_outlined, Icons.forum_rounded, t.tabCommunity),
      (Icons.person_outline_rounded, Icons.person_rounded, t.tabYou),
    ];
    // Free tier: a banner above the tabs, except on You (settings, account).
    final ads = ref.watch(showAdsProvider) && shell.currentIndex != 4;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.paper,
          border: Border(top: BorderSide(color: c.rule)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ads) const Center(child: AdBanner()),
            SafeArea(
              top: false,
              child: SizedBox(
                height: 62,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _NavItem(
                          icon: items[i].$1,
                          selectedIcon: items[i].$2,
                          label: items[i].$3,
                          selected: shell.currentIndex == i,
                          hindi: t.isHindi,
                          scale: scale,
                          onTap: () {
                            if (i != shell.currentIndex) Haptics.choose();
                            shell.goBranch(i, initialLocation: i == shell.currentIndex);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + label; the selected tab carries a short lac-red underline — the
/// one mark the reference design used for "you are here".
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.hindi,
    required this.scale,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool hindi;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.accent : c.inkMuted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? selectedIcon : icon, size: 22, color: color),
          const SizedBox(height: 3),
          // Five tabs: a long label shrinks to fit rather than wrapping.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: uiLabel(hindi: hindi, color: color, scale: scale).copyWith(fontSize: hindi ? null : 12)),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 22 : 0,
            height: 2,
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(1)),
          ),
        ],
      ),
    );
  }
}

/// Where a reader route asks to open: `?page=` and `?block=`.
BookPlace? _placeOf(GoRouterState s) {
  final page = int.tryParse(s.uri.queryParameters['page'] ?? '');
  return page == null ? null : (page: page, block: int.tryParse(s.uri.queryParameters['block'] ?? ''));
}

class _ReaderRoute extends ConsumerWidget {
  const _ReaderRoute({required this.id, this.at});

  final int id;
  final BookPlace? at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).valueOrNull;
    final book = books?.where((b) => b.id == id).firstOrNull;
    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ReaderScreen(book: book, filePath: p.join(ref.read(documentsDirProvider), book.path), initialPage: at?.page);
  }
}

class _EpubRoute extends ConsumerWidget {
  const _EpubRoute({required this.id, this.at});

  final int id;
  final BookPlace? at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).valueOrNull;
    final book = books?.where((b) => b.id == id).firstOrNull;
    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return EpubReaderScreen(book: book, filePath: p.join(ref.read(documentsDirProvider), book.path), initialPlace: at);
  }
}

class _ScanRoute extends ConsumerWidget {
  const _ScanRoute({required this.id, this.at});

  final int id;
  final BookPlace? at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).valueOrNull;
    final book = books?.where((b) => b.id == id).firstOrNull;
    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ScanReaderScreen(book: book, initialPage: at?.page);
  }
}

/// The tab a screen belongs under, for opening it from a notification with
/// something to go back to. Null for the tabs themselves.
String? tabUnder(String location) {
  final path = Uri.parse(location).path;
  const tabs = {'/', '/dictionary', '/cards', '/community', '/settings'};
  if (tabs.contains(path)) return null;
  if (path.startsWith('/deck') || path.startsWith('/word')) return '/cards';
  if (path.startsWith('/community')) return '/community';
  if (path == '/plans' || path == '/profile' || path == '/admin' || path == '/about') return '/settings';
  return '/';
}

/// Opens a notification's screen on top of its tab: back, ✕ and Finish then
/// lead somewhere, instead of the screen being the only one there is.
void openFromNotification(GoRouter router, String location) {
  final tab = tabUnder(location);
  if (tab == null) {
    router.go(location);
    return;
  }
  router.go(tab);
  unawaited(router.push(location));
}
