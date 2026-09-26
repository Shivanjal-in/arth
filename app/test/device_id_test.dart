import 'package:arth/app/providers.dart';
import 'package:arth/data/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the device id is a stable, salted hash of the platform id', () {
    final id = deviceIdFrom('9774d56d682e549c');
    expect(id, deviceIdFrom('9774d56d682e549c'), reason: 'same phone, same id, after a reinstall');
    expect(id, isNot(deviceIdFrom('9774d56d682e549d')));
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));
    expect(id.replaceAll('-', ''), isNot(contains('9774d56d682e549c')), reason: 'the raw id never leaves the phone');
  });

  test('usage says when the phone, not the account, is the limit', () {
    expect(Usage.fromJson({'used': 100, 'limit': 100, 'period': 'lifetime', 'phone': true}).phone, isTrue);
    expect(Usage.fromJson({'used': 3, 'limit': 100, 'period': 'lifetime'}).phone, isFalse);
  });
}
