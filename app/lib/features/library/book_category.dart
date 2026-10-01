// Fiction and nonfiction shelves a reader can put a book on. Ids are stored;
// the words are looked up so a language change doesn't rewrite the database.

import 'package:arth/app/providers.dart';
import 'package:arth/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BookShelf { fiction, nonfiction }

@immutable
class BookCategory {
  const BookCategory(this.shelf, this.id);

  final BookShelf shelf;
  final String id;

  static BookCategory? resolve(String? shelf, String? id) {
    if (shelf == null || id == null) return null;
    final group = BookShelf.values.where((s) => s.name == shelf).firstOrNull;
    if (group == null || !categoriesOf(group).contains(id)) return null;
    return BookCategory(group, id);
  }

  String label({required bool hindi}) => _labels['$shelfName:$id']?[hindi ? 1 : 0] ?? id;

  String get shelfName => shelf.name;

  @override
  bool operator ==(Object other) => other is BookCategory && other.shelf == shelf && other.id == id;

  @override
  int get hashCode => Object.hash(shelf, id);
}

const fictionCategories = [
  'romance',
  'mystery',
  'crime',
  'fantasy',
  'thriller',
  'science_fiction',
  'historical_fiction',
  'horror',
  'literary_fiction',
  'young_adult',
  'childrens_fiction',
  'adventure',
  'contemporary_fiction',
  'womens_fiction',
  'historical_romance',
  'western',
  'erotic_fiction',
  'humor_satire',
  'magical_realism',
  'gothic_fiction',
  'dystopian_fiction',
  'post_apocalyptic',
  'war_fiction',
  'political_fiction',
  'religious_fiction',
  'lgbtq_fiction',
  'short_fiction',
  'experimental_fiction',
  'speculative_fiction',
  'other',
];

const nonfictionCategories = [
  'self_help',
  'biography',
  'business',
  'health',
  'history',
  'psychology',
  'religion',
  'true_crime',
  'science',
  'politics',
  'travel',
  'cooking',
  'philosophy',
  'society',
  'parenting',
  'education',
  'how_to',
  'nature',
  'art',
  'sports',
  'crafts',
  'law',
  'medicine',
  'reference',
  'language',
  'military',
  'essays',
  'humor',
  'academic',
  'childrens_nonfiction',
  'other',
];

List<String> categoriesOf(BookShelf shelf) => shelf == BookShelf.fiction ? fictionCategories : nonfictionCategories;

/// What the picker returns. [category] null means the reader cleared it.
class CategoryPick {
  const CategoryPick(this.category);

  final BookCategory? category;
}

Future<CategoryPick?> showCategoryPicker(BuildContext context, WidgetRef ref, {BookCategory? current}) {
  return showModalBottomSheet<CategoryPick>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.72,
      child: _CategoryList(current: current),
    ),
  );
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.current});

  final BookCategory? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(stringsProvider);
    final scale = ref.watch(settingsProvider).hindiScale;
    final style = uiBody(hindi: t.isHindi, color: c.ink, scale: scale, size: 16);
    final heading = uiLabel(hindi: t.isHindi, color: c.inkMuted, scale: scale);

    Widget item(BookShelf shelf, String id) {
      final category = BookCategory(shelf, id);
      final selected = category == current;
      return ListTile(
        title: Text(category.label(hindi: t.isHindi), style: style),
        trailing: selected ? Icon(Icons.check_rounded, color: c.accent) : null,
        onTap: () => Navigator.pop(context, CategoryPick(category)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(t.category, style: uiHeading(hindi: t.isHindi, color: c.ink, scale: scale)),
        ),
        if (current != null)
          ListTile(
            leading: Icon(Icons.clear_rounded, color: c.inkMuted),
            title: Text(t.noCategory, style: style),
            onTap: () => Navigator.pop(context, const CategoryPick(null)),
          ),
        for (final shelf in BookShelf.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(shelf == BookShelf.fiction ? t.fiction : t.nonfiction, style: heading),
          ),
          for (final id in categoriesOf(shelf)) item(shelf, id),
        ],
      ],
    );
  }
}

