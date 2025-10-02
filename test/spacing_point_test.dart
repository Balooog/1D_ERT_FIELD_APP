import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/enums.dart';
import 'package:ves_qc/models/spacing_point.dart';

void main() {
  test('feet to meters conversion', () {
    expect(feetToMeters(2.0), closeTo(0.6096, 1e-6));
  });

  test('Wenner rho derives from spacing and resistance', () {
    final point = SpacingPoint(
      id: 'rho-test',
      arrayType: ArrayType.wenner,
      aFeet: 12.0,
      resistanceOhm: 30.0,
      direction: SoundingDirection.we,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      timestamp: DateTime(2024),
    );
    final expected = 2 * math.pi * point.aMeters * point.resistanceOhm;
    expect(point.rhoAppOhmM, closeTo(expected, 1e-6));
  });

  test('Sigma propagation follows 2πa scaling', () {
    final point = SpacingPoint(
      id: 'sigma-test',
      arrayType: ArrayType.wenner,
      aFeet: 8.0,
      resistanceOhm: 15.0,
      resistanceStdOhm: 0.8,
      direction: SoundingDirection.other,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      timestamp: DateTime(2024),
    );
    final expectedSigma = 2 * math.pi * point.aMeters * 0.8;
    expect(point.sigmaRhoApp, closeTo(expectedSigma, 1e-6));
  });

  test('Resistance QA diff percent reflects V/I difference', () {
    final point = SpacingPoint(
      id: 'qa-test',
      arrayType: ArrayType.wenner,
      aFeet: 10.0,
      resistanceOhm: 10.0,
      direction: SoundingDirection.ns,
      voltageV: 21.1,
      currentA: 2.0,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      timestamp: DateTime(2024),
    );
    expect(point.rFromVi, closeTo(10.55, 1e-6));
    expect(point.resistanceDiffPercent, closeTo(5.5, 1e-6));
    expect(point.hasResistanceQaWarning, isTrue);
  });
}
