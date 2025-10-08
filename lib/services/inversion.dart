import 'dart:async';
import 'dart:math' as math;

import '../models/inversion_model.dart';
import '../models/spacing_point.dart';
import '../utils/units.dart';

class OneDInversionResult {
  OneDInversionResult({
    required this.depthsM,
    required this.resistivities,
    required this.fitCurve,
    required this.misfit,
  });

  final List<double> depthsM;
  final List<double> resistivities;
  final List<double> fitCurve;
  final double misfit;

  bool get isFallback => misfit.isInfinite;
}

class _InversionAttempt {
  const _InversionAttempt({
    required this.depths,
    required this.resistivities,
    required this.fit,
    required this.misfit,
  });

  final List<double> depths;
  final List<double> resistivities;
  final List<double> fit;
  final double misfit;

  OneDInversionResult toResult() {
    return OneDInversionResult(
      depthsM: List<double>.from(depths),
      resistivities: List<double>.from(resistivities),
      fitCurve: List<double>.from(fit),
      misfit: misfit,
    );
  }
}

Future<OneDInversionResult> invert1DWenner({
  required List<double> aFt,
  required List<double> rhoAppNS,
  required List<double> rhoAppWE,
  int maxLayers = 3,
  double minRho = 1.0,
  double maxRho = 10000.0,
  double minThick = 0.2,
  double maxThick = 20.0,
  double regLambda = 0.25,
  double outlierSdPct = 20,
}) async {
  final aggregated = _aggregateMeasurements(
    aFt: aFt,
    rhoAppNS: rhoAppNS,
    rhoAppWE: rhoAppWE,
    outlierSdPct: outlierSdPct,
    minRho: minRho,
    maxRho: maxRho,
  );
  if (aggregated.isEmpty) {
    return OneDInversionResult(
      depthsM: const [],
      resistivities: const [],
      fitCurve: const [],
      misfit: double.infinity,
    );
  }
  try {
    return await Future<OneDInversionResult>(() {
      return _runLayeredInversion(
        aggregated: aggregated,
        maxLayers: maxLayers,
        minRho: minRho,
        maxRho: maxRho,
        minThick: minThick,
        maxThick: maxThick,
        regLambda: regLambda,
      );
    }).timeout(const Duration(seconds: 2));
  } on TimeoutException {
    return _fallbackResult(aggregated);
  } catch (_) {
    return _fallbackResult(aggregated);
  }
}

OneDInversionResult _runLayeredInversion({
  required List<_AggregatedMeasurement> aggregated,
  required int maxLayers,
  required double minRho,
  required double maxRho,
  required double minThick,
  required double maxThick,
  required double regLambda,
}) {
  final layerCount = math.max(1, math.min(maxLayers, aggregated.length));
  final baseDepths = _estimateLayerBoundaries(
    aggregated,
    layerCount: layerCount,
    minThick: minThick,
    maxThick: maxThick,
  );

  final baseAttempt = _solveForDepths(
    aggregated: aggregated,
    depths: baseDepths,
    minRho: minRho,
    maxRho: maxRho,
    minThick: minThick,
    maxThick: maxThick,
    regLambda: regLambda,
  );

  if (layerCount < 3) {
    return baseAttempt.toResult();
  }

  final effectiveLayers = _effectiveLayerCount(baseAttempt.resistivities);
  if (effectiveLayers >= layerCount) {
    return baseAttempt.toResult();
  }

  final thicknesses = _buildThicknesses(baseAttempt.depths, minThick, maxThick);
  final splitIndex = _thickestLayerIndex(thicknesses);
  if (splitIndex == null) {
    return baseAttempt.toResult();
  }

  final guard = math.max(minThick, 0.3);
  final top = splitIndex == 0 ? 0.0 : baseAttempt.depths[splitIndex - 1];
  final bottom = baseAttempt.depths[splitIndex];
  final depthSamples = aggregated
      .map((m) => feetToMeters(m.spacingFt * 0.5))
      .where((depth) => depth > top && depth < bottom)
      .toList()
    ..sort();
  if (depthSamples.isEmpty) {
    return baseAttempt.toResult();
  }

  final adjustedDepths = List<double>.from(baseAttempt.depths);
  var candidate = _quantile(depthSamples, 0.5);
  final minAllowed = top + guard;
  final maxAllowed = math.max(minAllowed, math.min(bottom - guard, top + maxThick));
  candidate = candidate.clamp(minAllowed, maxAllowed);
  if (candidate <= top || candidate >= bottom) {
    return baseAttempt.toResult();
  }
  adjustedDepths[splitIndex] = candidate;

  final restartAttempt = _solveForDepths(
    aggregated: aggregated,
    depths: adjustedDepths,
    minRho: minRho,
    maxRho: maxRho,
    minThick: minThick,
    maxThick: maxThick,
    regLambda: regLambda,
  );

  if (restartAttempt.misfit < baseAttempt.misfit * 0.95) {
    return restartAttempt.toResult();
  }

  return baseAttempt.toResult();
}