const _labels = <String, List<String>>{
  'fiction:romance': ['Romance', 'रोमांस'],
  'fiction:mystery': ['Mystery', 'रहस्य'],
  'fiction:crime': ['Crime', 'अपराध'],
  'fiction:fantasy': ['Fantasy', 'फैंटेसी'],
  'fiction:thriller': ['Thriller', 'थ्रिलर'],
  'fiction:science_fiction': ['Science Fiction', 'विज्ञान कथा'],
  'fiction:historical_fiction': ['Historical Fiction', 'ऐतिहासिक कथा'],
  'fiction:horror': ['Horror', 'हॉरर'],
  'fiction:literary_fiction': ['Literary Fiction', 'साहित्यिक कथा'],
  'fiction:young_adult': ['Young Adult', 'युवा'],
  'fiction:childrens_fiction': ["Children's Fiction", 'बच्चों की कथा'],
  'fiction:adventure': ['Adventure', 'रोमांच'],
  'fiction:contemporary_fiction': ['Contemporary Fiction', 'समकालीन कथा'],
  'fiction:womens_fiction': ["Women's Fiction", 'स्त्री कथा'],
  'fiction:historical_romance': ['Historical Romance', 'ऐतिहासिक रोमांस'],
  'fiction:western': ['Western', 'वेस्टर्न'],
  'fiction:erotic_fiction': ['Erotic Fiction', 'कामुक कथा'],
  'fiction:humor_satire': ['Humor & Satire', 'हास्य और व्यंग्य'],
  'fiction:magical_realism': ['Magical Realism', 'जादुई यथार्थ'],
  'fiction:gothic_fiction': ['Gothic Fiction', 'गॉथिक कथा'],
  'fiction:dystopian_fiction': ['Dystopian Fiction', 'डिसटॉपिया'],
  'fiction:post_apocalyptic': ['Post-Apocalyptic Fiction', 'प्रलय के बाद'],
  'fiction:war_fiction': ['War Fiction', 'युद्ध कथा'],
  'fiction:political_fiction': ['Political Fiction', 'राजनीतिक कथा'],
  'fiction:religious_fiction': ['Religious Fiction', 'धार्मिक कथा'],
  'fiction:lgbtq_fiction': ['LGBTQ+ Fiction', 'LGBTQ+ कथा'],
  'fiction:short_fiction': ['Short Fiction', 'लघु कथा'],
  'fiction:experimental_fiction': ['Experimental Fiction', 'प्रयोगात्मक कथा'],
  'fiction:speculative_fiction': ['Speculative Fiction', 'कल्पना कथा'],
  'fiction:other': ['Other', 'अन्य'],
  'nonfiction:self_help': ['Self-Help & Personal Development', 'आत्म-विकास'],
  'nonfiction:biography': ['Biography & Memoir', 'जीवनी और संस्मरण'],
  'nonfiction:business': ['Business & Economics', 'व्यापार और अर्थशास्त्र'],
  'nonfiction:health': ['Health & Wellness', 'स्वास्थ्य'],
  'nonfiction:history': ['History', 'इतिहास'],
  'nonfiction:psychology': ['Psychology', 'मनोविज्ञान'],
  'nonfiction:religion': ['Religion & Spirituality', 'धर्म और आध्यात्म'],
  'nonfiction:true_crime': ['True Crime', 'सच्चा अपराध'],
  'nonfiction:science': ['Science & Technology', 'विज्ञान और तकनीक'],
  'nonfiction:politics': ['Politics & Current Affairs', 'राजनीति'],
  'nonfiction:travel': ['Travel', 'यात्रा'],
  'nonfiction:cooking': ['Cooking, Food & Drink', 'खाना और पेय'],
  'nonfiction:philosophy': ['Philosophy', 'दर्शन'],
  'nonfiction:society': ['Society & Culture', 'समाज और संस्कृति'],
  'nonfiction:parenting': ['Parenting & Family', 'पालन-पोषण'],
  'nonfiction:education': ['Education', 'शिक्षा'],
  'nonfiction:how_to': ['How-To & Instruction', 'कैसे करें'],
  'nonfiction:nature': ['Nature & Environment', 'प्रकृति'],
  'nonfiction:art': ['Art & Photography', 'कला और फ़ोटोग्राफ़ी'],
  'nonfiction:sports': ['Sports & Recreation', 'खेल'],
  'nonfiction:crafts': ['Crafts & Hobbies', 'शिल्प और शौक'],
  'nonfiction:law': ['Law', 'क़ानून'],
  'nonfiction:medicine': ['Medicine', 'चिकित्सा'],
  'nonfiction:reference': ['Reference', 'संदर्भ'],
  'nonfiction:language': ['Language & Linguistics', 'भाषा'],
  'nonfiction:military': ['Military & War', 'सैन्य और युद्ध'],
  'nonfiction:essays': ['Essays & Literary Criticism', 'निबंध और आलोचना'],
  'nonfiction:humor': ['Humor', 'हास्य'],
  'nonfiction:academic': ['Academic & Scholarly', 'अकादमिक'],
  'nonfiction:childrens_nonfiction': ["Children's Nonfiction", 'बच्चों की गैर-कथा'],
  'nonfiction:other': ['Other', 'अन्य'],
};
