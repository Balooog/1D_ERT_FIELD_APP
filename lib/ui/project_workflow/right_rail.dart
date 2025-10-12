import 'package:flutter/material.dart';

import '../../core/render_safety.dart';
import '../../models/site.dart';
import '../../services/inversion.dart';
import '../../utils/distance_unit.dart';
import 'inversion_summary_panel.dart';
import 'right_detail_panel.dart';

class RightRail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeResult = tryRenderSafe<TwoLayerInversionResult?>(
      inversionResult,
      null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedHeight = constraints.maxHeight.isFinite;
          Widget scrollableContent;
          final innerColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RightDetailPanel(
                site: site,
                projectDefaultStacks: projectDefaultStacks,
                onMetadataChanged: onMetadataChanged,
              ),
              const SizedBox(height: 12),
              InversionSummaryPanel(
                site: site,
                result: safeResult,
                isLoading: isInversionLoading,
                distanceUnit: distanceUnit,
                margin: EdgeInsets.zero,
              ),
            ],
          );
          if (hasBoundedHeight) {
            scrollableContent = Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: innerColumn,
              ),
            );
          } else {
            scrollableContent = innerColumn;
          }

          final actions = (onExportCsv != null ||
                  onExportSitePdf != null ||
                  onExportAllSitesPdf != null)
              ? Card(
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
                            if (onExportCsv != null)
                              FilledButton.icon(
                                icon: const Icon(Icons.file_download),
                                label: const Text('Export CSV & DAT'),
                                onPressed: onExportCsv,
                              ),
                            if (onExportSitePdf != null)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('Site PDF…'),
                                onPressed: onExportSitePdf,
                              ),
                            if (onExportAllSitesPdf != null)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.print),
                                label: const Text('All sites PDF'),
                                onPressed: onExportAllSitesPdf,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : null;

          if (hasBoundedHeight) {
            return Column(
              children: [
                Expanded(child: scrollableContent),
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
              scrollableContent,
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
