import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/inversion_model.dart';
import '../../models/spacing_point.dart';
import '../../services/qc_rules.dart';
import 'point_details_sheet.dart';

class SoundingChart extends StatelessWidget {
  const SoundingChart({super.key, required this.points, required this.inversion});

  final List<SpacingPoint> points;
  final InversionModel inversion;

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
    final lowerSpots = <FlSpot>[];

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = _log10(p.spacingMetric);
      final y = _log10(p.rhoApp);
      spots.add(FlSpot(x, y));
      double? residual;
      if (i < predicted.length) {
        final fit = predicted[i];
        residual = fit == 0 ? 0 : (p.rhoApp - fit) / fit;
        predictedSpots.add(FlSpot(x, _log10(fit)));
        if (i < sigma.length) {
          final frac = sigma[i];
          final upper = fit * (1 + frac.abs());
          final lower = fit * (1 - frac.abs());
          upperSpots.add(FlSpot(x, _log10(upper)));
          lowerSpots.add(FlSpot(x, _log10(math.max(lower, 1e-6))));
        }
      }
      final level = classifyPoint(
        residual: residual ?? 0,
        coefficientOfVariation:
            p.sigmaRhoApp == null || p.rhoApp == 0 ? null : (p.sigmaRhoApp! / p.rhoApp),
        point: p,
      );
      colors.add(_qaColor(level));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LineChart(
        LineChartData(
          clipData: const FlClipData.all(),
          minX: spots.map((e) => e.x).reduce(math.min) - 0.1,
          maxX: spots.map((e) => e.x).reduce(math.max) + 0.1,
          minY: spots.map((e) => e.y).reduce(math.min) - 0.2,
          maxY: spots.map((e) => e.y).reduce(math.max) + 0.2,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Text('${math.pow(10, value).toStringAsFixed(1)}'),
                reservedSize: 60,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Text('${math.pow(10, value).toStringAsFixed(1)}'),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            if (upperSpots.isNotEmpty && lowerSpots.isNotEmpty)
              LineChartBarData(
                spots: upperSpots,
                isCurved: true,
                color: Colors.blue.withOpacity(0.2),
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: Colors.blue.withOpacity(0.1),
                ),
              ),
            LineChartBarData(
              spots: predictedSpots,
              isCurved: true,
              color: Colors.blue,
              dotData: const FlDotData(show: false),
            ),
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
          ],
          gridData: FlGridData(show: true, drawVerticalLine: true, drawHorizontalLine: true),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.lineBarSpots != null) {
                final index = response!.lineBarSpots!.first.spotIndex;
                showModalBottomSheet(
                  context: context,
                  builder: (ctx) => PointDetailsSheet(point: points[index]),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  double _log10(double value) => math.log(value) / math.ln10;

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
