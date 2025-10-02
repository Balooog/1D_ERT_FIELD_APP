import 'dart:math' as math;

import '../models/inversion_model.dart';
import '../models/spacing_point.dart';

class LiteInversionService {
  LiteInversionService({this.maxIterations = 10, this.layerCount = 3});

  final int maxIterations;
  final int layerCount;

  InversionModel invert(List<SpacingPoint> points) {
    final usable = points.where((p) => !p.excluded).toList();
    if (usable.length < 2) {
      return InversionModel.empty;
    }
    final spacings = usable.map((e) => e.spacingMetric).toList();
    final observations = usable.map((e) => e.rhoAppOhmM).toList();
    final seeds = _seedModel(spacings, observations);
    var logRhos = seeds.rhos.map(math.log).toList();
    final thicknesses = seeds.thicknesses;

    double lambda = 0.3;
    double lastRms = double.infinity;
    List<double> predicted = List.filled(spacings.length, 0);

    for (var iter = 0; iter < maxIterations; iter++) {
      predicted = _forward(spacings, thicknesses, logRhos);
      final residuals = List<double>.generate(
        predicted.length,
        (i) => observations[i] - predicted[i],
      );

      final rms = _rms(residuals);
      if ((lastRms - rms).abs() < 0.5) {
        break;
      }
      lastRms = rms;

      final jacobian = _jacobian(spacings, thicknesses, logRhos, predicted);
      final update = _levenbergMarquardtStep(jacobian, residuals, lambda);

      for (var i = 0; i < logRhos.length; i++) {
        logRhos[i] += update[i];
      }
      lambda = math.max(0.05, lambda * 0.7);
    }

    predicted = _forward(spacings, thicknesses, logRhos);
    final residuals = List<double>.generate(predicted.length, (i) => observations[i] - predicted[i]);
    final rms = _rms(residuals);
    final chiSq = _chiSquare(residuals, usable);
    final oneSigma = _oneSigmaBand(predicted, residuals);
    final layers = <Layer>[];
    for (var i = 0; i < logRhos.length; i++) {
      layers.add(Layer(
        thicknessM: i < thicknesses.length ? thicknesses[i] : null,
        rhoOhmM: math.exp(logRhos[i]),
      ));
    }

    return InversionModel(
      layers: layers,
      rmsPct: rms,
      chiSq: chiSq,
      predictedRho: predicted,
      oneSigmaBand: oneSigma,
    );
  }

  _SeedResult _seedModel(List<double> spacings, List<double> obs) {
    final median = _median(obs);
    final rhos = List<double>.filled(layerCount, median);
    final thicknesses = <double?>[];
    if (layerCount == 1) {
      thicknesses.add(null);
    } else {
      final increments = _logSlopeBreaks(spacings, obs, layerCount - 1);
      for (var i = 0; i < layerCount - 1; i++) {
        thicknesses.add(increments[i]);
      }
      thicknesses.add(null);
    }
    return _SeedResult(rhos: rhos, thicknesses: thicknesses);
  }

  List<double> _forward(List<double> spacings, List<double?> thicknesses, List<double> logRhos) {
    final rhos = logRhos.map(math.exp).toList();
    final outputs = <double>[];
    for (var spacing in spacings) {
      final depth = spacing / 2;
      double numerator = 0;
      double weightSum = 0;
      double cumulativeDepth = 0;
      for (var i = 0; i < rhos.length; i++) {
        final layerThickness = thicknesses[i];
        final thickness = layerThickness ?? (depth * 2);
        final layerTop = cumulativeDepth;
        final layerBottom = cumulativeDepth + thickness;
        final distanceWeight = _depthWeight(depth, layerTop, layerBottom);
        numerator += rhos[i] * distanceWeight;
        weightSum += distanceWeight;
        cumulativeDepth += thickness;
      }
      outputs.add(weightSum == 0 ? rhos.last : numerator / weightSum);
    }
    return outputs;
  }

  List<List<double>> _jacobian(
    List<double> spacings,
    List<double?> thicknesses,
    List<double> logRhos,
    List<double> predicted,
  ) {
    final eps = 1e-3;
    final base = _forward(spacings, thicknesses, logRhos);
    final jacobian = List.generate(spacings.length, (_) => List<double>.filled(logRhos.length, 0));

    for (var j = 0; j < logRhos.length; j++) {
      final perturbed = List<double>.from(logRhos);
      perturbed[j] += eps;
      final forwardPerturbed = _forward(spacings, thicknesses, perturbed);
      for (var i = 0; i < spacings.length; i++) {
        jacobian[i][j] = (forwardPerturbed[i] - base[i]) / eps;
      }
    }
    return jacobian;
  }

