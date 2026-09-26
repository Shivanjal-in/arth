// The community as the API describes it (api/src/routes/community.ts,
// admin.ts): published recaps of books, their comments, and admin views.

import 'package:arth/app/settings.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/local_store.dart';

Tier _tier(Object? t) => switch (t) {
      'pro' => Tier.pro,
      'super' => Tier.superTier,
      _ => Tier.free,
    };

DateTime _ms(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as int?) ?? 0);

class Author {
  const Author({required this.uid, required this.name, required this.tier, this.photoUrl});

  factory Author.fromJson(Map<String, dynamic> j) =>
      Author(uid: j['uid'] as String, name: (j['name'] as String?) ?? '', photoUrl: j['photoUrl'] as String?, tier: _tier(j['tier']));

  final String uid;
  final String name;
  final String? photoUrl;
  final Tier tier;
}

class DeckCard {
  const DeckCard({required this.kind, required this.front, this.back = '', this.note = '', this.location});

  factory DeckCard.fromJson(Map<String, dynamic> j) => DeckCard(
        kind: CardKind.values.byName(j['kind'] as String),
        front: j['front'] as String,
        back: (j['back'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
        location: j['location'] as String?,
      );

  factory DeckCard.of(Flashcard c) => DeckCard(kind: c.kind, front: c.front, back: c.back, note: c.note, location: c.location);

  final CardKind kind;
  final String front;
  final String back;
  final String note;
  final String? location;

  Map<String, Object?> toJson() => {'kind': kind.name, 'front': front, 'back': back, 'note': note, 'location': location};

  /// As a local card, for showing with the same tiles as your own.
  Flashcard asFlashcard(int i) => Flashcard(
        id: 'published-$i',
        kind: kind,
        front: front,
        back: back,
        note: note,
        location: location,
        createdAt: DateTime(2000),
        updatedAt: DateTime(2000),
      );
}

/// A deck in a list: enough to choose it.
class PublishedDeckSummary {
  const PublishedDeckSummary({
    required this.id,
    required this.title,
    required this.bookTitle,
    required this.blurb,
    required this.cardCount,
    required this.preview,
    required this.likes,
    required this.saves,
    required this.comments,
    required this.createdAt,
    required this.author,
    required this.liked,
    this.font = CardFont.montserrat,
  });

  factory PublishedDeckSummary.fromJson(Map<String, dynamic> j) => PublishedDeckSummary(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        bookTitle: j['bookTitle'] as String,
        blurb: (j['blurb'] as String?) ?? '',
        cardCount: (j['cardCount'] as int?) ?? 0,
        preview: [for (final p in (j['preview'] as List<dynamic>? ?? const [])) (kind: CardKind.values.byName((p as Map<String, dynamic>)['kind'] as String), front: p['front'] as String)],
        likes: (j['likes'] as int?) ?? 0,
        saves: (j['saves'] as int?) ?? 0,
        comments: (j['comments'] as int?) ?? 0,
        createdAt: _ms(j['createdAt']),
        author: Author.fromJson(j['author'] as Map<String, dynamic>),
        liked: (j['liked'] as bool?) ?? false,
        font: CardFont.values.asNameMap()[j['font']] ?? CardFont.montserrat,
      );

  final String id;
  final String title;
  final String bookTitle;
  final String blurb;
  final int cardCount;
  final List<({CardKind kind, String front})> preview;
  final int likes;
  final int saves;
  final int comments;
  final DateTime createdAt;
  final Author author;
  final bool liked;

  /// The font its author chose for the cards.
  final CardFont font;
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
    required this.mine,
    required this.hidden,
    this.parentId,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> j) => CommunityComment(
        id: j['id'] as String,
        parentId: j['parentId'] as String?,
        text: j['text'] as String,
        createdAt: _ms(j['createdAt']),
        author: Author.fromJson(j['author'] as Map<String, dynamic>),
        mine: (j['mine'] as bool?) ?? false,
        hidden: (j['hidden'] as bool?) ?? false,
      );

  final String id;
  final String? parentId;
  final String text;
  final DateTime createdAt;
  final Author author;
  final bool mine;

  /// Held for review after reports; only its author (and admins) see it.
  final bool hidden;
}

/// A deck's page: everything, including cards and comments.
class PublishedDeck {
  const PublishedDeck({required this.summary, required this.cards, required this.comments, required this.mine, required this.hidden, this.removed = false, this.bookKey});

