import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:arth/features/about/about_screen.dart';
import 'package:arth/features/dictionary/dictionary_screen.dart';
import 'package:arth/features/dictionary/word_screen.dart';
import 'package:arth/features/library/library_screen.dart';
import 'package:arth/features/reader/reader_screen.dart';
import 'package:arth/features/saved/saved_screen.dart';
import 'package:arth/features/scan/scan_reader_screen.dart';
import 'package:arth/features/seed/seed_screen.dart';
import 'package:arth/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

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
        GoRoute(
          path: '/scan/:id',
          builder: (_, s) => _ScanRoute(id: int.parse(s.pathParameters['id']!)),
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
      (Icons.bookmark_border_rounded, Icons.bookmark_rounded, t.tabSaved),
      (Icons.person_outline_rounded, Icons.person_rounded, t.tabYou),
    ];
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.paper,
          border: Border(top: BorderSide(color: c.rule)),
        ),
        child: SafeArea(
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
                      onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                    ),
                  ),
              ],
            ),
          ),
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
          Text(label, style: uiLabel(hindi: hindi, color: color, scale: scale).copyWith(fontSize: hindi ? null : 12)),
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
    return ReaderScreen(book: book, filePath: p.join(ref.read(documentsDirProvider), book.path));
  }
}

class _ScanRoute extends ConsumerWidget {
  const _ScanRoute({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).valueOrNull;
    final book = books?.where((b) => b.id == id).firstOrNull;
    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ScanReaderScreen(book: book);
  }
}
