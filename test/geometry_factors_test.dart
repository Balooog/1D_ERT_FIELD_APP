import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/services/geometry_factors.dart';

void main() {
  test('Wenner geometry factor', () {
    final k = geometryFactor(array: GeometryArray.wenner, spacing: 10);
    expect(k, closeTo(2 * 3.14159 * 10, 1e-3));
  });

  test('Schlumberger geometry factor', () {
    final k =
        geometryFactor(array: GeometryArray.schlumberger, spacing: 20, mn: 6);
    expect(k, greaterThan(0));
  });

  test('rhoApp calculation', () {
    final result = rhoAppFromReadings(
      array: GeometryArray.wenner,
      spacing: 5,
      voltage: 0.5,
      current: 0.1,
    );
    expect(result['rho'], isNotNull);
  });
}
