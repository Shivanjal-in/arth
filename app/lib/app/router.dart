import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/features/about/about_screen.dart';
import 'package:arth/features/dictionary/dictionary_screen.dart';
import 'package:arth/features/dictionary/word_screen.dart';
import 'package:arth/features/library/library_screen.dart';
import 'package:arth/features/reader/reader_screen.dart';
import 'package:arth/features/saved/saved_screen.dart';
import 'package:arth/features/seed/seed_screen.dart';
import 'package:arth/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter({required bool needsSeed}) => GoRouter(
      initialLocation: needsSeed ? '/seed' : '/',
      routes: [
        GoRoute(path: '/seed', builder: (_, _) => const SeedScreen()),
        GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
        GoRoute(
          path: '/word/:lemma',
          builder: (_, s) => WordScreen(word: s.pathParameters['lemma']!),
        ),
        GoRoute(
          path: '/read/:id',
          builder: (_, s) => _ReaderRoute(id: int.parse(s.pathParameters['id']!)),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => _Shell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const LibraryScreen())]),
            StatefulShellBranch(
              routes: [GoRoute(path: '/dictionary', builder: (_, _) => const DictionaryScreen())],
            ),
            StatefulShellBranch(routes: [GoRoute(path: '/saved', builder: (_, _) => const SavedScreen())]),
            StatefulShellBranch(
              routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())],
            ),
          ],
        ),
      ],
    );

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.rule))),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'किताबें'),
            NavigationDestination(icon: Icon(Icons.search_rounded), label: 'शब्दकोश'),
            NavigationDestination(icon: Icon(Icons.bookmark_border_rounded), selectedIcon: Icon(Icons.bookmark_rounded), label: 'सहेजे'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'आप'),
          ],
        ),
      ),
    );
  }
}

class _ReaderRoute extends ConsumerWidget {
  const _ReaderRoute({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).valueOrNull;
    final book = books?.where((b) => b.id == id).firstOrNull;
    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ReaderScreen(book: book);
  }
}
