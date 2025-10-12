import 'dart:collection';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/logging.dart';
import '../../models/calc.dart';
import '../../models/project.dart';
import '../../models/site.dart';
import '../../services/templates_service.dart';
import '../../services/inversion.dart';
import '../../utils/distance_unit.dart';

class GhostSeriesPoint {
  const GhostSeriesPoint({required this.spacingFt, required this.rho});

  final double spacingFt;
  final double rho;
}

const _okabeBlue = Color(0xFF0072B2);
const _okabeVermillion = Color(0xFFD55E00);
const _averageGray = Color(0xFF595959);
const _okabeOrange = Color(0xFFE69F00);

class PlotsPanel extends StatelessWidget {
  const PlotsPanel({
    super.key,
    required this.project,
    required this.selectedSite,
    required this.showOutliers,
    required this.lockAxes,
    required this.showAllSites,
    this.template,
    this.averageGhost = const [],
  });

  final ProjectRecord project;
  final SiteRecord selectedSite;
  final bool showOutliers;
  final bool lockAxes;
  final bool showAllSites;
  final GhostTemplate? template;
  final List<GhostSeriesPoint> averageGhost;

  @override
  Widget build(BuildContext context) {
    if (showAllSites) {
      return _buildAllSitesComposite(context);
    }
    return _buildPrimaryChart(context, selectedSite);
  }

