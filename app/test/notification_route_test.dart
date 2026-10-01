import 'package:arth/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a notification opens its screen over the tab it belongs to', () {
    expect(tabUnder('/deck/review?mode=practice&book=3&title=Emma'), '/cards', reason: 'a review reminder');
    expect(tabUnder('/community/deck/abc'), '/community', reason: 'a comment or reply');
    expect(tabUnder('/plans'), '/settings', reason: 'a plan change');
    expect(tabUnder('/read/4?page=12'), '/');
    expect(tabUnder('/cards'), isNull, reason: 'tabs open as themselves');
    expect(tabUnder('/community'), isNull);
    expect(tabUnder('/'), isNull);
  });
}
