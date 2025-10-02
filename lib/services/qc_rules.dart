import 'dart:math' as math;

import '../models/spacing_point.dart';

enum QaLevel { green, yellow, red }

class QaThresholds {
  const QaThresholds();

  static const double greenCv = 0.03;
  static const double yellowCv = 0.10;
  static const double greenResidual = 0.05;
  static const double yellowResidual = 0.15;
  static const double spLimitMv = 5;
  static const double contactLimit = 5000;
}

QaLevel classifyPoint({
  required double residual,
  required double? coefficientOfVariation,
  required SpacingPoint point,
}) {
  final absResidual = residual.abs();
  final cv = coefficientOfVariation ?? 0;
  final spDrift = point.spDriftMv?.abs() ?? 0;
  final maxContact = point.contactRMax ?? 0;

  bool isRed() =>
      cv > QaThresholds.yellowCv ||
      absResidual > QaThresholds.yellowResidual ||
      spDrift > QaThresholds.spLimitMv ||
      maxContact > QaThresholds.contactLimit;
  bool isYellow() =>
      (cv > QaThresholds.greenCv && cv <= QaThresholds.yellowCv) ||
      (absResidual > QaThresholds.greenResidual && absResidual <= QaThresholds.yellowResidual);

  if (isRed()) return QaLevel.red;
  if (isYellow()) return QaLevel.yellow;
  return QaLevel.green;
}

class QaSummary {
  const QaSummary({
    required this.green,
    required this.yellow,
    required this.red,
    required this.rms,
    required this.chiSq,
    required this.lastSpDrift,
    required this.worstContact,
  });

  final int green;
  final int yellow;
  final int red;
  final double rms;
  final double chiSq;
  final double? lastSpDrift;
  final double? worstContact;
}

QaSummary summarizeQa(
  List<SpacingPoint> points,
  List<double> residuals,
  List<double> fitted,
) {
  if (points.isEmpty || residuals.isEmpty) {
    return const QaSummary(
      green: 0,
      yellow: 0,
      red: 0,
      rms: 0.0,
      chiSq: 0.0,
      lastSpDrift: null,
      worstContact: null,
    );
  }

  double rss = 0.0;
  var obsCount = 0;
  final qaCounts = {QaLevel.green: 0, QaLevel.yellow: 0, QaLevel.red: 0};
  double? worstContact;

  for (var i = 0; i < points.length; i++) {
    final residual = residuals[i];
    final level = classifyPoint(
      residual: residual,
      coefficientOfVariation: points[i].sigmaRhoApp == null || points[i].rhoApp == 0
          ? null
          : (points[i].sigmaRhoApp! / points[i].rhoApp),
      point: points[i],
    );
    qaCounts[level] = (qaCounts[level] ?? 0) + 1;
    rss += math.pow(residual * 100, 2).toDouble();
    obsCount += 1;
    final contact = points[i].contactRMax;
    if (contact != null) {
      worstContact = math.max(worstContact ?? contact, contact).toDouble();
    }
  }

  final rms = obsCount == 0 ? 0.0 : math.sqrt(rss / obsCount);
  final chiSq = obsCount == 0
      ? 0.0
      : List.generate(points.length, (index) {
          final sigma = points[index].sigmaRhoApp ?? (0.05 * points[index].rhoApp.abs());
          final fit = fitted[index].abs();
          final resid = residuals[index] * fit;
          final weight = sigma == 0 ? 1 : 1 / sigma;
          return math.pow(resid * weight, 2).toDouble();
        }).fold<double>(0.0, (a, b) => a + b) /
          obsCount;
  return QaSummary(
    green: qaCounts[QaLevel.green]!,
    yellow: qaCounts[QaLevel.yellow]!,
    red: qaCounts[QaLevel.red]!,
    rms: rms,
    chiSq: chiSq,
    lastSpDrift: points.last.spDriftMv,
    worstContact: worstContact,
  );
}
