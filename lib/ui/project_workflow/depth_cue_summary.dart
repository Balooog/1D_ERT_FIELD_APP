import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/calc.dart';
import '../../models/site.dart';
import '../../utils/distance_unit.dart';
import '../../utils/format.dart';
import '../../utils/units.dart' as units;

class DepthCueSummaryData {
  DepthCueSummaryData({
    required this.message,
    required this.steps,
    required this.hasCue,
  });

  final String message;
  final List<DepthCueStep> steps;
  final bool hasCue;

  static DepthCueSummaryData fromSite(
    SiteRecord site,
    DistanceUnit distanceUnit,
  ) {
    final steps = _buildSteps(site);
    if (steps.isEmpty) {
      return DepthCueSummaryData(
        message:
            'Depth cue will appear once valid resistivity values are recorded.',
        steps: const [],
        hasCue: false,
      );
    }

    final trend = _describeTrend(steps);
    final deepest = steps.last;
    final depthLabel = formatCompactValue(
      distanceUnit.fromMeters(deepest.depthMeters),
    );
    final unitLabel = distanceUnit == DistanceUnit.feet ? 'ft' : 'm';
    final metersTooltip = formatMetersTooltip(deepest.depthMeters);
    final rhoLabel = formatCompactValue(deepest.rho);

    return DepthCueSummaryData(
      message:
          'Depth cue: $trend toward $depthLabel $unitLabel (~$metersTooltip m, ≈$rhoLabel Ω·m).',
      steps: List.unmodifiable(steps),
      hasCue: true,
    );
  }

  static List<DepthCueStep> _buildSteps(SiteRecord site) {
    final steps = <DepthCueStep>[];
    double? fallbackSpacingFeet;

    for (final spacing in site.spacings) {
      fallbackSpacingFeet ??= spacing.spacingFeet;
      final aSample = spacing.orientationA.latest;
      final bSample = spacing.orientationB.latest;

      final resistances = <double>[
        if (aSample != null && !aSample.isBad && aSample.resistanceOhm != null)
          aSample.resistanceOhm!,
        if (bSample != null && !bSample.isBad && bSample.resistanceOhm != null)
          bSample.resistanceOhm!,
      ];

      if (resistances.isEmpty) {
        continue;
      }

      final avgResistance =
          resistances.reduce((value, element) => value + element) /
              resistances.length;
      final rho = rhoAWenner(spacing.spacingFeet, avgResistance);
      final depthFeet = 0.5 * spacing.spacingFeet;
      steps.add(
        DepthCueStep(
          depthMeters: units.feetToMeters(depthFeet).toDouble(),
          rho: rho,
        ),
      );
    }

    if (steps.isEmpty && fallbackSpacingFeet != null) {
      final fallbackDepth =
          units.feetToMeters(fallbackSpacingFeet * 0.5).toDouble();
      steps.add(
        DepthCueStep(
          depthMeters: fallbackDepth,
          rho: 1.0,
        ),
      );
    }

    steps.sort((a, b) => a.depthMeters.compareTo(b.depthMeters));
    return steps;
  }

  static String _describeTrend(List<DepthCueStep> steps) {
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

class DepthCueStep {
  const DepthCueStep({
    required this.depthMeters,
    required this.rho,
  });

  final double depthMeters;
  final double rho;

  double depthInUnit(DistanceUnit unit) => unit.fromMeters(depthMeters);
}

class DepthCueTable extends StatelessWidget {
  const DepthCueTable({
    super.key,
    required this.summary,
    required this.distanceUnit,
  });

  final DepthCueSummaryData summary;
  final DistanceUnit distanceUnit;

  @override
  Widget build(BuildContext context) {
    if (summary.steps.isEmpty) {
      return const SizedBox.shrink();
    }

    const maxVisibleRows = 4;
    final steps = summary.steps;
    final visibleSteps = steps.take(maxVisibleRows).toList();
    final hiddenCount = math.max(0, steps.length - visibleSteps.length);
    final theme = Theme.of(context);
    final unitLabel = distanceUnit == DistanceUnit.feet ? 'ft' : 'm';
    final headerStyle =
        theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${steps.length} spacing${steps.length == 1 ? '' : 's'} informing cue',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: Scrollbar(
            thumbVisibility: steps.length > maxVisibleRows,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderRow(unitLabel: unitLabel, style: headerStyle),
                  const Divider(height: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final step in visibleSteps)
                        _DataRow(
                          depthLabel: formatCompactValue(
                            distanceUnit.fromMeters(step.depthMeters),
                          ),
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.unitLabel,
    this.style,
  });

  final String unitLabel;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
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
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.depthLabel,
    required this.rhoLabel,
    this.style,
  });

  final String depthLabel;
  final String rhoLabel;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
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
}
