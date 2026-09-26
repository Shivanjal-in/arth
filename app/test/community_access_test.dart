import 'package:arth/app/account_providers.dart';
import 'package:arth/data/account.dart';
import 'package:arth/features/community/community_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedAccount extends AccountNotifier {
  _FixedAccount(this.account);
  final Account? account;

  @override
  Future<Account?> build() async => account;
}

Account _account(Tier tier, {bool admin = false}) => Account(uid: 'u', displayName: 'U', bio: '', isAdmin: admin, tier: tier);

void main() {
  Future<CommunityAccess> accessFor({String? uid, Account? account}) async {
    final container = ProviderContainer(
      overrides: [
        signedInUidProvider.overrideWithValue(uid),
        accountProvider.overrideWith(() => _FixedAccount(account)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    return container.read(communityAccessProvider);
  }

  test('the community opens for Pro, Super and admins only', () async {
    expect(await accessFor(), CommunityAccess.locked, reason: 'signed out');
    expect(await accessFor(uid: 'u', account: _account(Tier.free)), CommunityAccess.locked);
    expect(await accessFor(uid: 'u', account: _account(Tier.pro)), CommunityAccess.open);
    expect(await accessFor(uid: 'u', account: _account(Tier.superTier)), CommunityAccess.open);
    expect(await accessFor(uid: 'u', account: _account(Tier.free, admin: true)), CommunityAccess.open);
  });
}
