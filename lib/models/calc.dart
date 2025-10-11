import 'dart:math' as math;

import '../utils/units.dart';

class QcConfig {
  const QcConfig({
    this.outlierCapOhm = 100000,
    this.sdThresholdPercent = 15,
    this.anisotropyRatioThreshold = 3,
    this.jumpThresholdLog10 = 0.35,
  });

  final double outlierCapOhm;
  final double sdThresholdPercent;
  final double anisotropyRatioThreshold;
  final double jumpThresholdLog10;
}

double rhoAWenner(double spacingFeet, double resistanceOhm) {
  final spacingMeters = feetToMeters(spacingFeet);
  return 2 * math.pi * spacingMeters * resistanceOhm;
}

double? averageApparentResistivity(
  double spacingFeet,
  Iterable<double?> resistances,
) {
  final valid = resistances.whereType<double>().toList();
  if (valid.isEmpty) {
    return null;
  }
  final rhoValues =
      valid.map((resistance) => rhoAWenner(spacingFeet, resistance)).toList();
  final sum = rhoValues.reduce((a, b) => a + b);
  return sum / rhoValues.length;
}

double? anisotropyRatio(double? rhoA, double? rhoB) {
  if (rhoA == null || rhoB == null) {
    return null;
  }
  final maxVal = math.max(rhoA.abs(), rhoB.abs());
  final minVal = math.min(rhoA.abs(), rhoB.abs());
  if (minVal == 0) {
    return null;
  }
  return maxVal / minVal;
}

class QcFlags {
  const QcFlags({
    this.outlier = false,
    this.highVariance = false,
    this.anisotropy = false,
    this.jump = false,
  });

  final bool outlier;
  final bool highVariance;
  final bool anisotropy;
  final bool jump;

  bool get hasAny => outlier || highVariance || anisotropy || jump;
}

QcFlags evaluateQc({
  required double spacingFeet,
  required double? resistanceA,
  required double? resistanceB,
  required double? sdA,
  required double? sdB,
  required QcConfig config,
  double? previousRho,
}) {
  final rhoA =
      resistanceA == null ? null : rhoAWenner(spacingFeet, resistanceA);
  final rhoB =
      resistanceB == null ? null : rhoAWenner(spacingFeet, resistanceB);
  final ratio = anisotropyRatio(rhoA, rhoB);
  final latestRho = _averageNullable([rhoA, rhoB]);

  final outlier = (resistanceA != null && resistanceA.abs() > config.outlierCapOhm) ||
      (resistanceB != null && resistanceB.abs() > config.outlierCapOhm);
  final highVariance = ((sdA ?? 0) >= config.sdThresholdPercent) ||
      ((sdB ?? 0) >= config.sdThresholdPercent);
  final anisotropy = ratio != null && ratio > config.anisotropyRatioThreshold;

  bool jump = false;
  if (previousRho != null && latestRho != null && previousRho > 0 && latestRho > 0) {
    final jumpMagnitude = (math.log(previousRho) / math.ln10) -
        (math.log(latestRho) / math.ln10);
    jump = jumpMagnitude.abs() > config.jumpThresholdLog10;
  }

  return QcFlags(
    outlier: outlier,
    highVariance: highVariance,
    anisotropy: anisotropy,
    jump: jump,
  );
}

List<double> computeDepthCueFeet(List<double> spacingsFeet) {
  return spacingsFeet.map((spacing) => spacing * 0.5).toList();
}

List<double> computeDepthCueMeters(List<double> spacingsFeet) {
  return computeDepthCueFeet(spacingsFeet).map(feetToMeters).toList();
}

double? _averageNullable(List<double?> values) {
  final filtered = values.whereType<double>().toList();
  if (filtered.isEmpty) {
    return null;
  }
  final sum = filtered.reduce((a, b) => a + b);
  return sum / filtered.length;
}
