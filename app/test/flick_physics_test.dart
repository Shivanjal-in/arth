import 'package:arth/features/reader/flick_physics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slow drags and gentle flicks are left alone; hard flicks go further', () {
    expect(FlickBoostPhysics.boost(0), 0);
    expect(FlickBoostPhysics.boost(900), 900);
    expect(FlickBoostPhysics.boost(-1500), -1500);
    expect(FlickBoostPhysics.boost(3000), closeTo(3000 * 1.75, 0.01)); // halfway up the ramp
    expect(FlickBoostPhysics.boost(-9000), closeTo(-9000 * 2.5, 0.01)); // capped, direction kept
  });
}