  Widget _buildAllSitesComposite(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final site in project.sites)
              SizedBox(
                width: 320,
                height: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: _buildChartForSite(context, site, compact: true),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrimaryChart(BuildContext context, SiteRecord site) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: _buildChartForSite(context, site, compact: false),
    );
  }

  Widget _buildChartForSite(BuildContext context, SiteRecord site,
      {required bool compact}) {
    final theme = Theme.of(context);
    final data = buildSeriesForSite(site, showOutliers: showOutliers);
    if (data.aSeries.isEmpty && data.bSeries.isEmpty) {
      return Center(
        child: Text(
          'No readings yet for ${site.displayName}.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final axis = _computeAxisRanges(site);
    LOG.info('plot_render', extra: {
      'site': site.siteId,
      'spacing_count': site.spacings.length,
      'lock_axes': lockAxes,
      'show_outliers': showOutliers,
      'series_a': data.aSeries.length,
      'series_b': data.bSeries.length,
      'has_template': template != null,
    });
    final spacingSamples = List<double>.of(
      lockAxes
          ? project.sites.expand((s) => s.spacings.map((p) => p.spacingFeet))
          : site.spacings.map((p) => p.spacingFeet),
    );
    final rhoSamples = List<double>.of(
      lockAxes ? project.sites.expand(_collectRho) : _collectRho(site),
    );
    final spacingTickLogs =
        _buildSpacingTicks(spacingSamples, axis.minX, axis.maxX);
    final rhoTickLogs =
        _buildResistivityTicks(rhoSamples, axis.minY, axis.maxY);
    final sortedGhost = List<GhostSeriesPoint>.of(averageGhost)
      ..sort((a, b) => a.spacingFt.compareTo(b.spacingFt));
    final ghostSpots = sortedGhost
        .map((point) => FlSpot(_log(point.spacingFt), _log(point.rho)))
        .toList();
    final sortedTemplate = template == null
        ? const <GhostTemplatePoint>[]
        : (List<GhostTemplatePoint>.of(template!.points)
          ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet)));
    final templateSpots = sortedTemplate
        .map((point) => FlSpot(
              _log(point.spacingFeet),
              _log(point.apparentResistivityOhmM),
            ))
        .toList();
    final chart = LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: theme.colorScheme.surface.withValues(
              alpha: (0.9 * 255).round().toDouble(),
            ),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final spacing = math.pow(10, spot.x).toDouble();
                final rho = math.pow(10, spot.y).toDouble();
                return LineTooltipItem(
                  'a=${spacing.toStringAsFixed(1)} ft\nρa=${rho.toStringAsFixed(1)} Ω·m',
                  theme.textTheme.bodyMedium!,
                );
              }).toList();
            },
          ),
        ),
        minX: axis.minX,
        maxX: axis.maxX,
        minY: axis.minY,
        maxY: axis.maxY,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) {
                if (!_isNearTick(spacingTickLogs, value)) {
                  return const SizedBox.shrink();
                }
                final spacing = math.pow(10, value).toDouble();
                final label = _formatSpacingLabel(spacing);
                return Text('$label ft', style: theme.textTheme.labelSmall);
              },
            ),
            axisNameWidget: const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('Spacing a (ft)'),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                if (!_isNearTick(rhoTickLogs, value)) {
                  return const SizedBox.shrink();
                }
                final rho = math.pow(10, value).toDouble();
                return Text(
                  _formatResistivityLabel(rho),
                  style: theme.textTheme.labelSmall,
                );
              },
            ),
            axisNameWidget: const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Text('ρa (Ω·m)'),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          checkToShowVerticalLine: (value) =>
              _isNearTick(spacingTickLogs, value),
          checkToShowHorizontalLine: (value) => _isNearTick(rhoTickLogs, value),
          getDrawingVerticalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            strokeWidth: 0.8,
          ),
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            strokeWidth: 0.8,
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          if (data.aSeries.isNotEmpty)
            LineChartBarData(
              spots: data.aSeries,
              barWidth: 3,
              color: _okabeBlue,
              isCurved: false,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: _okabeBlue,
                    strokeWidth: 1.5,
                    strokeColor: theme.colorScheme.surface,
                  );
                },
              ),
            ),
          if (data.bSeries.isNotEmpty)
            LineChartBarData(
              spots: data.bSeries,
              barWidth: 3,
              color: _okabeVermillion,
              isCurved: false,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotSquarePainter(
                    size: 6,
                    color: _okabeVermillion,
                    strokeWidth: 1.5,
                    strokeColor: theme.colorScheme.surface,
                  );
                },
              ),
            ),
          if (ghostSpots.isNotEmpty)
            LineChartBarData(
              spots: ghostSpots,
              barWidth: 2,
              color: _averageGray,
              dashArray: [6, 6],
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return const _TriangleDotPainter(
                    color: _averageGray,
                    size: 4,
                  );
                },
              ),
            ),
          if (templateSpots.isNotEmpty)
            LineChartBarData(
              spots: templateSpots,
              barWidth: 2,
              color: Theme.of(context).colorScheme.outline,
              dashArray: [4, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: compact ? Duration.zero : const Duration(milliseconds: 300),
    );
    final legend = <Widget>[];
    if (data.aSeries.isNotEmpty) {
      legend.add(
        const _LegendEntry(
          label: 'N–S',
          color: _okabeBlue,
          marker: _LegendMarker.circle,
        ),
      );
    }
    if (data.bSeries.isNotEmpty) {
      legend.add(
        const _LegendEntry(
          label: 'W–E',
          color: _okabeVermillion,
          marker: _LegendMarker.square,
        ),
      );
    }
    if (ghostSpots.isNotEmpty) {
      legend.add(
        const _LegendEntry(
          label: 'Average',
          color: _averageGray,
          dashed: true,
          marker: _LegendMarker.triangle,
        ),
      );
    }
    if (legend.isEmpty) {
      return chart;
    }
    return Stack(
      children: [
        chart,
        Positioned(
          top: 8,
          left: 8,
          child: Card(
            elevation: 1,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: legend,
              ),
            ),
          ),
        ),
      ],
    );
  }

  _AxisRanges _computeAxisRanges(SiteRecord site) {
    final spacings = lockAxes
        ? project.sites.expand((s) => s.spacings.map((p) => p.spacingFeet))
        : site.spacings.map((p) => p.spacingFeet);
    final rhoValues = lockAxes
        ? project.sites.expand((s) => _collectRho(s))
        : _collectRho(site);
    final minSpacing = spacings.isEmpty ? 1.0 : spacings.reduce(math.min);
    final maxSpacing = spacings.isEmpty ? 10.0 : spacings.reduce(math.max);
    final minRho = rhoValues.isEmpty ? 10.0 : rhoValues.reduce(math.min);
    final maxRho = rhoValues.isEmpty ? 1000.0 : rhoValues.reduce(math.max);
    return _AxisRanges(
      minX: _log(minSpacing) - 0.1,
      maxX: _log(maxSpacing) + 0.1,
      minY: _log(minRho) - 0.2,
      maxY: _log(maxRho) + 0.2,
    );
  }

  Iterable<double> _collectRho(SiteRecord site) sync* {
    for (final spacing in site.spacings) {
      for (final orientation in [spacing.orientationA, spacing.orientationB]) {
        final latest = orientation.latest;
        if (latest == null || latest.resistanceOhm == null) {
          continue;
        }
        final hideSample = !showOutliers && (latest.isBad);
        if (hideSample) {
          continue;
        }
        yield rhoAWenner(spacing.spacingFeet, latest.resistanceOhm!);
      }
    }
  }

  double _log(double value) => math.log(value) / math.ln10;
}

