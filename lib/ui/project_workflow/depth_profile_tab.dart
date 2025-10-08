import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/calc.dart';
import '../../models/site.dart';

class DepthProfileTab extends StatelessWidget {
  const DepthProfileTab({super.key, required this.site});

  final SiteRecord site;

  @override
  Widget build(BuildContext context) {
    final steps = _depthSteps();
    if (steps.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(12),
        child: Center(
          child: Text(
            'Depth cue will appear once valid resistivity values are recorded.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: CustomPaint(
          painter: _DepthProfilePainter(steps: steps),
          child: Container(),
        ),
      ),
    );
  }

  List<_DepthStep> _depthSteps() {
    final steps = <_DepthStep>[];
    for (final spacing in site.spacings) {
      final aSample = spacing.orientationA.latest;
      final bSample = spacing.orientationB.latest;
      final resistances = [
        if (aSample != null && !aSample.isBad) aSample.resistanceOhm,
        if (bSample != null && !bSample.isBad) bSample.resistanceOhm,
      ].whereType<double>();
      if (resistances.isEmpty) {
        continue;
      }
      final avgResistance =
          resistances.reduce((a, b) => a + b) / resistances.length;
      final rho = rhoAWenner(spacing.spacingFeet, avgResistance);
      final depthFt = 0.5 * spacing.spacingFeet;
      steps.add(_DepthStep(depthMeters: feetToMeters(depthFt), rho: rho));
    }
    steps.sort((a, b) => a.depthMeters.compareTo(b.depthMeters));
    return steps;
  }
}

class _DepthStep {
  _DepthStep({required this.depthMeters, required this.rho});

  final double depthMeters;
  final double rho;
}

class _DepthProfilePainter extends CustomPainter {
  _DepthProfilePainter({required this.steps});

  final List<_DepthStep> steps;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    final maxDepth = steps.last.depthMeters;
    final maxRho = steps.map((step) => step.rho).reduce((a, b) => a > b ? a : b);
    final minRho = steps.map((step) => step.rho).reduce((a, b) => a < b ? a : b);

    double depthToY(double depthMeters) {
      if (maxDepth == 0) {
        return 0;
      }
      return depthMeters / maxDepth * size.height;
    }

    double rhoToX(double rho) {
      if (maxRho == minRho) {
        return size.width * 0.5;
      }
      return ((rho - minRho) / (maxRho - minRho)) * (size.width * 0.8) + size.width * 0.1;
    }

    Offset? previous;
    for (final step in steps) {
      final y = depthToY(step.depthMeters);
      final x = rhoToX(step.rho);
      final current = Offset(x, y);
      if (previous != null) {
        canvas.drawLine(previous!, Offset(previous!.dx, current.dy), paint);
        canvas.drawLine(Offset(previous!.dx, current.dy), current, paint);
      }
      previous = current;
      textPainter.text = TextSpan(
        text:
            '${step.depthMeters.toStringAsFixed(1)} m / ${step.rho.toStringAsFixed(0)} Ω·m',
        style: const TextStyle(fontSize: 10, color: Colors.black87),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(current.dx + 4, current.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DepthProfilePainter oldDelegate) {
    return !listEquals(oldDelegate.steps, steps);
  }
}
