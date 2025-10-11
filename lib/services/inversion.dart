import 'dart:async';
import 'dart:math' as math;

import '../models/calc.dart' as calc;
import '../models/inversion_model.dart';
import '../models/site.dart';
import '../models/spacing_point.dart';
import '../utils/units.dart' as units;

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

class TwoLayerInversionResult {
  TwoLayerInversionResult({
    required List<double> spacingFeet,
    required List<double> measurementDepthsM,
    required List<double> observedRho,
    required List<double> predictedRho,
    required List<double> layerDepths,
    required this.rho1,
    required this.rho2,
    this.halfSpaceRho,
    required this.rms,
    this.thicknessM,
    DateTime? solvedAt,
  })  : spacingFeet = List.unmodifiable(spacingFeet),
        measurementDepthsM = List.unmodifiable(measurementDepthsM),
        observedRho = List.unmodifiable(observedRho),
        predictedRho = List.unmodifiable(predictedRho),
        layerDepths = List.unmodifiable(layerDepths),
        solvedAt = solvedAt ?? DateTime.now();

  final List<double> spacingFeet;
  final List<double> measurementDepthsM;
  final List<double> observedRho;
  final List<double> predictedRho;
  final List<double> layerDepths;
  final double rho1;
  final double rho2;
  final double? halfSpaceRho;
  final double rms;
  final double? thicknessM;
  final DateTime solvedAt;

  double? get thicknessFeet =>
      thicknessM == null ? null : units.metersToFeet(thicknessM!).toDouble();

  double get maxDepthMeters {
    final candidates = <double>[];
    if (measurementDepthsM.isNotEmpty) {
      candidates.add(measurementDepthsM.reduce(math.max));
    }
    if (thicknessM != null) {
      candidates.add(thicknessM!);
    }
    if (layerDepths.isNotEmpty) {
      candidates.add(layerDepths.last);
    }
    if (candidates.isEmpty) {
      return 0;
    }
    return candidates.reduce(math.max);
  }

  Iterable<double> get _allRhoSamples sync* {
    if (rho1.isFinite && rho1 > 0) {
      yield rho1;
    }
    if (rho2.isFinite && rho2 > 0) {
      yield rho2;
    }
    if (halfSpaceRho != null && halfSpaceRho!.isFinite && halfSpaceRho! > 0) {
      yield halfSpaceRho!;
    }
    for (final value in observedRho) {
      if (value.isFinite && value > 0) {
        yield value;
      }
    }
    for (final value in predictedRho) {
      if (value.isFinite && value > 0) {
        yield value;
      }
    }
  }

  double get minRho => _allRhoSamples.isEmpty ? 1 : _allRhoSamples.reduce(math.min);

  double get maxRho => _allRhoSamples.isEmpty ? 1 : _allRhoSamples.reduce(math.max);
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

class _LogClamp {
  const _LogClamp(this.lower, this.upper);

  final double lower;
  final double upper;
}

class _LogBand {
  const _LogBand({required this.lower, required this.upper});