List<double> _buildSpacingTicks(
  List<double> spacings,
  double minLog,
  double maxLog, {
  int maxCount = 8,
}) {
  final minSpacing = math.pow(10, minLog).toDouble();
  final maxSpacing = math.pow(10, maxLog).toDouble();
  final tickSet = SplayTreeSet<double>();
  for (final spacing in spacings) {
    if (!spacing.isFinite || spacing <= 0) {
      continue;
    }
    if (spacing >= minSpacing * 0.95 && spacing <= maxSpacing * 1.05) {
      tickSet.add(spacing);
    }
  }
  tickSet.addAll(_generateNiceTicks(minSpacing, maxSpacing));
  if (tickSet.isEmpty) {
    tickSet.addAll([minSpacing, maxSpacing]);
  }
  final limited = _limitTicks(tickSet.toList(), maxCount: maxCount);
  return limited.map((value) => math.log(value) / math.ln10).toList();
}

List<double> _buildResistivityTicks(
  List<double> rhoValues,
  double minLog,
  double maxLog, {
  int maxCount = 8,
}) {
  final minValue = math.pow(10, minLog).toDouble();
  final maxValue = math.pow(10, maxLog).toDouble();
  final tickSet = SplayTreeSet<double>();
  for (final rho in rhoValues) {
    if (!rho.isFinite || rho <= 0) {
      continue;
    }
    if (rho >= minValue * 0.9 && rho <= maxValue * 1.1) {
      tickSet.add(rho);
    }
  }
  tickSet.addAll(_generateNiceTicks(minValue, maxValue));
  if (tickSet.isEmpty) {
    tickSet.addAll([minValue, maxValue]);
  }
  final limited = _limitTicks(tickSet.toList(), maxCount: maxCount);
  return limited.map((value) => math.log(value) / math.ln10).toList();
}

List<double> _limitTicks(List<double> ticks, {required int maxCount}) {
  if (ticks.length <= maxCount) {
    return ticks;
  }
  final result = <double>[];
  final step = (ticks.length - 1) / (maxCount - 1);
  for (var i = 0; i < maxCount; i++) {
    final index = (i * step).round().clamp(0, ticks.length - 1);
    final value = ticks[index];
    if (result.isEmpty || (value - result.last).abs() > 1e-6) {
      result.add(value);
    }
  }
  return result;
}

