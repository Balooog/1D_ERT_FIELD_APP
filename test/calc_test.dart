import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/calc.dart';

void main() {
  test('feet to meters conversion', () {
    expect(feetToMeters(10), closeTo(3.048, 1e-6));
    expect(metersToFeet(3.048), closeTo(10, 1e-6));
  });

  test('rho a wenner calculation matches expected value', () {
    final rho = rhoAWenner(20, 50);
    expect(rho, closeTo(1915, 20));
  });

  test('QC flags detect high variability', () {
    final flags = evaluateQc(
      spacingFeet: 10,
      resistanceA: 100,
      resistanceB: 105,
      sdA: 20,
      sdB: 5,
      config: const QcConfig(sdThresholdPercent: 10),
      previousRho: null,
    );
    expect(flags.highVariance, isTrue);
    expect(flags.outlier, isFalse);
  });

  test('depth cue computed as half spacing', () {
    final feet = computeDepthCueFeet([10, 20, 40]);
    expect(feet, [5, 10, 20]);
    final meters = computeDepthCueMeters([10]);
    expect(meters.first, closeTo(1.524, 1e-6));
  });
}
