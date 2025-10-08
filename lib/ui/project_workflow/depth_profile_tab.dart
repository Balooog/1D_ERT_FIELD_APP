import 'package:flutter/material.dart';

import '../../models/calc.dart';
import '../../models/site.dart';
import '../../utils/distance_unit.dart';

class DepthProfileTab extends StatelessWidget {
  const DepthProfileTab({
    super.key,
    required this.site,
    this.distanceUnit = DistanceUnit.feet,
  });

  final SiteRecord site;
  final DistanceUnit distanceUnit;

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
    final depthValue = distanceUnit.fromMeters(deepest.depthMeters);
    final depthUnitLabel = distanceUnit == DistanceUnit.feet ? 'ft' : 'm';
    final trend = _trendDescription(steps);
    final message =
        'Depth cue: $trend toward ${_formatNumber(depthValue)} $depthUnitLabel (~${_formatNumber(deepest.depthMeters)} m, ≈${deepest.rho.toStringAsFixed(0)} Ω·m).';

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${steps.length} spacing${steps.length == 1 ? '' : 's'} informing cue',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _buildDepthTable(context, steps),
          ],
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

  Widget _buildDepthTable(BuildContext context, List<_DepthStep> steps) {
    final unitLabel = distanceUnit == DistanceUnit.feet ? 'ft' : 'm';
    final theme = Theme.of(context);
    return DataTable(
      headingRowHeight: 32,
      dataRowMinHeight: 32,
      dataRowMaxHeight: 40,
      headingTextStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      dataTextStyle: theme.textTheme.bodySmall,
      columnSpacing: 24,
      horizontalMargin: 12,
      columns: [
        DataColumn(
          label: Center(child: Text('Depth ($unitLabel)')),
        ),
        const DataColumn(
          label: Center(child: Text('ρa (Ω·m)')),
        ),
      ],
      rows: [
        for (final step in steps)
          DataRow(
            cells: [
              DataCell(
                Center(
                  child: Text(
                    _formatNumber(distanceUnit.fromMeters(step.depthMeters)),
                  ),
                ),
              ),
              DataCell(
                Center(
                  child: Text(_formatNumber(step.rho)),
                ),
              ),
            ],
          ),
      ],
    );
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
