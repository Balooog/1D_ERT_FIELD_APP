import 'dart:math' as math;

import '../models/spacing_point.dart';

enum QaLevel { green, yellow, red }

const double kQaGreenCvLimit = 0.03;
const double kQaYellowCvLimit = 0.10;
const double kQaGreenResidualLimit = 0.05;
const double kQaYellowResidualLimit = 0.15;
const double kQaSpLimitMv = 5;
const double kQaContactLimitOhm = 5000;

class QaThresholds {
  const QaThresholds();

  static const double greenCv = kQaGreenCvLimit;
  static const double yellowCv = kQaYellowCvLimit;
  static const double greenResidual = kQaGreenResidualLimit;
  static const double yellowResidual = kQaYellowResidualLimit;
  static const double spLimitMv = kQaSpLimitMv;
  static const double contactLimit = kQaContactLimitOhm;
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
      cv > kQaYellowCvLimit ||
      absResidual > kQaYellowResidualLimit ||
      spDrift > kQaSpLimitMv ||
      maxContact > kQaContactLimitOhm;
  bool isYellow() =>
      (cv > kQaGreenCvLimit && cv <= kQaYellowCvLimit) ||
      (absResidual > kQaGreenResidualLimit && absResidual <= kQaYellowResidualLimit);

  if (isRed()) return QaLevel.red;
  if (point.hasRhoQaWarning) return QaLevel.yellow;
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
  var chiAccum = 0.0;
  var chiCount = 0;
  final qaCounts = {QaLevel.green: 0, QaLevel.yellow: 0, QaLevel.red: 0};
  double? worstContact;

  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    final hasResidual = i < residuals.length;
    final residual = hasResidual ? residuals[i] : 0.0;
    final level = classifyPoint(
      residual: residual,
      coefficientOfVariation:
          point.sigmaRhoOhmM == null || point.rhoAppOhmM == 0 ? null : (point.sigmaRhoOhmM! / point.rhoAppOhmM),
      point: point,
    );
    qaCounts[level] = (qaCounts[level] ?? 0) + 1;

    if (hasResidual) {
      rss += math.pow(residual * 100, 2).toDouble();
      obsCount += 1;
    }

    if (hasResidual && fitted.isNotEmpty) {
      final fit = i < fitted.length ? fitted[i].abs() : fitted.last.abs();
      final sigma = point.sigmaRhoOhmM ?? (0.05 * point.rhoAppOhmM.abs());
      final resid = residual * fit;
      final weight = sigma == 0 ? 1 : 1 / sigma;
      chiAccum += math.pow(resid * weight, 2).toDouble();
      chiCount += 1;
    }

    final contact = point.contactRMax;
    if (contact != null) {
      worstContact = math.max(worstContact ?? contact, contact).toDouble();
    }
  }

  final rms = obsCount == 0 ? 0.0 : math.sqrt(rss / obsCount);
  final chiSq = chiCount == 0 ? 0.0 : chiAccum / chiCount;
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
