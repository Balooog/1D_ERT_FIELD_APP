import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/inversion.dart';
import '../../utils/distance_unit.dart';
import 'depth_cue_summary.dart';
import 'plots_panel.dart';

const _metricBlue = Color(0xFF0072B2);
const _metricOrange = Color(0xFFE69F00);
const _metricVermillion = Color(0xFFD55E00);
const _metricAccent = Color(0xFF7AA802);

class InversionSummaryPanel extends StatelessWidget {
  const InversionSummaryPanel({
    super.key,
    required this.site,
    required this.result,
    required this.isLoading,
    required this.distanceUnit,
    this.margin = const EdgeInsets.all(12),
  });

  final SiteRecord site;
  final TwoLayerInversionResult? result;
  final bool isLoading;
  final DistanceUnit distanceUnit;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cueSummary = DepthCueSummaryData.fromSite(site, distanceUnit);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );

    return Card(
      margin: margin,
      color: theme.colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Two-layer inversion — ${site.displayName}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(cueSummary.message, style: subtitleStyle),
            const SizedBox(height: 16),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: InversionPlotPanel(
                  result: result,
                  isLoading: isLoading,
                  distanceUnit: distanceUnit,
                  siteLabel: null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            InversionStatsBar(
              result: result,
              distanceUnit: distanceUnit,
            ),
            if (cueSummary.hasCue && cueSummary.steps.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: theme.colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 12),
              DepthCueTable(summary: cueSummary, distanceUnit: distanceUnit),
            ],
          ],
        ),
      ),
    );
  }
}

class InversionStatsBar extends StatelessWidget {
  const InversionStatsBar({
    super.key,
    required this.result,
    required this.distanceUnit,
  });

  final TwoLayerInversionResult? result;
  final DistanceUnit distanceUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.colorScheme.outlineVariant),
    );

    if (result == null) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'Record at least two valid spacings to compute inversion.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final summary = result!;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _MetricChip(
          label: 'ρ₁',
          value: _formatRho(summary.rho1),
          color: _metricBlue,
        ),
        _MetricChip(
          label: 'ρ₂',
          value: _formatRho(summary.rho2),
          color: _metricOrange,
        ),
        if (summary.halfSpaceRho != null)
          _MetricChip(
            label: 'ρ₃',
            value: _formatRho(summary.halfSpaceRho!),
            color: _metricVermillion,
          ),
        if (summary.thicknessM != null)
          _MetricChip(
            label: 'h',
            value:
                '${distanceUnit.formatSpacing(summary.thicknessM!)} ${distanceUnit == DistanceUnit.feet ? 'ft' : 'm'}',
            color: _metricAccent,
          ),
        _MetricChip(
          label: 'RMS',
          value: '${(summary.rms * 100).toStringAsFixed(1)}%',
          color: theme.colorScheme.primary,
        ),
        _MetricChip(
          label: 'Solved',
          value:
              '${summary.solvedAt.hour.toString().padLeft(2, '0')}:${summary.solvedAt.minute.toString().padLeft(2, '0')}',
          color: theme.colorScheme.secondary,
        ),
      ],
    );
  }

  String _formatRho(double rho) {
    if (rho >= 1000) {
      return '${rho.toStringAsFixed(0)} Ω·m';
    }
    if (rho >= 100) {
      return '${rho.toStringAsFixed(1)} Ω·m';
    }
    return '${rho.toStringAsFixed(2)} Ω·m';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
