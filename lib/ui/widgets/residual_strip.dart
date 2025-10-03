import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/spacing_point.dart';
import '../../services/qc_rules.dart';

class ResidualStrip extends StatelessWidget {
  const ResidualStrip({super.key, required this.points, required this.inversion});

  final List<SpacingPoint> points;
  final dynamic inversion;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty || inversion.predictedRho.isEmpty) {
      return const SizedBox(height: 120);
    }
    final predicted = inversion.predictedRho;
    final bars = <Widget>[];
    for (var i = 0; i < points.length; i++) {
      final fit = i < predicted.length ? predicted[i] : predicted.last;
      final residual = fit == 0 ? 0.0 : (points[i].rhoAppOhmM - fit) / fit;
      final level = classifyPoint(
        residual: residual,
        coefficientOfVariation:
            points[i].sigmaRhoOhmM == null || points[i].rhoAppOhmM == 0
                ? null
                : (points[i].sigmaRhoOhmM! / points[i].rhoAppOhmM),
        point: points[i],
      );
      bars.add(Expanded(
        child: _ResidualBar(residual: residual, level: level),
      ));
    }

    return SizedBox(
      height: 120,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Residuals', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'Residuals (%)',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ResidualGridPainter(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: Text('+15%', style: Theme.of(context).textTheme.bodySmall),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: bars,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Text('-15%', style: Theme.of(context).textTheme.bodySmall),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResidualBar extends StatelessWidget {
  const _ResidualBar({required this.residual, required this.level});

  final double residual;
  final QaLevel level;

  @override
  Widget build(BuildContext context) {
    final color = _qaColor(level);
    final positiveHeight = residual >= 0 ? residual : 0;
    final negativeHeight = residual < 0 ? -residual : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: math.max((positiveHeight * 100).abs().toInt(), 1),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                height: math.min(positiveHeight.abs() * 80, 80),
                decoration: BoxDecoration(color: color),
              ),
            ),
          ),
          Expanded(
            flex: math.max((negativeHeight * 100).abs().toInt(), 1),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: double.infinity,
                height: math.min(negativeHeight.abs() * 80, 80),
                decoration: BoxDecoration(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResidualGridPainter extends CustomPainter {
  const _ResidualGridPainter({required this.color});

  final Color color;

  static const double _limit = 0.15;
  static const List<double> _lines = [-_limit, -0.1, -0.05, 0, 0.05, 0.1, _limit];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    final paint = Paint()..color = color;

    for (final value in _lines) {
      final position = _mapValueToY(value, size.height);
      final isMajor = value == 0 || value.abs() == _limit;
      paint
        ..strokeWidth = isMajor ? 0.8 : 0.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, position), Offset(size.width, position), paint);
    }
  }

  double _mapValueToY(double value, double height) {
    final clamped = value.clamp(-_limit, _limit);
    final ratio = (_limit - clamped) / (_limit * 2);
    return ratio * height;
  }

  @override
  bool shouldRepaint(covariant _ResidualGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
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