OneDInversionResult _fallbackResult(List<_AggregatedMeasurement> aggregated) {
  final depths = <double>[];
  final resistivities = <double>[];
  final fit = <double>[];
  for (final measurement in aggregated) {
    final depth = feetToMeters(measurement.spacingFt * 0.5);
    depths.add(depth);
    resistivities.add(measurement.rho);
    fit.add(measurement.rho);
  }
  return OneDInversionResult(
    depthsM: depths,
    resistivities: resistivities,
    fitCurve: fit,
    misfit: double.infinity,
  );
}

_InversionAttempt _solveForDepths({
  required List<_AggregatedMeasurement> aggregated,
  required List<double> depths,
  required double minRho,
  required double maxRho,
  required double minThick,
  required double maxThick,
  required double regLambda,
}) {
  final spacingMeters = aggregated.map((m) => m.spacingMeters).toList();
  final thicknesses = _buildThicknesses(depths, minThick, maxThick);
  final resistivities = _estimateLayerResistivities(
    aggregated,
    depths: depths,
    minRho: minRho,
    maxRho: maxRho,
    regLambda: regLambda,
  );
  final logRhos = resistivities.map(math.log).toList();
  final fit = _forwardApparentRho(spacingMeters, thicknesses, logRhos);
  final observed = aggregated.map((m) => m.rho).toList();
  final misfit = _normalizedMisfit(observed, fit);
  return _InversionAttempt(
    depths: List<double>.from(depths),
    resistivities: List<double>.from(resistivities),
    fit: List<double>.from(fit),
    misfit: misfit,
  );
}

List<_AggregatedMeasurement> _aggregateMeasurements({
  required List<double> aFt,
  required List<double> rhoAppNS,
  required List<double> rhoAppWE,
  required double outlierSdPct,
  required double minRho,
  required double maxRho,
}) {
  final entries = <_SpacingEntry>[];
  final nsValues = <double>[];
  final weValues = <double>[];
  for (var i = 0; i < aFt.length; i++) {
    final spacing = aFt[i];
    final ns = i < rhoAppNS.length ? _validValue(rhoAppNS[i]) : null;
    final we = i < rhoAppWE.length ? _validValue(rhoAppWE[i]) : null;
    entries.add(_SpacingEntry(spacingFt: spacing, ns: ns, we: we));
    if (ns != null) {
      nsValues.add(ns);
    }
    if (we != null) {
      weValues.add(we);
    }
  }
  final medianNs = _median(nsValues);
  final medianWe = _median(weValues);
  final result = <_AggregatedMeasurement>[];
  for (final entry in entries) {
    var ns = entry.ns;
    var we = entry.we;
    if (ns != null && medianNs != null) {
      final deviation = (ns - medianNs).abs() / medianNs * 100;
      if (deviation > outlierSdPct) {
        ns = null;
      }
    }
    if (we != null && medianWe != null) {
      final deviation = (we - medianWe).abs() / medianWe * 100;
      if (deviation > outlierSdPct) {
        we = null;
      }
    }
    final values = <double>[];
    if (ns != null) {
      values.add(ns);
    }
    if (we != null) {
      values.add(we);
    }
    if (values.isEmpty) {
      continue;
    }
    final mean = values.reduce((a, b) => a + b) / values.length;
    final clamped = mean.clamp(minRho, maxRho).toDouble();
    result.add(
      _AggregatedMeasurement(
        spacingFt: entry.spacingFt,
        spacingMeters: feetToMeters(entry.spacingFt),
        rho: clamped,
      ),
    );
  }
  result.sort((a, b) => a.spacingFt.compareTo(b.spacingFt));
  return result;
}

