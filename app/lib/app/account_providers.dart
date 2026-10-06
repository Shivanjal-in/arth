// Accounts: who is signed in, their profile, and keeping this device's
// cards and bookmarks in sync with the server.

import 'dart:async';

import 'package:arth/app/providers.dart';
import 'package:arth/app/reminders.dart';
import 'package:arth/app/strings.dart';
import 'package:arth/data/account.dart';
import 'package:arth/data/analytics.dart';
import 'package:arth/data/api_client.dart';
import 'package:arth/data/auth_service.dart';
import 'package:arth/data/billing.dart';
import 'package:arth/data/push_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Firebase came up (it's configured and initialized). Set in main().
final firebaseReadyProvider = Provider<bool>((_) => false);

/// Null when accounts are off.
final authServiceProvider = Provider<AuthService?>(
  (ref) => ref.watch(firebaseReadyProvider) ? AuthService(FirebaseAuth.instance) : null,
);

/// The Firebase user; null when signed out or accounts are off.
final authUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth == null ? Stream.value(null) : auth.changes;
});

/// Who is signed in, by uid: what sync needs (tests override this).
final signedInUidProvider = Provider<String?>((ref) => ref.watch(authUserProvider).valueOrNull?.uid);

/// The signed-in user's profile from the API; null when signed out.
final accountProvider = AsyncNotifierProvider<AccountNotifier, Account?>(AccountNotifier.new);

class AccountNotifier extends AsyncNotifier<Account?> {
  @override
  Future<Account?> build() async {
    final user = await ref.watch(authUserProvider.future);
    if (user == null) return null;
    return ref.read(apiClientProvider).me();
  }

  Future<void> updateProfile({String? displayName, String? bio}) async {
    final updated = await ref.read(apiClientProvider).updateMe(displayName: displayName, bio: bio);
    state = AsyncData(updated);
  }

  /// Uploads [filePath] as the profile photo.
  Future<void> setPhoto(String filePath) async {
    final api = ref.read(apiClientProvider);
    final url = await api.uploadAvatar(filePath);
    state = AsyncData(await api.updateMe(photoUrl: url));
  }

  Future<void> setReviewReminders({required bool on}) async {
    state = AsyncData(await ref.read(apiClientProvider).setReviewReminders(on: on));
  }

  Future<void> removePhoto() async {
    state = AsyncData(await ref.read(apiClientProvider).updateMe(clearPhoto: true));
  }
}

/// Push notifications; null when accounts (Firebase) are off.
final pushServiceProvider = Provider<PushService?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  final service = PushService(
    api: () => ref.read(apiClientProvider),
    language: () => ref.read(settingsProvider).language == UiLanguage.hi ? 'hi' : 'en',
    local: ref.read(localNotificationsProvider),
  );
  // Register after sign-in is restored, never at launch: the API needs the
  // session. And again when the language changes.
  ref
    ..listen(signedInUidProvider, (prev, uid) {
      if (uid != null && uid != prev) unawaited(service.register());
    }, fireImmediately: true)
    ..listen(settingsProvider.select((s) => s.language), (_, _) {
      if (ref.read(signedInUidProvider) != null) unawaited(service.register());
    });
  return service;
});

/// Buying plans in the app stores. Follows sign-in so a purchase belongs to
/// the account.
final billingProvider = Provider<Billing>((ref) {
  final billing = Billing();
  ref.listen(signedInUidProvider, (prev, uid) {
    if (uid != prev) unawaited(billing.identify(uid));
  }, fireImmediately: true);
  return billing;
});

/// Usage analytics (see data/analytics.dart). Follows sign-in, the plan and
/// the interface language; initialized in main().
final analyticsProvider = Provider<Analytics>((ref) {
  final analytics = Analytics();
  ref
    ..listen(signedInUidProvider, (prev, uid) {
      if (uid != null && uid != prev) unawaited(analytics.signedIn(uid));
      if (uid == null && prev != null) unawaited(analytics.signedOut());
    }, fireImmediately: true)
    ..listen(accountProvider.select((a) => a.valueOrNull?.tier), (_, tier) {
      analytics.describe({'plan': (tier ?? Tier.free).name});
    }, fireImmediately: true)
    ..listen(settingsProvider.select((s) => s.language), (_, lang) {
      analytics.describe({'language': lang.name});
    }, fireImmediately: true)
    ..listen(settingsProvider.select((s) => s.usageStats), (_, on) => analytics.allow(on: on));
  return analytics;
});

