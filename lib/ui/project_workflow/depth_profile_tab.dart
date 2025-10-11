import 'package:flutter/material.dart';

import '../../models/calc.dart';
import '../../models/site.dart';
import '../../utils/distance_unit.dart';
import '../../utils/format.dart';

class DepthProfileTab extends StatefulWidget {
  const DepthProfileTab({
    super.key,
    required this.site,
    this.distanceUnit = DistanceUnit.feet,
  });

  final SiteRecord site;
  final DistanceUnit distanceUnit;

  @override
  State<DepthProfileTab> createState() => _DepthProfileTabState();
}

class _DepthProfileTabState extends State<DepthProfileTab> {
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
    final depthValue = widget.distanceUnit.fromMeters(deepest.depthMeters);
    final depthUnitLabel = widget.distanceUnit == DistanceUnit.feet ? 'ft' : 'm';
    final trend = _trendDescription(steps);
    final message =
        'Depth cue: $trend toward ${formatCompactValue(depthValue)} $depthUnitLabel (~${formatMetersTooltip(deepest.depthMeters)} m, ≈${formatCompactValue(deepest.rho)} Ω·m).';

    return SizedBox(
      height: 160,
      child: Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Expanded(
                child: _buildDepthTable(context, steps, unitLabel: depthUnitLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_DepthStep> _depthSteps() {
    final steps = <_DepthStep>[];
    for (final spacing in widget.site.spacings) {
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

  Widget _buildDepthTable(
    BuildContext context,
    List<_DepthStep> steps, {
    required String unitLabel,
  }) {
    const maxVisibleRows = 4;
    final theme = Theme.of(context);
    final visibleSteps = steps.take(maxVisibleRows).toList();
    final hiddenCount = steps.length - visibleSteps.length;
    final headerStyle =
        theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDepthHeaderRow(unitLabel, headerStyle),
        const Divider(height: 12),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final step in visibleSteps)
                  _buildDepthDataRow(
                    depthLabel: formatCompactValue(
                        widget.distanceUnit.fromMeters(step.depthMeters)),
                    rhoLabel: formatCompactValue(step.rho),
                    style: valueStyle,
                  ),
                if (hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+$hiddenCount more spacing${hiddenCount == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDepthHeaderRow(String unitLabel, TextStyle? style) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Text('Depth ($unitLabel)', style: style),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: Text('ρa (Ω·m)', style: style),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepthDataRow({
    required String depthLabel,
    required String rhoLabel,
    TextStyle? style,
  }) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Text(depthLabel, style: style),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: Text(rhoLabel, style: style),
            ),
          ),
        ],
      ),
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

}

class _DepthStep {
  _DepthStep({required this.depthMeters, required this.rho});

  final double depthMeters;
  final double rho;
}
