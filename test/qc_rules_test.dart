import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/enums.dart';
import 'package:ves_qc/models/spacing_point.dart';
import 'package:ves_qc/services/qc_rules.dart';

SpacingPoint _makePoint(double rho, {double? sigma}) {
  return SpacingPoint(
    id: '1',
    arrayType: ArrayType.wenner,
    spacingMetric: 5.0,
    vp: 1.0,
    current: 0.5,
    contactR: const {'c1': 100.0, 'c2': 150.0},
    spDriftMv: 1.0,
    stacks: 1,
    repeats: null,
    rhoApp: rho,
    sigmaRhoApp: sigma,
    timestamp: DateTime.now(),
  );
}

void main() {
  test('Green classification', () {
    final point = _makePoint(100.0, sigma: 2.0);
    final level = classifyPoint(residual: 0.02, coefficientOfVariation: 0.02, point: point);
    expect(level, QaLevel.green);
  });

  test('Red classification due to CV', () {
    final point = _makePoint(100.0, sigma: 20.0);
    final level = classifyPoint(residual: 0.02, coefficientOfVariation: 0.2, point: point);
    expect(level, QaLevel.red);
  });

  test('Summary counts', () {
    final points = [
      _makePoint(100.0, sigma: 2.0),
      _makePoint(90.0, sigma: 5.0),
      _makePoint(150.0, sigma: 30.0),
    ];
    final residuals = [0.02, 0.07, 0.2];
    final fitted = [100.0, 95.0, 140.0];
    final summary = summarizeQa(points, residuals, fitted);
    expect(summary.green, greaterThanOrEqualTo(1));
    expect(summary.red, greaterThanOrEqualTo(1));
  });
}
