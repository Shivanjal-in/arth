import 'package:arth/data/account.dart';
import 'package:arth/data/community.dart';
import 'package:arth/data/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  var n = 0;
  Future<LocalStore> fresh() async {
    final path = '${await factory.getDatabasesPath()}/community_test_${n++}.db';
    await factory.deleteDatabase(path);
    return LocalStore.openAt(path, factory: factory);
  }

  test('a deck page parses: author, cards, comments with replies', () {
    final deck = PublishedDeck.fromJson({
      'id': 'd1', 'title': 'What stayed', 'bookTitle': 'Emma', 'blurb': '', 'cardCount': 2, //
      'preview': [{'kind': 'idea', 'front': 'Who is Knightley?'}],
      'likes': 3, 'saves': 1, 'comments': 2, 'createdAt': 1_790_000_000_000, 'liked': true,
      'author': {'uid': 'u1', 'name': 'Ana', 'photoUrl': null, 'tier': 'super'},
      'bookKey': 'k', 'hidden': false, 'mine': false,
      'cards': [
        {'kind': 'idea', 'front': 'Who is Knightley?', 'back': 'Emma’s neighbour', 'note': '', 'location': 'Chapter 1'},
        {'kind': 'quote', 'front': 'Handsome, clever, and rich', 'back': '', 'note': '', 'location': null},
      ],
      'thread': [
        {'id': 'c1', 'parentId': null, 'text': 'Lovely', 'createdAt': 1, 'hidden': false, 'mine': true, 'author': {'uid': 'u2', 'name': 'Ben', 'tier': 'free'}},
        {'id': 'c2', 'parentId': 'c1', 'text': 'Thanks!', 'createdAt': 2, 'hidden': false, 'mine': false, 'author': {'uid': 'u1', 'name': 'Ana', 'tier': 'super'}},
      ],
    });
    expect(deck.summary.author.tier, Tier.superTier);
    expect(deck.summary.liked, isTrue);
    expect(deck.cards.map((c) => c.kind), [CardKind.idea, CardKind.quote]);
    expect(deck.cards.first.asFlashcard(0).location, 'Chapter 1');
    expect(deck.comments.last.parentId, 'c1');
    expect(deck.comments.first.mine, isTrue);
    expect(deck.removed, isFalse);
  });

  test('saving a deck copies its cards, attached to the same book if you have it — or later', () async {
    final store = await fresh();
    final emma = await store.addBook(title: 'Emma', path: 'emma.epub', kind: BookKind.epub);
    await store.setContentKey(emma.id, 'key-emma');
    final cards = [
      (kind: CardKind.idea, front: 'First', back: 'a', note: '', location: 'Chapter 1'),
      (kind: CardKind.word, front: 'Second', back: 'b', note: 'n', location: 'Chapter 2'),
    ];
    await store.saveDeckCards(bookTitle: 'Emma', bookKey: 'key-emma', cards: cards);
    expect((await store.flashcards(bookId: emma.id)).map((c) => c.front), ['First', 'Second'], reason: 'in the author’s order, on your copy');
    expect((await store.pendingCards()).length, 2, reason: 'your copies sync like your own cards');

    await store.saveDeckCards(bookTitle: 'Persuasion', bookKey: 'key-p', cards: cards);
    final later = await store.addBook(title: 'Persuasion', path: 'p.pdf');
    await store.setContentKey(later.id, 'key-p');
    expect((await store.flashcards(bookId: later.id)).length, 2);
  });
}
