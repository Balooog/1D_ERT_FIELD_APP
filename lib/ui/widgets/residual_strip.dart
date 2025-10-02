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
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const _GuideLine(value: 0.15),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: bars,
                      ),
                    ),
                    const _GuideLine(value: -0.15),
                  ],
                ),
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

class _GuideLine extends StatelessWidget {
  const _GuideLine({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text('${(value * 100).toStringAsFixed(0)}%'),
    );
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
