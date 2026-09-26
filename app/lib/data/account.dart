// The signed-in user as the API describes them (GET /v1/me), and one page
// of a sync round. Mirrors api/src/services/accounts.ts.

enum Tier { free, pro, superTier }

/// AI uses against the tier's allowance (api/src/services/quota.ts).
class Usage {
  const Usage({required this.used, required this.limit, required this.monthly, this.resetsAt});

  factory Usage.fromJson(Map<String, dynamic> j) => Usage(
        used: (j['used'] as int?) ?? 0,
        limit: j['limit'] as int?,
        monthly: j['period'] == 'month',
        resetsAt: j['resetsAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['resetsAt'] as int),
      );

  /// From the `x-ai-*` headers an AI response carries; null if absent.
  static Usage? fromHeaders(String? used, String? limit, String? period) {
    final u = int.tryParse(used ?? '');
    if (u == null) return null;
    return Usage(used: u, limit: int.tryParse(limit ?? ''), monthly: period == 'month');
  }

  final int used;

  /// Null: unlimited.
  final int? limit;

  /// Resets each month (pro), rather than a lifetime allowance (free).
  final bool monthly;
  final DateTime? resetsAt;

  int? get left => limit == null ? null : (limit! - used).clamp(0, limit!);
  bool get exhausted => limit != null && used >= limit!;
}

class Account {
  const Account({
    required this.uid,
    required this.displayName,
    required this.bio,
    required this.isAdmin,
    required this.tier,
    this.reviewReminders = true,
    this.usage,
    this.email,
    this.phone,
    this.photoUrl,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        uid: j['uid'] as String,
        displayName: (j['displayName'] as String?) ?? '',
        bio: (j['bio'] as String?) ?? '',
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        photoUrl: j['photoUrl'] as String?,
        isAdmin: j['role'] == 'admin',
        tier: switch (j['tier']) {
          'pro' => Tier.pro,
          'super' => Tier.superTier,
          _ => Tier.free,
        },
        usage: j['usage'] == null ? null : Usage.fromJson(j['usage'] as Map<String, dynamic>),
        reviewReminders: (j['reviewReminders'] as bool?) ?? true,
      );

  final String uid;
  final String displayName;
  final String bio;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final bool isAdmin;
  final Tier tier;
  final Usage? usage;

  /// A daily nudge when cards are due.
  final bool reviewReminders;

  /// What to call them: their name, else how they signed in.
  String get label => displayName.isNotEmpty ? displayName : (email ?? phone ?? '');
}

class SyncPage {
  const SyncPage({required this.cursor, required this.more, required this.cards, required this.bookmarks});

  factory SyncPage.fromJson(Map<String, dynamic> j) => SyncPage(
        cursor: j['cursor'] as int,
        more: j['more'] as bool? ?? false,
        cards: [for (final c in j['cards'] as List<dynamic>) c as Map<String, Object?>],
        bookmarks: [for (final b in j['bookmarks'] as List<dynamic>) b as Map<String, Object?>],
      );

  final int cursor;
  final bool more;
  final List<Map<String, Object?>> cards;
  final List<Map<String, Object?>> bookmarks;
}
