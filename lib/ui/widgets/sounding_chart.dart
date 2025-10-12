import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/inversion_model.dart';
import '../../models/spacing_point.dart';
import '../../services/qc_rules.dart';
import '../../utils/distance_unit.dart';
import 'point_details_sheet.dart';

class SoundingChart extends StatelessWidget {
  const SoundingChart({
    super.key,
    required this.points,
    required this.inversion,
    required this.distanceUnit,
  });

  final List<SpacingPoint> points;
  final InversionModel inversion;
  final DistanceUnit distanceUnit;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('No data'));
    }

    final predicted = inversion.predictedRho;
    final sigma = inversion.oneSigmaBand;

    final spots = <FlSpot>[];
    final colors = <Color>[];
    final predictedSpots = <FlSpot>[];
    final upperSpots = <FlSpot>[];
    final errorBars = <LineChartBarData>[];

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = _log10(p.spacingMetric);
      final y = _log10(p.rhoAppOhmM);
      spots.add(FlSpot(x, y));
      double? residual;
      if (i < predicted.length) {
        final fit = predicted[i];
        residual = fit == 0 ? 0 : (p.rhoAppOhmM - fit) / fit;
        predictedSpots.add(FlSpot(x, _log10(fit)));
        if (i < sigma.length) {
          final frac = sigma[i];
          final upper = fit * (1 + frac.abs());
          upperSpots.add(FlSpot(x, _log10(upper)));
        }
      }
      if (p.sigmaRhoOhmM != null && p.sigmaRhoOhmM! > 0) {
        final rho = p.rhoAppOhmM;
        final upper = math.max(rho + p.sigmaRhoOhmM!, 1e-6);
        final lower = math.max(rho - p.sigmaRhoOhmM!, 1e-6);
        errorBars.add(
          LineChartBarData(
            spots: [
              FlSpot(x, _log10(lower)),
              FlSpot(x, _log10(upper)),
            ],
            isCurved: false,
            color: Colors.grey,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        );
      }
      final level = classifyPoint(
        residual: residual ?? 0,
        coefficientOfVariation: p.sigmaRhoOhmM == null || p.rhoAppOhmM == 0
            ? null
            : (p.sigmaRhoOhmM! / p.rhoAppOhmM),
        point: p,
      );
      colors.add(_qaColor(level));
    }

    final lineBars = <LineChartBarData>[];
    if (upperSpots.isNotEmpty) {
      lineBars.add(
        LineChartBarData(
          spots: upperSpots,
          isCurved: true,
          color: Colors.blue.withValues(alpha: 0.2),
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.blue.withValues(alpha: 0.1),
          ),
        ),
      );
    }
    if (predictedSpots.isNotEmpty) {
      lineBars.add(
        LineChartBarData(
          spots: predictedSpots,
          isCurved: true,
          color: Colors.blue,
          dotData: const FlDotData(show: false),
        ),
      );
    }
    lineBars.addAll(errorBars);
    final pointsBarIndex = lineBars.length;
    lineBars.add(
      LineChartBarData(
        spots: spots,
        isCurved: false,
        barWidth: 0,
        showingIndicators: List.generate(spots.length, (index) => index),
        dotData: FlDotData(
          show: true,
          checkToShowDot: (spot, data) => true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            color: colors[index],
            radius: 4,
            strokeWidth: 1.5,
            strokeColor: Colors.black,
          ),
        ),
      ),
    );

    final spacingMeters = points.map((e) => e.spacingMeters).toList();
    final rhoValues = points.map((e) => e.rhoAppOhmM).toList();
    final minXValue = spacingMeters.map(_log10).reduce(math.min);
    final maxXValue = spacingMeters.map(_log10).reduce(math.max);
    final minYValue = rhoValues.map(_log10).reduce(math.min);
    final maxYValue = rhoValues.map(_log10).reduce(math.max);
    final spacingTickLogs = _buildLogTicks(spacingMeters, minXValue, maxXValue);
    final rhoTickLogs = _buildLogTicks(rhoValues, minYValue, maxYValue);

    final theme = Theme.of(context);
    final gridColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LineChart(
        LineChartData(
          clipData: const FlClipData.all(),
          minX: minXValue - 0.1,
          maxX: maxXValue + 0.1,
          minY: minYValue - 0.2,
          maxY: maxYValue + 0.2,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Text('ρₐ (Ω·m)'),
              ),
              axisNameSize: 32,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 62,
                getTitlesWidget: (value, meta) {
                  if (!_isNearTick(rhoTickLogs, value)) {
                    return const SizedBox.shrink();
                  }
                  final rho = math.pow(10, value).toDouble();
                  final label = _formatRhoLabel(rho);
                  return Text(label, style: const TextStyle(fontSize: 11));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(distanceUnit.axisLabel),
              ),
              axisNameSize: 36,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (value, meta) {
                  if (!_isNearTick(spacingTickLogs, value)) {
                    return const SizedBox.shrink();
                  }
                  final spacing = math.pow(10, value).toDouble();
                  final label = distanceUnit.formatSpacing(spacing);
                  return Text(label, style: const TextStyle(fontSize: 11));
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: lineBars,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
            checkToShowVerticalLine: (value) =>
                _isNearTick(spacingTickLogs, value),
            checkToShowHorizontalLine: (value) =>
                _isNearTick(rhoTickLogs, value),
            getDrawingVerticalLine: (_) =>
                FlLine(color: gridColor, strokeWidth: 0.5),
            getDrawingHorizontalLine: (_) =>
                FlLine(color: gridColor, strokeWidth: 0.5),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                const textStyle = TextStyle(color: Colors.white, fontSize: 11);
                final unitSuffix =
                    distanceUnit == DistanceUnit.feet ? 'ft' : 'm';
                return List<LineTooltipItem>.generate(touchedSpots.length,
                    (index) {
                  final spot = touchedSpots[index];
                  final spacingMetersValue = math.pow(10, spot.x).toDouble();
                  final rhoValueLinear = math.pow(10, spot.y).toDouble();
                  if (spot.barIndex == pointsBarIndex) {
                    final point = points[spot.spotIndex];
                    final spacingFt = point.aFeet.toStringAsFixed(2);
                    final spacingM = point.aMeters.toStringAsFixed(2);
                    final rhoValue = point.rhoAppOhmM.toStringAsFixed(2);
                    return LineTooltipItem(
                      'Obs • a: $spacingFt ft ($spacingM m)\nρₐ: $rhoValue Ω·m',
                      textStyle,
                    );
                  }

                  final spacingLabel =
                      distanceUnit.formatSpacing(spacingMetersValue);
                  final labelPrefix =
                      spot.barIndex < pointsBarIndex ? 'Model' : 'Band';
                  final rhoLabel = _formatRhoLabel(rhoValueLinear);
                  return LineTooltipItem(
                    '$labelPrefix • a: $spacingLabel $unitSuffix\nρₐ: $rhoLabel Ω·m',
                    textStyle,
                  );
                });
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.lineBarSpots != null) {
                final spotsData = response!.lineBarSpots!;
                for (final barSpot in spotsData) {
                  if (barSpot.barIndex == pointsBarIndex) {
                    final index = barSpot.spotIndex;
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => PointDetailsSheet(point: points[index]),
                    );
                    break;
                  }
                }
              }
            },
          ),
        ),
      ),
    );
  }

  double _log10(double value) => math.log(value) / math.ln10;

  List<double> _buildLogTicks(
    List<double> samples,
    double minLog,
    double maxLog, {
    int maxCount = 8,
  }) {
    final minValue = math.pow(10, minLog).toDouble();
    final maxValue = math.pow(10, maxLog).toDouble();
    final values = <double>{};
    for (final sample in samples) {
      if (!sample.isFinite || sample <= 0) {
        continue;
      }
      if (sample >= minValue * 0.95 && sample <= maxValue * 1.05) {
        values.add(sample);
      }
    }
    values.addAll(_generateNiceTicks(minValue, maxValue));
    if (values.isEmpty) {
      values.addAll([minValue, maxValue]);
    }
    final sorted = values.toList()..sort();
    final limited = _limitTicks(sorted, maxCount: maxCount);
    return limited.map((value) => math.log(value) / math.ln10).toList();
  }

  Iterable<double> _generateNiceTicks(double minValue, double maxValue) sync* {
    if (!minValue.isFinite || !maxValue.isFinite || minValue <= 0) {
      return;
    }
    final minExponent = math.max(-6, (math.log(minValue) / math.ln10).floor());
    final maxExponent =
        math.max(minExponent, (math.log(maxValue) / math.ln10).ceil());
    const multipliers = [1.0, 2.0, 5.0];
    for (var exp = minExponent - 1; exp <= maxExponent + 1; exp++) {
      final base = math.pow(10.0, exp).toDouble();
      for (final multiplier in multipliers) {
        final candidate = base * multiplier;
        if (candidate >= minValue * 0.95 && candidate <= maxValue * 1.05) {
          yield candidate;
        }
      }
    }
  }

  List<double> _limitTicks(List<double> values, {required int maxCount}) {
    if (values.length <= maxCount) {
      return values;
    }
    final result = <double>[];
    final step = (values.length - 1) / (maxCount - 1);
    for (var i = 0; i < maxCount; i++) {
      final index = (i * step).round().clamp(0, values.length - 1);
      final value = values[index];
      if (result.isEmpty || (value - result.last).abs() > 1e-6) {
        result.add(value);
      }
    }
    return result;
  }

  bool _isNearTick(List<double> ticks, double value,
      {double tolerance = 0.04}) {
    for (final tick in ticks) {
      if ((tick - value).abs() <= tolerance) {
        return true;
      }
    }
    return false;
  }

  String _formatRhoLabel(double value) {
    if (!value.isFinite) {
      return value.toString();
    }
    final absValue = value.abs();
    if (absValue >= 1000) {
      return value.round().toString();
    }
    if (absValue >= 100) {
      return value.round().toString();
    }
    if (absValue >= 10) {
      return _trimTrailingZeros(value.toStringAsFixed(0));
    }
    if (absValue >= 1) {
      return _trimTrailingZeros(value.toStringAsFixed(1));
    }
    if (absValue >= 0.1) {
      return _trimTrailingZeros(value.toStringAsFixed(2));
    }
    return _trimTrailingZeros(value.toStringAsFixed(3));
  }

  String _trimTrailingZeros(String value) {
    if (!value.contains('.')) {
      return value;
    }
    return value.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Color _qaColor(QaLevel level) {
    switch (level) {
      case QaLevel.green:
        return Colors.green;
      case QaLevel.yellow:
        return Colors.orange;
      case QaLevel.red:
        return Colors.red;
    }
  }
}
