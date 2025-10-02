import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/enums.dart';
import 'package:ves_qc/models/spacing_point.dart';
import 'package:ves_qc/services/inversion.dart';

void main() {
  test('Lite inversion returns model', () {
    final points = List.generate(5, (index) {
      final spacing = 1.0 + index;
      final rho = 100.0 + index * 5;
      final resistance = rho / (2 * math.pi * spacing);
      return SpacingPoint(
        id: '$index',
        arrayType: ArrayType.wenner,
        aFeet: metersToFeet(spacing),
        spacingMetric: spacing,
        resistanceOhm: resistance,
        direction: SoundingDirection.other,
        contactR: const {},
        spDriftMv: 0.0,
        stacks: 1,
        repeats: null,
        rhoApp: rho,
        sigmaRhoApp: 2.0,
        timestamp: DateTime.now(),
      );
    });
    final model = LiteInversionService(layerCount: 3).invert(points);
    expect(model.layers.length, greaterThan(0));
    expect(model.predictedRho.length, points.length);
  });
}