List<double> _estimateLayerBoundaries(
  List<_AggregatedMeasurement> aggregated, {
  required int layerCount,
  required double minThick,
  required double maxThick,
}) {
  if (layerCount <= 0) {
    return const [];
  }
  final guard = math.max(minThick, 0.3);
  final depthSamples = aggregated
      .map((m) => feetToMeters(m.spacingFt * 0.5))
      .toList()
    ..sort();
  final maxDepthAvailable =
      depthSamples.isEmpty ? guard * layerCount : depthSamples.last;
  final result = <double>[];
  var previous = 0.0;
  for (var i = 1; i <= layerCount; i++) {
    final fraction = depthSamples.isEmpty ? i / layerCount : i / layerCount;
    var target = depthSamples.isEmpty
        ? previous + guard
        : _quantile(depthSamples, fraction);
    final minDepth = previous + guard;
    final maxDepth = math.min(previous + maxThick, maxDepthAvailable);
    final clampedMax = math.max(minDepth, maxDepth);
    if (target < minDepth) {
      target = minDepth;
    }
    if (target > clampedMax) {
      target = clampedMax;
    }
    if (target - previous < guard) {
      target = math.min(clampedMax, previous + guard);
    }
    result.add(target);
    previous = target;
  }
  return result;
}

List<double> _estimateLayerResistivities(
  List<_AggregatedMeasurement> aggregated, {
  required List<double> depths,
  required double minRho,
  required double maxRho,
  required double regLambda,
}) {
  if (depths.isEmpty) {
    final median = _median(aggregated.map((m) => m.rho).toList()) ?? minRho;
    return [median.clamp(minRho, maxRho).toDouble()];
  }
  final allLogs = aggregated.map((m) => math.log(m.rho)).toList()..sort();
  final resistivities = <double>[];
  for (var i = 0; i < depths.length; i++) {
    final top = i == 0 ? 0.0 : depths[i - 1];
    final bottom = depths[i];
    final logsInLayer = <double>[];
    for (final measurement in aggregated) {
      final depth = feetToMeters(measurement.spacingFt * 0.5);
      final isLastLayer = i == depths.length - 1;
      final withinLayer =
          isLastLayer ? depth >= top : (depth >= top && depth < bottom);
      if (withinLayer) {
        logsInLayer.add(math.log(measurement.rho));
      }
    }
    double logValue;
    if (logsInLayer.isEmpty) {
      final fraction = (i + 0.5) / depths.length;
      logValue = _quantile(allLogs, fraction);
    } else {
      logsInLayer.sort();
      final mid = logsInLayer.length ~/ 2;
      if (logsInLayer.length.isOdd) {
        logValue = logsInLayer[mid];
      } else {
        logValue = (logsInLayer[mid - 1] + logsInLayer[mid]) / 2;
      }
    }
    final rho = math.exp(logValue).clamp(minRho, maxRho).toDouble();
    resistivities.add(rho);
  }
  final lambda = regLambda.clamp(0.0, 1.0);
  if (resistivities.length > 1 && lambda > 0) {
    for (var i = 1; i < resistivities.length; i++) {
      final blended =
          lambda * resistivities[i - 1] + (1 - lambda) * resistivities[i];
      resistivities[i] = blended.clamp(minRho, maxRho);
    }
    for (var i = resistivities.length - 2; i >= 0; i--) {
      final blended =
          lambda * resistivities[i + 1] + (1 - lambda) * resistivities[i];
      resistivities[i] = blended.clamp(minRho, maxRho);
    }
  }
  return resistivities;
}