/// AI uses against the allowance: from /me, then kept current by the
/// headers every AI response carries.
final usageProvider = NotifierProvider<UsageNotifier, Usage?>(UsageNotifier.new);

class UsageNotifier extends Notifier<Usage?> {
  @override
  Usage? build() => ref.watch(accountProvider).valueOrNull?.usage;

  // A method, not a setter: it's handed around as a callback.
  // ignore: use_setters_to_change_properties
  void report(Usage usage) => state = usage;
}

/// Whether the reader can ask for AI answers right now.
enum AiAccess {
  /// Accounts aren't set up (no Firebase): the server doesn't count either.
  open,
  allowed,
  signedOut,
  exhausted,
}

final aiAccessProvider = Provider<AiAccess>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return AiAccess.open;
  if (ref.watch(signedInUidProvider) == null) return AiAccess.signedOut;
  if (ref.watch(usageProvider)?.exhausted ?? false) return AiAccess.exhausted;
  return AiAccess.allowed;
});

enum SyncPhase { idle, syncing, failed }

class SyncState {
  const SyncState({this.phase = SyncPhase.idle, this.lastSyncedAt, this.error});

  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? error;
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

/// Pushes this device's changed cards and bookmarks and pulls everyone
/// else's, page by page. Runs on sign-in, when the app comes back to the
/// foreground, a few seconds after a local change, and on demand.
class SyncNotifier extends Notifier<SyncState> {
  Timer? _debounce;
  Future<void>? _running;
  bool _again = false;

  /// Rows per request; the store's default page size.
  static const _batch = 500;

  @override
  SyncState build() {
    ref.listen(signedInUidProvider, (prev, uid) {
      if (uid != null && uid != prev) unawaited(run());
    });
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(run()));
    ref.onDispose(() {
      lifecycle.dispose();
      _debounce?.cancel();
    });
    return const SyncState();
  }

  /// Syncs soon: local writes call this, and a burst of edits syncs once.
  void schedule() {
    if (ref.read(signedInUidProvider) == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => unawaited(run()));
  }

  /// Syncs now. A call while a sync is running queues one more round.
  Future<void> run() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _once();
    } while (_again);
  }

  Future<void> _once() async {
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    final store = ref.read(localStoreProvider);
    final api = ref.read(apiClientProvider);
    state = SyncState(phase: SyncPhase.syncing, lastSyncedAt: state.lastSyncedAt);
    try {
      // First sync of this account on this device: what's here joins it.
      final seenKey = 'sync_seen:$uid';
      if (await store.get(seenKey) == null) {
        await store.markAllDirty();
        await store.set(seenKey, '1');
      }
      final cursorKey = 'sync_cursor:$uid';
      var cursor = int.tryParse(await store.get(cursorKey) ?? '') ?? 0;
      var changed = false;
      while (true) {
        final cards = await store.pendingCards();
        final bookmarks = await store.pendingBookmarks();
        final page = await api.sync(cursor: cursor, cards: cards, bookmarks: bookmarks);
        await store.markSynced(cards: cards, bookmarks: bookmarks);
        await store.applyRemote(cards: page.cards, bookmarks: page.bookmarks);
        changed = changed || page.cards.isNotEmpty || page.bookmarks.isNotEmpty;
        cursor = page.cursor;
        await store.set(cursorKey, '$cursor');
        if (!page.more && cards.length < _batch && bookmarks.length < _batch) break;
      }
      if (changed) {
        ref
          ..invalidate(flashcardsProvider)
          ..invalidate(decksProvider)
          ..invalidate(bookmarksProvider);
      }
      state = SyncState(lastSyncedAt: DateTime.now());
    } on ApiFailure catch (e) {
      state = SyncState(phase: SyncPhase.failed, lastSyncedAt: state.lastSyncedAt, error: e.code);
    }
  }
}