Iterable<double> _generateNiceTicks(double minValue, double maxValue) sync* {
  if (!minValue.isFinite || !maxValue.isFinite || minValue <= 0) {
    return;
  }
  final minExponent = minValue <= 0
      ? 0
      : math.max((-6), (math.log(minValue) / math.ln10).floor());
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

bool _isNearTick(List<double> ticks, double value, {double tolerance = 0.04}) {
  for (final tick in ticks) {
    if ((value - tick).abs() <= tolerance) {
      return true;
    }
  }
  return false;
}

String _formatSpacingLabel(double spacing) {
  if (spacing >= 1000) {
    return spacing.toStringAsFixed(0);
  }
  if (spacing >= 100) {
    return spacing.toStringAsFixed(0);
  }
  if (spacing >= 10) {
    final rounded = (spacing / 5).round() * 5;
    if ((rounded - spacing).abs() <= 0.1) {
      return rounded.toStringAsFixed(0);
    }
    return spacing.toStringAsFixed(1);
  }
  if (spacing >= 1) {
    return spacing.toStringAsFixed(1);
  }
  return spacing.toStringAsFixed(2);
}

String _formatResistivityLabel(double value) {
  if (value >= 1000) {
    return value.round().toString();
  }
  if (value >= 100) {
    return value.round().toString();
  }
  if (value >= 10) {
    return value.toStringAsFixed(0);
  }
  if (value >= 1) {
    return value.toStringAsFixed(1);
  }
  return value.toStringAsFixed(2);
}

class SeriesData {
  SeriesData({required this.aSeries, required this.bSeries});

  final List<FlSpot> aSeries;
  final List<FlSpot> bSeries;
}

SeriesData buildSeriesForSite(SiteRecord site, {required bool showOutliers}) {
  final aSpots = <FlSpot>[];
  final bSpots = <FlSpot>[];
  for (final spacing in site.spacings) {
    final aSample = spacing.orientationA.latest;
    final bSample = spacing.orientationB.latest;
    if (aSample != null && aSample.resistanceOhm != null) {
      final hideSample = !showOutliers && aSample.isBad;
      if (!hideSample) {
        aSpots.add(
          FlSpot(
            math.log(spacing.spacingFeet) / math.ln10,
            math.log(rhoAWenner(spacing.spacingFeet, aSample.resistanceOhm!)) /
                math.ln10,
          ),
        );
      }
    }
    if (bSample != null && bSample.resistanceOhm != null) {
      final hideSample = !showOutliers && bSample.isBad;
      if (!hideSample) {
        bSpots.add(
          FlSpot(
            math.log(spacing.spacingFeet) / math.ln10,
            math.log(rhoAWenner(spacing.spacingFeet, bSample.resistanceOhm!)) /
                math.ln10,
          ),
        );
      }
    }
  }
  aSpots.sort((a, b) => a.x.compareTo(b.x));
  bSpots.sort((a, b) => a.x.compareTo(b.x));
  return SeriesData(aSeries: aSpots, bSeries: bSpots);
}

class _AxisRanges {
  _AxisRanges(
      {required this.minX,
      required this.maxX,
      required this.minY,
      required this.maxY});

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

enum _LegendMarker { none, circle, square, triangle }

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.label,
    required this.color,
    this.dashed = false,
    this.marker = _LegendMarker.none,
  });

  final String label;
  final Color color;
  final bool dashed;
  final _LegendMarker marker;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 10,
          child: CustomPaint(
            painter: _LegendLinePainter(
                color: color, dashed: dashed, marker: marker),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  _LegendLinePainter({
    required this.color,
    required this.dashed,
    required this.marker,
  });

  final Color color;
  final bool dashed;
  final _LegendMarker marker;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      const dashWidth = 4.0;
      const dashGap = 3.0;
      var start = 0.0;
      while (start < size.width) {
        final end = math.min(start + dashWidth, size.width);
        canvas.drawLine(Offset(start, y), Offset(end, y), paint);
        start += dashWidth + dashGap;
      }
    }
    final center = Offset(size.width / 2, y);
    switch (marker) {
      case _LegendMarker.circle:
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        final stroke = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawCircle(center, 3, fill);
        canvas.drawCircle(center, 3, stroke);
        break;
      case _LegendMarker.square:
        final rect = Rect.fromCenter(center: center, width: 6, height: 6);
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        final stroke = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, stroke);
        break;
      case _LegendMarker.triangle:
        const half = 4.0;
        final path = Path()
          ..moveTo(center.dx, center.dy - half)
          ..lineTo(center.dx + half, center.dy + half)
          ..lineTo(center.dx - half, center.dy + half)
          ..close();
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        final stroke = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
        break;
      case _LegendMarker.none:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.dashed != dashed ||
        oldDelegate.marker != marker;
  }
}

class _TriangleDotPainter extends FlDotPainter {
  const _TriangleDotPainter({
    required this.color,
    this.size = 4.0,
  });

  final Color color;
  final double size;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final path = Path()
      ..moveTo(offsetInCanvas.dx, offsetInCanvas.dy - size)
      ..lineTo(offsetInCanvas.dx - size, offsetInCanvas.dy + size)
      ..lineTo(offsetInCanvas.dx + size, offsetInCanvas.dy + size)
      ..close();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  Size getSize(FlSpot spot) {
    final extent = size * 2;
    return Size(extent, extent);
  }