List<double?> _buildThicknesses(List<double> boundaries, double minThick, double maxThick) {
  if (boundaries.isEmpty) {
    return [null];
  }
  final thicknesses = <double?>[];
  for (var i = 0; i < boundaries.length; i++) {
    if (i == boundaries.length - 1) {
      thicknesses.add(null);
    } else {
      final top = i == 0 ? 0.0 : boundaries[i - 1];
      final bottom = boundaries[i];
      final thickness = (bottom - top).clamp(minThick, maxThick).toDouble();
      thicknesses.add(thickness);
    }
  }
  return thicknesses;
}

int _effectiveLayerCount(List<double> resistivities) {
  if (resistivities.isEmpty) {
    return 0;
  }
  var count = 1;
  for (var i = 1; i < resistivities.length; i++) {
    final prev = resistivities[i - 1].abs();
    final curr = resistivities[i].abs();
    final denom = math.max(prev, 1e-6);
    if ((curr - prev).abs() / denom > 0.08) {
      count += 1;
    }
  }
  return count;
}

int? _thickestLayerIndex(List<double?> thicknesses) {
  var maxThickness = 0.0;
  int? index;
  for (var i = 0; i < thicknesses.length; i++) {
    final thickness = thicknesses[i];
    if (thickness == null) {
      continue;
    }
    if (thickness > maxThickness) {
      maxThickness = thickness;
      index = i;
    }
  }
  return index;
}

List<double> _forwardApparentRho(
  List<double> spacingsMeters,
  List<double?> thicknesses,
  List<double> logRhos,
) {
  final rhos = logRhos.map(math.exp).toList();
  final outputs = <double>[];
  for (final spacing in spacingsMeters) {
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

double _depthWeight(double depth, double top, double bottom) {
  final center = (top + bottom) / 2;
  final radius = (bottom - top) / 2;
  final distance = (depth - center).abs();
  final scale = math.max(radius, 1e-3);
  return math.exp(-distance / scale);
}

double _normalizedMisfit(List<double> observed, List<double> predicted) {
  final length = math.min(observed.length, predicted.length);
  if (length == 0) {
    return double.infinity;
  }
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < length; i++) {
    final residual = observed[i] - predicted[i];
    numerator += residual * residual;
    denominator += observed[i] * observed[i];
  }
  if (denominator <= 1e-12) {
    return math.sqrt(numerator);
  }
  return math.sqrt(numerator) / math.sqrt(denominator);
}

double? _validValue(double value) {
  if (value.isNaN || value.isInfinite || value <= 0) {
    return null;
  }
  return value;
}

double? _median(List<double> values) {
  if (values.isEmpty) {
    return null;
  }
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

double _quantile(List<double> values, double fraction) {
  if (values.isEmpty) {
    return 0;
  }
  final clamped = fraction.clamp(0.0, 1.0);
  final position = clamped * (values.length - 1);
  final lowerIndex = position.floor();
  final upperIndex = position.ceil();
  final lower = values[lowerIndex];
  final upper = values[upperIndex];
  if (lowerIndex == upperIndex) {
    return lower;
  }
  final weight = position - lowerIndex;
  return lower + (upper - lower) * weight;
}

class _SpacingEntry {
  _SpacingEntry({required this.spacingFt, this.ns, this.we});

  final double spacingFt;
  double? ns;
  double? we;
}

class _AggregatedMeasurement {
  _AggregatedMeasurement({
    required this.spacingFt,
    required this.spacingMeters,
    required this.rho,
  });

  final double spacingFt;
  final double spacingMeters;
  final double rho;
}

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
