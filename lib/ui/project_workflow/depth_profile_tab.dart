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

    final deepest = steps.last;
    final depthFt = metersToFeet(deepest.depthMeters);
    final trend = _trendDescription(steps);
    final message =
        'Depth cue: $trend toward ${_formatNumber(depthFt)} ft (~${_formatNumber(deepest.depthMeters)} m, ≈${deepest.rho.toStringAsFixed(0)} Ω·m).';

    return Card(
      margin: const EdgeInsets.all(12),
      child: ListTile(
        title: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: Text(
          '${steps.length} spacing${steps.length == 1 ? '' : 's'} informing cue',
          style: Theme.of(context).textTheme.bodySmall,
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

  String _trendDescription(List<_DepthStep> steps) {
    if (steps.length < 2) {
      return 'Resistivity stable';
    }
    final delta = steps.last.rho - steps.first.rho;
    if (delta.abs() < 0.5) {
      return 'Resistivity stable';
    }
    return delta > 0 ? 'Resistivity increasing' : 'Resistivity decreasing';
  }

  String _formatNumber(double value) {
    var text = value.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '');
      if (text.endsWith('.')) {
        text = text.substring(0, text.length - 1);
      }
    }
    return text;
  }
}

class _DepthStep {
  _DepthStep({required this.depthMeters, required this.rho});

  final double depthMeters;
  final double rho;
}