  @override
  bool hitTest(
    FlSpot spot,
    Offset touchedPoint,
    Offset centerOffset,
    double dotSize,
  ) {
    final radius = math.max(size, dotSize / 2) + 1.0;
    return (touchedPoint - centerOffset).distance <= radius;
  }

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) {
    return this;
  }

  @override
  Color get mainColor => color;

  @override
  List<Object?> get props => <Object?>[color, size];
}

class InversionPlotPanel extends StatelessWidget {
  const InversionPlotPanel({
    super.key,
    required this.result,
    required this.isLoading,
    required this.distanceUnit,
    this.siteLabel,
  });

  final TwoLayerInversionResult? result;
  final bool isLoading;
  final DistanceUnit distanceUnit;
  final String? siteLabel;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: SizedBox(
          height: 240,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  'Solving two-layer inversion…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }
    final summary = result;
    if (summary == null) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text(
              'Record at least two valid spacings to compute inversion.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final minRho = math.max(summary.minRho * 0.8, 0.5);
    final maxRho = summary.maxRho * 1.2;
    final minLog = _log10(minRho);
    final maxLog = _log10(maxRho);
    final depthMeters = math.max(summary.maxDepthMeters * 1.1, 0.5);
    final depthTicks = _buildDepthTicks(depthMeters);
    final resistivityTicks = _buildResistivityTicks(minLog, maxLog);

    final measurementSpots = <FlSpot>[];
    final predictedSpots = <FlSpot>[];
    for (var i = 0; i < summary.observedRho.length; i++) {
      final double observed = summary.observedRho[i].toDouble();
      if (!observed.isFinite || observed <= 0) {
        continue;
      }
      final double depth = i < summary.measurementDepthsM.length
          ? summary.measurementDepthsM[i].toDouble()
          : (summary.measurementDepthsM.isEmpty
              ? 0.0
              : summary.measurementDepthsM.last.toDouble());
      measurementSpots.add(FlSpot(_log10(observed), -depth));
      final double predicted = i < summary.predictedRho.length
          ? summary.predictedRho[i].toDouble()
          : (summary.predictedRho.isEmpty
              ? observed
              : summary.predictedRho.last.toDouble());
      if (predicted.isFinite && predicted > 0) {
        predictedSpots.add(FlSpot(_log10(predicted), -depth));
      }
    }

    final profileSpots = _buildProfile(summary, depthMeters);

    final lineBars = <LineChartBarData>[
      LineChartBarData(
        spots: profileSpots,
        isCurved: false,
        barWidth: 3,
        color: _okabeOrange,
        isStepLineChart: true,
        dotData: const FlDotData(show: false),
      ),
      if (predictedSpots.isNotEmpty)
        LineChartBarData(
          spots: predictedSpots,
          isCurved: false,
          barWidth: 2,
          color: _okabeBlue,
          dashArray: const [6, 4],
          dotData: const FlDotData(show: false),
        ),
      if (measurementSpots.isNotEmpty)
        LineChartBarData(
          spots: measurementSpots,
          isCurved: false,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              color: _averageGray,
              radius: 4,
              strokeWidth: 1.5,
              strokeColor: theme.colorScheme.surface,
            ),
          ),
        ),
    ];

