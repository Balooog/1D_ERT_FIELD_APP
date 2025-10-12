import 'package:flutter/material.dart';

import '../../core/render_safety.dart';
import '../../models/site.dart';
import '../../services/inversion.dart';
import '../../utils/distance_unit.dart';
import 'inversion_summary_panel.dart';
import 'right_detail_panel.dart';

class RightRail extends StatefulWidget {
  const RightRail({
    super.key,
    required this.site,
    required this.projectDefaultStacks,
    required this.onMetadataChanged,
    required this.inversionResult,
    required this.isInversionLoading,
    required this.distanceUnit,
    this.onExportCsv,
    this.onExportSitePdf,
    this.onExportAllSitesPdf,
  });

  final SiteRecord site;
  final int projectDefaultStacks;
  final void Function({
    double? power,
    int? stacks,
    SoilType? soil,
    MoistureLevel? moisture,
  }) onMetadataChanged;
  final TwoLayerInversionResult? inversionResult;
  final bool isInversionLoading;
  final DistanceUnit distanceUnit;
  final VoidCallback? onExportCsv;
  final VoidCallback? onExportSitePdf;
  final VoidCallback? onExportAllSitesPdf;

  @override
  State<RightRail> createState() => _RightRailState();
}

class _RightRailState extends State<RightRail> {
  Future<void> _openSiteSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: RightDetailPanel(
                site: widget.site,
                projectDefaultStacks: widget.projectDefaultStacks,
                onMetadataChanged: widget.onMetadataChanged,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeResult = tryRenderSafe<TwoLayerInversionResult?>(
      widget.inversionResult,
      null,
    );

    Widget? buildActions() {
      if (widget.onExportCsv == null &&
          widget.onExportSitePdf == null &&
          widget.onExportAllSitesPdf == null) {
        return null;
      }
      return Card(
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Quick actions',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.onExportCsv != null)
                    FilledButton.icon(
                      icon: const Icon(Icons.file_download),
                      label: const Text('Export CSV & DAT'),
                      onPressed: widget.onExportCsv,
                    ),
                  if (widget.onExportSitePdf != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Site PDF…'),
                      onPressed: widget.onExportSitePdf,
                    ),
                  if (widget.onExportAllSitesPdf != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text('All sites PDF'),
                      onPressed: widget.onExportAllSitesPdf,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSiteSummary() {
      return Card(
        color: theme.colorScheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.site.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID ${widget.site.siteId}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openSiteSettings,
                    icon: const Icon(Icons.tune),
                    label: const Text('Site settings'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _SummaryChip(
                    label: 'Power',
                    value:
                        '${widget.site.powerMilliAmps.toStringAsFixed(1)} mA',
                    icon: Icons.bolt,
                  ),
                  _SummaryChip(
                    label: 'Stacks',
                    value: '${widget.site.stacks}',
                    icon: Icons.repeat,
                  ),
                  _SummaryChip(
                    label: 'Soil',
                    value: widget.site.soil.label,
                    icon: Icons.terrain,
                  ),
                  _SummaryChip(
                    label: 'Moisture',
                    value: widget.site.moisture.label,
                    icon: Icons.water_drop,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = buildActions();
          if (!constraints.maxHeight.isFinite) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSiteSummary(),
                const SizedBox(height: 12),
                InversionSummaryPanel(
                  site: widget.site,
                  result: safeResult,
                  isLoading: widget.isInversionLoading,
                  distanceUnit: widget.distanceUnit,
                  margin: EdgeInsets.zero,
                  plotHeight: 300,
                ),
                if (actions != null) ...[
                  const SizedBox(height: 12),
                  actions,
                ],
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildSiteSummary(),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InversionSummaryPanel(
                    site: widget.site,
                    result: safeResult,
                    isLoading: widget.isInversionLoading,
                    distanceUnit: widget.distanceUnit,
                    margin: EdgeInsets.zero,
                    plotHeight: (constraints.maxHeight - 220)
                        .clamp(260, 420)
                        .toDouble(),
                  ),
                ),
              ),
              if (actions != null) ...[
                const SizedBox(height: 12),
                actions,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