  List<double> _levenbergMarquardtStep(
    List<List<double>> jacobian,
    List<double> residuals,
    double lambda,
  ) {
    final rows = jacobian.length;
    final cols = jacobian.first.length;
    final jt = List.generate(cols, (i) => List<double>.generate(rows, (j) => jacobian[j][i]));
    final jtj = List.generate(cols, (_) => List<double>.filled(cols, 0.0));

    for (var i = 0; i < cols; i++) {
      for (var j = 0; j < cols; j++) {
        double sum = 0;
        for (var k = 0; k < rows; k++) {
          sum += jt[i][k] * jacobian[k][j];
        }
        jtj[i][j] = sum;
      }
    }

    for (var i = 0; i < cols; i++) {
      jtj[i][i] += lambda;
    }

    final jtr = List<double>.filled(cols, 0);
    for (var i = 0; i < cols; i++) {
      double sum = 0;
      for (var k = 0; k < rows; k++) {
        sum += jt[i][k] * residuals[k];
      }
      jtr[i] = sum;
    }

    return _solveLinearSystem(jtj, jtr);
  }

  List<double> _solveLinearSystem(List<List<double>> matrix, List<double> rhs) {
    final n = rhs.length;
    final a = List.generate(n, (i) => List<double>.from(matrix[i]));
    final b = List<double>.from(rhs);

    for (var i = 0; i < n; i++) {
      var pivot = a[i][i];
      if (pivot.abs() < 1e-12) {
        pivot = 1e-12;
      }
      for (var j = i; j < n; j++) {
        a[i][j] /= pivot;
      }
      b[i] /= pivot;

      for (var k = 0; k < n; k++) {
        if (k == i) continue;
        final factor = a[k][i];
        for (var j = i; j < n; j++) {
          a[k][j] -= factor * a[i][j];
        }
        b[k] -= factor * b[i];
      }
    }
    return b;
  }

  double _depthWeight(double depth, double top, double bottom) {
    final center = (top + bottom) / 2;
    final radius = (bottom - top) / 2;
    final distance = (depth - center).abs();
    final weight = math.exp(-distance / math.max(radius, 1e-3));
    return weight;
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    }
  }

  double _rms(List<double> residuals) {
    if (residuals.isEmpty) return 0;
    final sumSq = residuals.fold<double>(0, (sum, r) => sum + r * r);
    return math.sqrt(sumSq / residuals.length);
  }

  double _chiSquare(List<double> residuals, List<SpacingPoint> points) {
    if (residuals.isEmpty) return 0;
    double chi = 0;
    for (var i = 0; i < residuals.length; i++) {
      final sigma = points[i].sigmaRhoOhmM ?? (0.05 * points[i].rhoAppOhmM.abs());
      final weight = sigma == 0 ? 1 : 1 / sigma;
      chi += math.pow(residuals[i] * weight, 2).toDouble();
    }
    return chi / residuals.length;
  }

  List<double> _oneSigmaBand(List<double> predicted, List<double> residuals) {
    if (predicted.isEmpty) return [];
    final variance = residuals.isEmpty
        ? 0
        : residuals.map((r) => r * r).reduce((a, b) => a + b) / residuals.length;
    final sigma = math.sqrt(variance);
    return predicted.map((p) => p == 0 ? sigma : (sigma / p)).toList();
  }

  List<double> _logSlopeBreaks(List<double> spacing, List<double> obs, int count) {
    final logSpacing = spacing.map((e) => math.log(e)).toList();
    final logRho = obs.map((e) => math.log(e)).toList();
    final slopes = <double>[];
    for (var i = 1; i < logSpacing.length; i++) {
      final ds = logSpacing[i] - logSpacing[i - 1];
      if (ds == 0) continue;
      slopes.add((logRho[i] - logRho[i - 1]) / ds);
    }
    if (slopes.isEmpty) {
      return List<double>.filled(count, spacing.first);
    }
    final sortedIndices = List<int>.generate(slopes.length, (i) => i)
      ..sort((a, b) => slopes[b].abs().compareTo(slopes[a].abs()));
    final breaks = <double>[];
    for (var i = 0; i < count; i++) {
      if (sortedIndices.isEmpty) {
        final idx = math.min(i, spacing.length - 1);
        breaks.add(spacing[idx]);
      } else {
        final slopeIndex = sortedIndices[math.min(i, sortedIndices.length - 1)] + 1;
        final idx = math.min(slopeIndex, spacing.length - 1);
        breaks.add(spacing[idx]);
      }
    }
    return breaks;
  }
}

class _SeedResult {
  const _SeedResult({required this.rhos, required this.thicknesses});

  final List<double> rhos;
  final List<double?> thicknesses;
}