  final double lower;
  final double upper;
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

Future<TwoLayerInversionResult?> invertTwoLayerSite(SiteRecord site) async {
  final input = _aggregateSiteForInversion(site);
  if (input.spacingFeet.length < 2) {
    return null;
  }
  final result = await invert1DWenner(
    aFt: input.spacingFeet,
    rhoAppNS: input.rhoNs,
    rhoAppWE: input.rhoWe,
    maxLayers: 2,
  );
  if (result.isFallback || result.resistivities.length < 2) {
    return null;
  }
  final thicknessM = result.depthsM.isEmpty ? null : result.depthsM.first;
  final fit = result.fitCurve.length == input.spacingFeet.length
      ? result.fitCurve
      : List<double>.generate(
          input.spacingFeet.length,
          (index) =>
              result.fitCurve[index < result.fitCurve.length ? index : result.fitCurve.length - 1],
        );
  final summary = TwoLayerInversionResult(
    spacingFeet: input.spacingFeet,
    measurementDepthsM: input.depthsM,
    observedRho: input.observed,
    predictedRho: fit,
    layerDepths: result.depthsM,
    rho1: result.resistivities.first,
    rho2: result.resistivities[1],
    halfSpaceRho: result.resistivities.length > 2 ? result.resistivities.last : null,
    rms: result.misfit,
    thicknessM: thicknessM,
  );
  // QA instrumentation per workflow plan.
  // ignore: avoid_print
  print('RMS = ${summary.rms.toStringAsFixed(3)}');
  return summary;
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
  final int layerCount =
      math.max(1, math.min(maxLayers, aggregated.length)).toInt();
  final baseDepths = _estimateLayerBoundaries(
    aggregated,
    layerCount: layerCount,
    minThick: minThick,
    maxThick: maxThick,
  );

  final logClamp = _logClampFor(aggregated, minRho, maxRho);

  final baseAttempt = _solveForDepths(
    aggregated: aggregated,
    depths: baseDepths,
    minRho: minRho,
    maxRho: maxRho,
    minThick: minThick,
    maxThick: maxThick,
    regLambda: regLambda,
    lowerLogBound: logClamp.lower,
    upperLogBound: logClamp.upper,
  );

  var bestAttempt = baseAttempt;

  if (layerCount >= 3) {
    final effectiveLayers = _effectiveLayerCount(baseAttempt.resistivities);
    if (effectiveLayers < layerCount) {
      final thicknesses =
          _buildThicknesses(baseAttempt.depths, minThick, maxThick);
      final splitIndex = _thickestLayerIndex(thicknesses);
      if (splitIndex != null) {
        final guard = math.max(minThick, 0.25);
        final top = splitIndex == 0 ? 0.0 : baseAttempt.depths[splitIndex - 1];
        final bottom = baseAttempt.depths[splitIndex];
        final depthSamples = aggregated
            .map((m) => units.feetToMeters(m.spacingFt * 0.5).toDouble())
            .where((depth) => depth > top && depth < bottom)
            .toList()
          ..sort();

        final adjustedDepths = List<double>.from(baseAttempt.depths);
        final midpoint = top + (bottom - top) / 2;
        final sampledDepth =
            depthSamples.isEmpty ? midpoint : _quantile(depthSamples, 0.5);
        final minAllowed = top + guard;
        final maxAllowed = math.max(
          minAllowed,
          math.min(bottom - guard, top + maxThick),
        );
        final candidate = sampledDepth.clamp(minAllowed, maxAllowed);
        if (candidate > top && candidate < bottom) {
          adjustedDepths[splitIndex] = candidate;
          var previous = candidate;
          for (var i = splitIndex + 1; i < adjustedDepths.length; i++) {
            final minDepth = previous + guard;
            adjustedDepths[i] = math.max(adjustedDepths[i], minDepth);
            previous = adjustedDepths[i];
          }

          final seedResistivities =
              List<double>.from(baseAttempt.resistivities);
          seedResistivities[splitIndex] = (seedResistivities[splitIndex] * 0.9)
              .clamp(minRho, maxRho)
              .toDouble();
          if (splitIndex + 1 < seedResistivities.length) {
            seedResistivities[splitIndex + 1] =
                (seedResistivities[splitIndex + 1] * 1.1)
                    .clamp(minRho, maxRho)
                    .toDouble();
          }
          var restartLambda = regLambda * 0.6;
          if (layerCount < 3) {
            restartLambda *= 0.65;
          }
          restartLambda = restartLambda.clamp(0.12, 0.3);

          _clampFirstLayerSeed(seedResistivities, aggregated, minRho, maxRho);

          var lambdaForAttempt = restartLambda;
          List<double>? attemptSeed = seedResistivities;
          for (var attemptIndex = 0; attemptIndex < 2; attemptIndex++) {
            final restartAttempt = _solveForDepths(
              aggregated: aggregated,
              depths: adjustedDepths,
              minRho: minRho,
              maxRho: maxRho,
              minThick: minThick,
              maxThick: maxThick,
              regLambda: lambdaForAttempt,
              lowerLogBound: logClamp.lower,
              upperLogBound: logClamp.upper,
              seedResistivities: attemptSeed,
            );

            if (_shouldAcceptRestart(bestAttempt, restartAttempt)) {
              bestAttempt = restartAttempt;
              break;
            }

            final misfitBlewUp = bestAttempt.misfit.isFinite
                ? restartAttempt.misfit >= bestAttempt.misfit * 2
                : restartAttempt.misfit.isInfinite;
            if (!misfitBlewUp || attemptIndex == 1) {
              break;
            }

            lambdaForAttempt = math.max(regLambda * 0.8, 0.2);
            attemptSeed = _estimateLayerResistivities(
              aggregated,
              depths: adjustedDepths,
              minRho: minRho,
              maxRho: maxRho,
              regLambda: lambdaForAttempt,
              lowerLogBound: logClamp.lower,
              upperLogBound: logClamp.upper,
            );
            _clampFirstLayerSeed(attemptSeed, aggregated, minRho, maxRho);
          }
        }
      }
    }
  }

  if (!bestAttempt.misfit.isFinite || bestAttempt.misfit > 0.45) {
    final segmentedAttempt = _segmentalApproximation(
      aggregated: aggregated,
      maxLayers: layerCount,
      minThick: minThick,
      maxThick: maxThick,
      minRho: minRho,
      maxRho: maxRho,
      lowerLogBound: logClamp.lower,
      upperLogBound: logClamp.upper,
    );
    final segmentedBetter = segmentedAttempt.misfit.isFinite &&
        (!bestAttempt.misfit.isFinite ||
            segmentedAttempt.misfit < bestAttempt.misfit);
    if (segmentedBetter) {
      bestAttempt = segmentedAttempt;
    }
  }

  return bestAttempt.toResult();
}

bool _shouldAcceptRestart(
  _InversionAttempt current,
  _InversionAttempt candidate,
) {
  if (!candidate.misfit.isFinite) {
    return false;
  }
  if (!current.misfit.isFinite) {
    return true;
  }
  if (current.misfit <= 0) {
    return candidate.misfit < current.misfit;
  }
  final improvement = current.misfit - candidate.misfit;
  return improvement > current.misfit * 0.05;
}

void _clampFirstLayerSeed(
  List<double>? seed,
  List<_AggregatedMeasurement> aggregated,
  double minRho,
  double maxRho,
) {
  if (seed == null || seed.isEmpty || aggregated.isEmpty) {
    return;
  }
  final band = _firstLayerLogBand(aggregated, minRho, maxRho);
  if (band == null) {
    return;
  }
  final clamped = math.log(seed.first.clamp(minRho, maxRho))
      .clamp(band.lower, band.upper);
  seed[0] = math.exp(clamped).clamp(minRho, maxRho).toDouble();
}

_LogBand? _firstLayerLogBand(
  List<_AggregatedMeasurement> aggregated,
  double minRho,
  double maxRho,
) {
  if (aggregated.isEmpty) {
    return null;
  }
  final logs = aggregated
      .map((m) => math.log(m.rho.clamp(minRho, maxRho)))
      .toList()
    ..sort();
  final minLog = math.log(minRho);
  final maxLog = math.log(maxRho);
  final q25 = _quantile(logs, 0.25);
  final q75 = _quantile(logs, 0.75);
  final iqr = q75 - q25;
  final lower = (q25 - 1.8 * iqr).clamp(minLog, maxLog);
  final upper = (q75 + 1.8 * iqr).clamp(minLog, maxLog);
  return _LogBand(lower: lower, upper: upper);
}

_LogClamp _logClampFor(
  List<_AggregatedMeasurement> aggregated,
  double minRho,
  double maxRho,
) {
  final minLog = math.log(minRho);
  final maxLog = math.log(maxRho);
  if (aggregated.isEmpty) {
    return _LogClamp(minLog, maxLog);
  }
  final logs = aggregated
      .map((m) => math.log(m.rho.clamp(minRho, maxRho)))
      .toList()
    ..sort();
  final median = _quantile(logs, 0.5);
  final q1 = _quantile(logs, 0.25);
  final q3 = _quantile(logs, 0.75);
  final iqr = q3 - q1;
  final band = iqr > 0 ? 1.8 * iqr : (maxLog - minLog) * 0.5;
  final lower = (median - band).clamp(minLog, maxLog);
  final upper = (median + band).clamp(minLog, maxLog);
  return _LogClamp(lower, upper);
}

OneDInversionResult _fallbackResult(List<_AggregatedMeasurement> aggregated) {
  final depths = <double>[];
  final resistivities = <double>[];
  final fit = <double>[];
  for (final measurement in aggregated) {
    final depth = units.feetToMeters(measurement.spacingFt * 0.5);
    depths.add(depth.toDouble());
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
  double? lowerLogBound,
  double? upperLogBound,
  List<double>? seedResistivities,
}) {
  final spacingMeters = aggregated.map((m) => m.spacingMeters).toList();
  final thicknesses = _buildThicknesses(depths, minThick, maxThick);
  final resistivities = _estimateLayerResistivities(
    aggregated,
    depths: depths,
    minRho: minRho,
    maxRho: maxRho,
    regLambda: regLambda,
    lowerLogBound: lowerLogBound,
    upperLogBound: upperLogBound,
    seed: seedResistivities,
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

_InversionAttempt _segmentalApproximation({
  required List<_AggregatedMeasurement> aggregated,
  required int maxLayers,
  required double minThick,
  required double maxThick,
  required double minRho,
  required double maxRho,
  double? lowerLogBound,
  double? upperLogBound,
}) {
  if (aggregated.isEmpty) {
    return const _InversionAttempt(
      depths: [],
      resistivities: [],
      fit: [],
      misfit: double.infinity,
    );
  }

  final count = aggregated.length;
  final targetLayers = math.max(1, math.min(maxLayers, count));
  final logs = List<double>.generate(count, (index) {
    final rho = aggregated[index].rho.clamp(minRho, maxRho);
    var logValue = math.log(rho);
    if (lowerLogBound != null && upperLogBound != null) {
      logValue = logValue.clamp(lowerLogBound, upperLogBound);
    }
    return logValue;
  });
  final prefix = List<double>.filled(count + 1, 0);
  final prefixSq = List<double>.filled(count + 1, 0);
  for (var i = 0; i < count; i++) {
    final value = logs[i];
    prefix[i + 1] = prefix[i] + value;
    prefixSq[i + 1] = prefixSq[i] + value * value;
  }

  double segmentCost(int start, int end) {
    final length = end - start;
    if (length <= 0) {
      return 0;
    }
    final sum = prefix[end] - prefix[start];
    final sumSq = prefixSq[end] - prefixSq[start];
    final mean = sum / length;
    return sumSq - 2 * mean * sum + length * mean * mean;
  }

  const infinity = double.infinity;
  final dp = List.generate(
    targetLayers + 1,
    (_) => List<double>.filled(count + 1, infinity),
  );
  final back = List.generate(
    targetLayers + 1,
    (_) => List<int>.filled(count + 1, 0),
  );
  dp[0][0] = 0;

  for (var layers = 1; layers <= targetLayers; layers++) {
    for (var end = layers; end <= count; end++) {
      var bestCost = double.infinity;
      var bestSplit = layers - 1;
      for (var split = layers - 1; split <= end - 1; split++) {
        final previous = dp[layers - 1][split];
        if (!previous.isFinite) {
          continue;
        }
        final cost = previous + segmentCost(split, end);
        if (cost < bestCost) {
          bestCost = cost;
          bestSplit = split;
        }
      }
      dp[layers][end] = bestCost;
      back[layers][end] = bestSplit;
    }
  }

  var bestLayerCount = 1;
  var bestScore = dp[1][count];
  for (var layers = 2; layers <= targetLayers; layers++) {
    final score = dp[layers][count];
    if (score < bestScore) {
      bestScore = score;
      bestLayerCount = layers;
    }
  }

  if (!bestScore.isFinite) {
    final depths = aggregated
        .map((m) => units.feetToMeters(m.spacingFt * 0.5))
        .map((value) => value.toDouble())
        .toList();
    final resistivities = aggregated.map((m) {
      var logValue = math.log(m.rho.clamp(minRho, maxRho));
      if (lowerLogBound != null && upperLogBound != null) {
        logValue = logValue.clamp(lowerLogBound, upperLogBound);
      }
      return math.exp(logValue).clamp(minRho, maxRho).toDouble();
    }).toList();
    final observed = aggregated.map((m) => m.rho).toList();
    return _InversionAttempt(
      depths: depths,
      resistivities: resistivities,
      fit: observed,
      misfit: double.infinity,
    );
  }

  var end = count;
  var segments = <MapEntry<int, int>>[];
  for (var layer = bestLayerCount; layer >= 1; layer--) {
    final start = back[layer][end];
    segments.add(MapEntry(start, end));
    end = start;
  }
  segments = segments.reversed.toList();

  final depths = <double>[];
  final resistivities = <double>[];
  for (final segment in segments) {
    final start = segment.key;
    final finish = segment.value;
    final length = finish - start;
    final sum = prefix[finish] - prefix[start];
    final meanLog = length == 0 ? 0.0 : sum / length;
    final boundedLog = (lowerLogBound != null && upperLogBound != null)
        ? meanLog.clamp(lowerLogBound, upperLogBound)
        : meanLog;
    final rho = math.exp(boundedLog).clamp(minRho, maxRho).toDouble();
    resistivities.add(rho);
    final depthIndex = math.max(0, finish - 1);
    final depth = units.feetToMeters(aggregated[depthIndex].spacingFt * 0.5);
    depths.add(depth.toDouble());
  }

  final guard = math.max(minThick, 0.25);
  final maxDepthAvailable = units.feetToMeters(aggregated.last.spacingFt * 0.5).toDouble();
  var previousDepth = 0.0;
  for (var i = 0; i < depths.length; i++) {
    var depth = depths[i];
    final minDepth = previousDepth + guard;
    if (depth < minDepth) {
      depth = minDepth;
    }
    final maxDepth = math.min(previousDepth + maxThick, maxDepthAvailable);
    depth = depth
        .clamp(minDepth, math.max(minDepth, maxDepth))
        .toDouble();
    depths[i] = depth;
    previousDepth = depth;
  }

  final spacingMeters = aggregated.map((m) => m.spacingMeters).toList();
  final thicknesses = _buildThicknesses(depths, minThick, maxThick);
  final logRhos = resistivities.map(math.log).toList();
  final fit = _forwardApparentRho(spacingMeters, thicknesses, logRhos);
  final observed = aggregated.map((m) => m.rho).toList();
  final misfit = _normalizedMisfit(observed, fit);

  return _InversionAttempt(
    depths: depths,
    resistivities: resistivities,
    fit: fit,
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
  for (var i = 0; i < aFt.length; i++) {
    final spacing = aFt[i];
    final ns = i < rhoAppNS.length ? _validValue(rhoAppNS[i]) : null;
    final we = i < rhoAppWE.length ? _validValue(rhoAppWE[i]) : null;
    entries.add(_SpacingEntry(spacingFt: spacing, ns: ns, we: we));
  }
  final result = <_AggregatedMeasurement>[];
  for (final entry in entries) {
    var ns = entry.ns;
    var we = entry.we;
    if (ns != null && we != null) {
      final mean = (ns + we) / 2;
      final denom = mean.abs() < 1e-6 ? 1.0 : mean.abs();
      final nsDeviation = (ns - mean).abs() / denom * 100;
      final weDeviation = (we - mean).abs() / denom * 100;
      if (nsDeviation > outlierSdPct && weDeviation > outlierSdPct) {
        if (nsDeviation > weDeviation) {
          ns = null;
        } else if (weDeviation > nsDeviation) {
          we = null;
        } else {
          ns = null;
          we = null;
        }
      } else {
        if (nsDeviation > outlierSdPct) {
          ns = null;
        }
        if (weDeviation > outlierSdPct) {
          we = null;
        }
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
        spacingMeters: units.feetToMeters(entry.spacingFt).toDouble(),
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
  final guard = math.max(minThick, 0.25);
  final depthSamples = aggregated
      .map((m) => units.feetToMeters(m.spacingFt * 0.5).toDouble())
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
  double? lowerLogBound,
  double? upperLogBound,
  List<double>? seed,
}) {
  if (depths.isEmpty) {
    final median = _median(aggregated.map((m) => m.rho).toList()) ?? minRho;
    final logMedian = math.log(median.clamp(minRho, maxRho));
    final boundedLog = (lowerLogBound != null && upperLogBound != null)
        ? logMedian.clamp(lowerLogBound, upperLogBound)
        : logMedian;
    return [math.exp(boundedLog).clamp(minRho, maxRho).toDouble()];
  }
  final allLogs = aggregated.map((m) => math.log(m.rho)).toList()..sort();
  final sortedRhos = aggregated
      .map((m) => m.rho.clamp(minRho, maxRho).toDouble())
      .toList()
    ..sort();
  double? firstLayerLower;
  double? firstLayerUpper;
  if (sortedRhos.isNotEmpty) {
    final q25 = _quantile(sortedRhos, 0.25);
    final q75 = _quantile(sortedRhos, 0.75);
    final iqr = q75 - q25;
    final lo = iqr > 0 ? q25 - 1.8 * iqr : q25;
    final hi = iqr > 0 ? q75 + 1.8 * iqr : q75;
    firstLayerLower = math.max(minRho, lo);
    firstLayerUpper = math.min(maxRho, hi);
  }
  final resistivities = <double>[];
  for (var i = 0; i < depths.length; i++) {
    final top = i == 0 ? 0.0 : depths[i - 1];
    final bottom = depths[i];
    final logsInLayer = <double>[];
    for (final measurement in aggregated) {
      final depth = units.feetToMeters(measurement.spacingFt * 0.5).toDouble();
      final isLastLayer = i == depths.length - 1;
      final withinLayer =
          isLastLayer ? depth >= top : (depth >= top && depth < bottom);
      if (withinLayer) {
        logsInLayer.add(math.log(measurement.rho));
      }
    }
    double logValue;
    if (logsInLayer.isEmpty) {
      final fraction = (i + 1) / (depths.length + 1);
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
    if (lowerLogBound != null && upperLogBound != null) {
      logValue = logValue.clamp(lowerLogBound, upperLogBound);
    }
    if (i == 0 && allLogs.isNotEmpty) {
      final shallow = _quantile(allLogs, 0.25);
      logValue = math.min(logValue, shallow);
      if (lowerLogBound != null) {
        logValue = math.max(logValue, lowerLogBound);
      }
    }
    var rho = math.exp(logValue).clamp(minRho, maxRho).toDouble();
    if (seed != null && i < seed.length) {
      final blended = 0.25 * seed[i] + 0.75 * rho;
      rho = blended.clamp(minRho, maxRho).toDouble();
    }
    if (lowerLogBound != null && upperLogBound != null) {
      final logRho = math.log(rho).clamp(lowerLogBound, upperLogBound);
      rho = math.exp(logRho).clamp(minRho, maxRho).toDouble();
    }
    if (i == 0 && firstLayerLower != null && firstLayerUpper != null) {
      rho = rho.clamp(firstLayerLower, firstLayerUpper).toDouble();
    }
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

class _SiteInversionInput {
  const _SiteInversionInput({
    required this.spacingFeet,
    required this.rhoNs,
    required this.rhoWe,
    required this.observed,
    required this.depthsM,
  });

  final List<double> spacingFeet;
  final List<double> rhoNs;
  final List<double> rhoWe;
  final List<double> observed;
  final List<double> depthsM;
}

_SiteInversionInput _aggregateSiteForInversion(SiteRecord site) {
  final spacingFeet = <double>[];
  final rhoNs = <double>[];
  final rhoWe = <double>[];
  final observed = <double>[];
  final depths = <double>[];
  final spacings = [...site.spacings]
    ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
  for (final spacing in spacings) {
    final aSample = spacing.orientationA.latest;
    final bSample = spacing.orientationB.latest;
    final hasA =
        aSample != null && !aSample.isBad && (aSample.resistanceOhm ?? 0) > 0;
    final hasB =
        bSample != null && !bSample.isBad && (bSample.resistanceOhm ?? 0) > 0;
    if (!hasA && !hasB) {
      continue;
    }
    double? rhoA;
    if (hasA) {
      rhoA = calc.rhoAWenner(spacing.spacingFeet, aSample!.resistanceOhm!);
    }
    double? rhoB;
    if (hasB) {
      rhoB = calc.rhoAWenner(spacing.spacingFeet, bSample!.resistanceOhm!);
    }
    final values = <double>[if (rhoA != null) rhoA, if (rhoB != null) rhoB];
    if (values.isEmpty) {
      continue;
    }
    final average = values.reduce((a, b) => a + b) / values.length;
    spacingFeet.add(spacing.spacingFeet);
    rhoNs.add(rhoA ?? average);
    rhoWe.add(rhoB ?? average);
    observed.add(average);
    depths.add(units.feetToMeters(spacing.spacingFeet * 0.5).toDouble());
  }
  return _SiteInversionInput(
    spacingFeet: spacingFeet,
    rhoNs: rhoNs,
    rhoWe: rhoWe,
    observed: observed,
    depthsM: depths,
  );
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

    final totalIterations = maxIterations + 4;
    for (var iter = 0; iter < totalIterations; iter++) {
      predicted = _forward(spacings, thicknesses, logRhos);
      final residuals = List<double>.generate(
        predicted.length,
        (i) => observations[i] - predicted[i],
      );

      final rms = _rms(residuals);
      if (!rms.isFinite) {
        break;
      }
      final improvement = (lastRms - rms).abs();
      if ((improvement < 0.08 && iter >= 2) || rms < 0.32) {
        lastRms = rms;
        break;
      }
      lastRms = rms;

      final jacobian = _jacobian(spacings, thicknesses, logRhos, predicted);
      final update = _levenbergMarquardtStep(jacobian, residuals, lambda);

      for (var i = 0; i < logRhos.length; i++) {
        logRhos[i] += update[i];
      }
      if (improvement < 0.15 && rms > 0.4) {
        lambda = math.max(0.05, lambda * 0.5);
      } else {
        lambda = math.max(0.05, lambda * 0.7);
      }
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
      return _SeedResult(rhos: rhos, thicknesses: thicknesses);
    }

    final increments = _logSlopeBreaks(spacings, obs, layerCount - 1);
    for (var i = 0; i < layerCount - 1; i++) {
      thicknesses.add(increments[i]);
    }
    thicknesses.add(null);

    if (layerCount >= 2 && spacings.isNotEmpty) {
      final paired = List<MapEntry<double, double>>.generate(
        spacings.length,
        (index) => MapEntry(spacings[index], obs[index]),
      )..sort((a, b) => a.key.compareTo(b.key));

      final leadingSamples = paired
          .take(math.min(3, paired.length))
          .map((entry) => entry.value)
          .where((value) => value.isFinite && value > 0)
          .toList();
      final trailingSamples = paired
          .reversed
          .take(math.min(3, paired.length))
          .map((entry) => entry.value)
          .where((value) => value.isFinite && value > 0)
          .toList();

      final rho1Seed =
          leadingSamples.isEmpty ? median : _median(leadingSamples);
      final rho2Seed =
          trailingSamples.isEmpty ? median : _median(trailingSamples);

      final sanitizedRho1 =
          rho1Seed.isFinite && rho1Seed > 0 ? rho1Seed : math.max(median, 1.0);
      final sanitizedRho2 =
          rho2Seed.isFinite && rho2Seed > 0 ? rho2Seed : math.max(median, 1.0);

      rhos[0] = sanitizedRho1;
      if (rhos.length > 1) {
        rhos[1] = sanitizedRho2;
      }

      final twoLayerSeed =
          _gridSearchTwoLayerSeed(paired, sanitizedRho1, sanitizedRho2);
      if (twoLayerSeed != null) {
        rhos[0] = twoLayerSeed.rho1;
        if (rhos.length > 1) {
          rhos[1] = twoLayerSeed.rho2;
        }
        if (thicknesses.isNotEmpty) {
          thicknesses[0] = twoLayerSeed.h;
        }
      }
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

  List<double> _logSpace(double start, double stop, int count) {
    final length = math.max(count, 1);
    if (!start.isFinite || start <= 0) {
      return List<double>.filled(length, 0.5);
    }
    if (!stop.isFinite || stop <= start) {
      return List<double>.filled(length, start);
    }
    if (length == 1) {
      return [start];
    }
    final lower = math.log(start);
    final upper = math.log(stop);
    if (!lower.isFinite || !upper.isFinite || (upper - lower).abs() < 1e-6) {
      return List<double>.filled(length, start);
    }
    final step = (upper - lower) / (length - 1);
    return List<double>.generate(
      length,
      (index) => math.exp(lower + step * index),
    );
  }

  _TwoLayerSeed? _gridSearchTwoLayerSeed(
    List<MapEntry<double, double>> samples,
    double rho1Seed,
    double rho2Seed,
  ) {
    if (samples.length < 2) {
      return null;
    }
    final spacings = samples.map((entry) => entry.key).toList();
    final observations = samples.map((entry) => entry.value).toList();

    var lower = math.max(0.3, spacings.first * 0.5);
    if (!lower.isFinite || lower <= 0) {
      lower = 0.3;
    }
    var upper = spacings.last / 3;
    if (!upper.isFinite || upper <= lower) {
      upper = lower * 1.25;
    }
    final candidates = _logSpace(lower, upper, 7);
    if (candidates.isEmpty) {
      return null;
    }

    _TwoLayerSeed? best;
    double? bestRms;
    final safeRho1 = math.max(rho1Seed, 1e-3);
    final safeRho2 = math.max(rho2Seed, 1e-3);
    final logRhos = [math.log(safeRho1), math.log(safeRho2)];

    for (final h in candidates) {
      if (!h.isFinite || h <= 0) {
        continue;
      }
      final predicted = _forward(spacings, <double?>[h, null], logRhos);
      final residuals = List<double>.generate(
        predicted.length,
        (i) => observations[i] - predicted[i],
      );
      final rms = _rms(residuals);
      if (!rms.isFinite) {
        continue;
      }
      if (bestRms == null || rms < bestRms) {
        bestRms = rms;
        best = _TwoLayerSeed(rho1: safeRho1, rho2: safeRho2, h: h);
      }
    }

    return best;
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

class _TwoLayerSeed {
  const _TwoLayerSeed({required this.rho1, required this.rho2, required this.h});

  final double rho1;
  final double rho2;
  final double h;
}