    final chart = SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minX: minLog - 0.1,
          maxX: maxLog + 0.1,
          minY: -depthMeters,
          maxY: 0,
          clipData: const FlClipData.all(),
          lineBarsData: lineBars,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
            horizontalInterval: depthTicks.isEmpty
                ? null
                : depthTicks.length == 1
                    ? depthTicks.first
                    : depthTicks[1] - depthTicks[0],
            verticalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 0.8,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 0.8,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget: const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('Resistivity (Ω·m)'),
              ),
              axisNameSize: 32,
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  if (!resistivityTicks.contains(value.round())) {
                    return const SizedBox.shrink();
                  }
                  final label = _formatResistivityTick(value);
                  return Text(label, style: theme.textTheme.labelSmall);
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text('Depth (${_unitLabel(distanceUnit)})'),
              ),
              axisNameSize: 32,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                getTitlesWidget: (value, meta) {
                  final depth = -value;
                  if (depth < 0) {
                    return const SizedBox.shrink();
                  }
                  final closest = _closestTick(depthTicks, depth);
                  if ((depth - closest).abs() > depthMeters * 0.04) {
                    return const SizedBox.shrink();
                  }
                  final text = distanceUnit.formatSpacing(depth);
                  return Text(text, style: theme.textTheme.labelSmall);
                },
              ),
            ),
          ),
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );

    final header = siteLabel == null
        ? const Text('Two-layer inversion summary')
        : Text('Two-layer inversion — $siteLabel');

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 12),
            chart,
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _SummaryChip(
                  label: 'Upper layer ρ',
                  value: _formatRho(summary.rho1),
                  color: _okabeBlue,
                ),
                _SummaryChip(
                  label: 'Lower layer ρ',
                  value: _formatRho(summary.rho2),
                  color: _okabeOrange,
                ),
                if (summary.halfSpaceRho != null)
                  _SummaryChip(
                    label: 'Half-space ρ',
                    value: _formatRho(summary.halfSpaceRho!),
                    color: _okabeVermillion,
                  ),
                if (summary.thicknessM != null)
                  _SummaryChip(
                    label: 'Layer thickness',
                    value:
                        '${distanceUnit.formatSpacing(summary.thicknessM!)} ${_unitLabel(distanceUnit)}',
                    color: theme.colorScheme.primary,
                  ),
                _SummaryChip(
                  label: 'RMS misfit',
                  value: '${(summary.rms * 100).toStringAsFixed(1)}%',
                  color: theme.colorScheme.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static double _closestTick(List<double> ticks, double value) {
    if (ticks.isEmpty) {
      return value;
    }
    return ticks
        .reduce((a, b) => (a - value).abs() < (b - value).abs() ? a : b);
  }

  static List<double> _buildDepthTicks(double maxDepth) {
    if (maxDepth <= 0) {
      return const [];
    }
    const tickCount = 4;
    final step = maxDepth / tickCount;
    return List<double>.generate(tickCount + 1, (index) => index * step);
  }

  static List<int> _buildResistivityTicks(double minLog, double maxLog) {
    final start = minLog.floor();
    final end = maxLog.ceil();
    return [for (var i = start; i <= end; i++) i];
  }

  static List<FlSpot> _buildProfile(
      TwoLayerInversionResult summary, double depthMeters) {
    final spots = <FlSpot>[];
    final topLog = _log10(summary.rho1);
    spots.add(FlSpot(topLog, 0));
    final firstBoundary = summary.thicknessM ??
        (summary.layerDepths.isNotEmpty
            ? summary.layerDepths.first
            : summary.maxDepthMeters / 2);
    final cappedBoundary = math.min(firstBoundary, depthMeters);
    spots.add(FlSpot(topLog, -cappedBoundary));
    final secondLog = _log10(summary.rho2);
    spots.add(FlSpot(secondLog, -cappedBoundary));
    spots.add(FlSpot(secondLog, -depthMeters));
    return spots;
  }

  static double _log10(double value) => math.log(value) / math.ln10;

  static String _formatResistivityTick(double logValue) {
    final value = math.pow(10, logValue).toDouble();
    String label;
    if (value >= 1000) {
      label = value.toStringAsFixed(0);
    } else if (value >= 100) {
      label = value.toStringAsFixed(0);
    } else if (value >= 10) {
      label = value.toStringAsFixed(1);
    } else {
      label = value.toStringAsFixed(2);
    }
    return _trimTrailingZeros(label);
  }

  static String _formatRho(double rho) {
    if (rho >= 1000) {
      return '${rho.toStringAsFixed(0)} Ω·m';
    }
    if (rho >= 100) {
      return '${rho.toStringAsFixed(1)} Ω·m';
    }
    return '${rho.toStringAsFixed(2)} Ω·m';
  }

  static String _unitLabel(DistanceUnit unit) =>
      unit == DistanceUnit.feet ? 'ft' : 'm';

  static String _trimTrailingZeros(String value) {
    if (!value.contains('.')) {
      return value;
    }
    return value.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.labelMedium,
          children: [
            TextSpan(
                text: '$label ',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