  factory PublishedDeck.fromJson(Map<String, dynamic> j) => PublishedDeck(
        summary: PublishedDeckSummary.fromJson(j),
        bookKey: j['bookKey'] as String?,
        cards: [for (final c in j['cards'] as List<dynamic>) DeckCard.fromJson(c as Map<String, dynamic>)],
        comments: [for (final c in j['thread'] as List<dynamic>) CommunityComment.fromJson(c as Map<String, dynamic>)],
        mine: (j['mine'] as bool?) ?? false,
        hidden: (j['hidden'] as bool?) ?? false,
        removed: (j['removed'] as bool?) ?? false,
      );

  final PublishedDeckSummary summary;
  final String? bookKey;
  final List<DeckCard> cards;
  final List<CommunityComment> comments;
  final bool mine;
  final bool hidden;

  /// Taken down; only an admin is still shown it.
  final bool removed;
}

class DeckPage {
  const DeckPage({required this.decks, required this.more, required this.canPublish});

  final List<PublishedDeckSummary> decks;
  final bool more;
  final bool canPublish;
}

// ---- admin ----

class AdminReportItem {
  const AdminReportItem({
    required this.kind,
    required this.targetId,
    required this.count,
    required this.reasons,
    required this.status,
    required this.preview,
    this.deckId,
    this.ownerUid,
    this.ownerName,
    this.ownerBanned = false,
  });

  factory AdminReportItem.fromJson(Map<String, dynamic> j) {
    final owner = j['owner'] as Map<String, dynamic>?;
    final p = j['preview'] as Map<String, dynamic>;
    final title = (p['title'] as String?) ?? '';
    return AdminReportItem(
      kind: j['kind'] as String,
      targetId: j['targetId'] as String,
      count: j['count'] as int,
      reasons: [for (final r in j['reasons'] as List<dynamic>) r as String],
      status: j['status'] as String,
      preview: (p['text'] as String?) ?? [p['bookTitle'] as String? ?? '', if (title.isNotEmpty) title].join(' — '),
      deckId: p['deckId'] as String?,
      ownerUid: owner?['uid'] as String?,
      ownerName: owner?['name'] as String?,
      ownerBanned: (owner?['banned'] as bool?) ?? false,
    );
  }

  /// 'deck' or 'comment'.
  final String kind;
  final String targetId;
  final int count;
  final List<String> reasons;

  /// 'live' or 'hidden' (three reports hide it).
  final String status;
  final String preview;
  final String? deckId;
  final String? ownerUid;
  final String? ownerName;
  final bool ownerBanned;
}

class AdminUser {
  const AdminUser({required this.uid, required this.displayName, required this.tier, required this.isAdmin, required this.banned, this.email, this.phone, this.photoUrl, this.usage});

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        uid: j['uid'] as String,
        displayName: (j['displayName'] as String?) ?? '',
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        photoUrl: j['photoUrl'] as String?,
        tier: _tier(j['tier']),
        isAdmin: j['role'] == 'admin',
        banned: (j['banned'] as bool?) ?? false,
        usage: j['usage'] == null ? null : Usage.fromJson(j['usage'] as Map<String, dynamic>),
      );

  final String uid;
  final String displayName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final Tier tier;
  final bool isAdmin;
  final bool banned;
  final Usage? usage;

  String get label => displayName.isNotEmpty ? displayName : (email ?? phone ?? uid);
}
