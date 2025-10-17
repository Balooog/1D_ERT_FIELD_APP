import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/inversion.dart';
import '../../utils/distance_unit.dart';
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
    this.plotHeight = 160,
    this.trailing,
  });

  final SiteRecord site;
  final TwoLayerInversionResult? result;
  final bool isLoading;
  final DistanceUnit distanceUnit;
  final EdgeInsetsGeometry margin;
  final double plotHeight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );
    final subtitle = result == null
        ? 'Record at least two valid spacings to compute inversion.'
        : _buildResultSummary(result!);

    return Card(
      margin: margin,
      color: theme.colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Two-layer inversion — ${site.displayName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: subtitleStyle),
            const SizedBox(height: 12),
            InversionPlotPanel(
              result: result,
              isLoading: isLoading,
              distanceUnit: distanceUnit,
              siteLabel: null,
              chartHeight: plotHeight,
            ),
            const SizedBox(height: 16),
            InversionStatsBar(
              result: result,
              distanceUnit: distanceUnit,
            ),
          ],
        ),
      ),
    );
  }

  String _buildResultSummary(TwoLayerInversionResult result) {
    final spacingCount = result.spacingFeet.length;
    final solvedAt = result.solvedAt;
    final timeLabel =
        '${solvedAt.hour.toString().padLeft(2, '0')}:${solvedAt.minute.toString().padLeft(2, '0')}';
    final spacingLabel = '$spacingCount spacing${spacingCount == 1 ? '' : 's'}';
    final rmsLabel = '${(result.rms * 100).toStringAsFixed(1)}% RMS';
    return 'Solved from $spacingLabel at $timeLabel • $rmsLabel';
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
    final chips = <Widget>[
      _MetricChip(
        label: 'Upper layer ρ',
        value: _formatRho(summary.rho1),
        color: _metricBlue,
      ),
      _MetricChip(
        label: 'Lower layer ρ',
        value: _formatRho(summary.rho2),
        color: _metricOrange,
      ),
      if (summary.halfSpaceRho != null)
        _MetricChip(
          label: 'Half-space ρ',
          value: _formatRho(summary.halfSpaceRho!),
          color: _metricVermillion,
        ),
      if (summary.thicknessM != null)
        _MetricChip(
          label: 'Layer thickness',
          value:
              '${distanceUnit.formatSpacing(summary.thicknessM!)} ${distanceUnit == DistanceUnit.feet ? 'ft' : 'm'}',
          color: _metricAccent,
        ),
      _MetricChip(
        label: 'RMS misfit',
        value: '${(summary.rms * 100).toStringAsFixed(1)}%',
        color: theme.colorScheme.primary,
      ),
    ];

    return Container(
      decoration: decoration,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              chips[i],
            ],
          ],
        ),
      ),
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
    final baseStyle = theme.textTheme.labelSmall?.copyWith(
          fontSize: 12,
          height: 1.1,
        ) ??
        const TextStyle(fontSize: 12, height: 1.1);
    final valueStyle = baseStyle.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurface,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text.rich(
        TextSpan(
          style: valueStyle,
          children: [
            TextSpan(
              text: '$label ',
              style: baseStyle.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value, style: valueStyle),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
