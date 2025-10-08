import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/project_models.dart' show ArrayType;
import 'package:resicheck/models/spacing_point.dart';

void main() {
  test('feet to meters conversion', () {
    expect(feetToMeters(2.0), closeTo(0.6096, 1e-6));
  });

  test('Derived resistance matches Wenner geometry from rho input', () {
    const rho = 150.0;
    const aFeet = 12.0;
    final point = SpacingPoint(
      id: 'rho-test',
      arrayType: ArrayType.wenner,
      aFeet: aFeet,
      rhoAppOhmM: rho,
      direction: SoundingDirection.we,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      timestamp: DateTime(2024),
    );
    final expectedResistance = rho / (2 * math.pi * point.aMeters);
    expect(point.resistanceOhm, closeTo(expectedResistance, 1e-6));
  });

  test('Sigma rho propagates from resistance sigma', () {
    const resistanceStd = 0.8;
    final point = SpacingPoint(
      id: 'sigma-test',
      arrayType: ArrayType.wenner,
      aFeet: 8.0,
      rhoAppOhmM: 2 * math.pi * feetToMeters(8.0) * 15.0,
      resistanceStdOhm: resistanceStd,
      direction: SoundingDirection.other,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      timestamp: DateTime(2024),
    );
    final expectedSigma = 2 * math.pi * point.aMeters * resistanceStd;
    expect(point.sigmaRhoOhmM, closeTo(expectedSigma, 1e-6));
  });

  test('Rho QA diff percent reflects V/I derived resistivity', () {
    const aFeet = 10.0;
    const rho = 200.0;
    const voltage = 40.0;
    const current = 2.0;
    final point = SpacingPoint(
      id: 'qa-test',
      arrayType: ArrayType.wenner,
      aFeet: aFeet,
      rhoAppOhmM: rho,
      direction: SoundingDirection.ns,
      voltageV: voltage,
      currentA: current,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      timestamp: DateTime(2024),
    );
    final expectedRhoFromVi = 2 * math.pi * point.aMeters * (voltage / current);
    final expectedDiff = ((expectedRhoFromVi - rho).abs() / rho) * 100;
    expect(point.rhoFromVi, closeTo(expectedRhoFromVi, 1e-6));
    expect(point.rhoDiffPercent, closeTo(expectedDiff, 1e-6));
    expect(expectedDiff, greaterThan(SpacingPoint.rhoQaThresholdPercent));
    expect(point.hasRhoQaWarning, isTrue);
  });
}
