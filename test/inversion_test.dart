import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/services/inversion.dart';
import 'package:resicheck/utils/units.dart';

void main() {
  test('invert1DWenner recovers synthetic three-layer model', () async {
    final spacingsMeters = <double>[2, 4, 8, 12, 16, 24];
    final spacingsFeet = spacingsMeters.map(metersToFeet).toList();
    final resistivities = <double>[30, 120, 400];
    final thicknesses = <double?>[2.5, 6.0, null];
    final synthetic = _forwardSynthetic(spacingsMeters, resistivities, thicknesses);

    final result = await invert1DWenner(
      aFt: spacingsFeet,
      rhoAppNS: synthetic,
      rhoAppWE: synthetic,
      maxLayers: 3,
    );

    expect(result.misfit.isFinite, isTrue);
    expect(result.resistivities.length, equals(3));
    expect(result.depthsM.length, equals(3));
    expect(result.fitCurve.length, equals(synthetic.length));
    expect(result.misfit, lessThan(0.2));

    final recoveredThicknesses = _boundariesToThickness(result.depthsM);
    expect(recoveredThicknesses.length, equals(3));

    for (var i = 0; i < 2; i++) {
      final expectedThick = thicknesses[i]!;
      final actualThick = recoveredThicknesses[i]!;
      final thicknessError = (actualThick - expectedThick).abs() / expectedThick;
      expect(thicknessError, lessThan(0.25), reason: 'thickness layer ${i + 1}');
    }

    for (var i = 0; i < resistivities.length; i++) {
      final expectedRho = resistivities[i];
      final actualRho = result.resistivities[i];
      final rhoError = (actualRho - expectedRho).abs() / expectedRho;
      expect(rhoError, lessThan(0.30), reason: 'resistivity layer ${i + 1}');
    }
  });
}

List<double> _forwardSynthetic(
  List<double> spacingsMeters,
  List<double> resistivities,
  List<double?> thicknesses,
) {
  final outputs = <double>[];
  for (final spacing in spacingsMeters) {
    final depth = spacing / 2;
    double numerator = 0;
    double weightSum = 0;
    double cumulativeDepth = 0;
    for (var i = 0; i < resistivities.length; i++) {
      final thickness = thicknesses[i] ?? (depth * 2);
      final top = cumulativeDepth;
      final bottom = cumulativeDepth + thickness;
      final weight = math.exp(
        -(depth - (top + bottom) / 2).abs() / math.max((bottom - top) / 2, 1e-3),
      );
      numerator += resistivities[i] * weight;
      weightSum += weight;
      cumulativeDepth += thickness;
    }
    outputs.add(weightSum == 0 ? resistivities.last : numerator / weightSum);
  }
  return outputs;
}

List<double?> _boundariesToThickness(List<double> boundaries) {
  if (boundaries.isEmpty) {
    return const [null];
  }
  final thicknesses = <double?>[];
  for (var i = 0; i < boundaries.length; i++) {
    if (i == boundaries.length - 1) {
      thicknesses.add(null);
    } else {
      final top = i == 0 ? 0.0 : boundaries[i - 1];
      final bottom = boundaries[i];
      thicknesses.add(bottom - top);
    }
  }
  return thicknesses;
}
