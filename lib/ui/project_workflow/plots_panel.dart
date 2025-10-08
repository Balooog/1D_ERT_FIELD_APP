import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/calc.dart';
import '../../models/project.dart';
import '../../models/site.dart';
import '../../services/templates_service.dart';

class GhostSeriesPoint {
  const GhostSeriesPoint({required this.spacingFt, required this.rho});

  final double spacingFt;
  final double rho;
}

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
    final averageColor = theme.colorScheme.outline;
    final chart = LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: theme.colorScheme.surface.withValues(
                  alpha: (0.9 * 255).round().toDouble(),
                ),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final spacing = math.pow(10, spot.x);
                final rho = math.pow(10, spot.y);
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
              interval: (axis.maxX - axis.minX) / 4,
              getTitlesWidget: (value, meta) {
                final spacing = math.pow(10, value);
                return Text('${spacing.toStringAsFixed(1)} ft');
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
              interval: (axis.maxY - axis.minY) / 4,
              getTitlesWidget: (value, meta) {
                final rho = math.pow(10, value);
                return Text('${rho.toStringAsFixed(0)}');
              },
            ),
            axisNameWidget: const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Text('ρa (Ω·m)'),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: true, drawHorizontalLine: true),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          if (data.aSeries.isNotEmpty)
            LineChartBarData(
              spots: data.aSeries,
              barWidth: 3,
              color: theme.colorScheme.primary,
              isCurved: false,
              dotData: const FlDotData(show: true),
            ),
          if (data.bSeries.isNotEmpty)
            LineChartBarData(
              spots: data.bSeries,
              barWidth: 3,
              color: theme.colorScheme.secondary,
              isCurved: false,
              dotData: const FlDotData(show: true),
            ),
          if (ghostSpots.isNotEmpty)
            LineChartBarData(
              spots: ghostSpots,
              barWidth: 2,
              color: averageColor,
              dashArray: [6, 6],
              dotData: const FlDotData(show: false),
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
      legend.add(_LegendEntry(label: 'N–S', color: theme.colorScheme.primary));
    }
    if (data.bSeries.isNotEmpty) {
      legend.add(_LegendEntry(label: 'W–E', color: theme.colorScheme.secondary));
    }
    if (ghostSpots.isNotEmpty) {
      legend.add(_LegendEntry(label: 'Average', color: averageColor, dashed: true));
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
  _AxisRanges({required this.minX, required this.maxX, required this.minY, required this.maxY});

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.label,
    required this.color,
    this.dashed = false,
  });

  final String label;
  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 10,
          child: CustomPaint(
            painter: _LegendLinePainter(color: color, dashed: dashed),
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
  _LegendLinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

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
      return;
    }
    const dashWidth = 4.0;
    const dashGap = 3.0;
    var start = 0.0;
    while (start < size.width) {
      final end = math.min(start + dashWidth, size.width);
      canvas.drawLine(Offset(start, y), Offset(end, y), paint);
      start += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dashed != dashed;
  }
}
