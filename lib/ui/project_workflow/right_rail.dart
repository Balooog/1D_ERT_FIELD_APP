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
    double? groundTemperatureF,
    SiteLocation? location,
    bool? updateLocation,
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
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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

  void _handleMenuSelection(_RightRailMenuAction action) {
    switch (action) {
      case _RightRailMenuAction.exportCsv:
        widget.onExportCsv?.call();
        break;
      case _RightRailMenuAction.exportSitePdf:
        widget.onExportSitePdf?.call();
        break;
      case _RightRailMenuAction.exportAllSitesPdf:
        widget.onExportAllSitesPdf?.call();
        break;
      case _RightRailMenuAction.settings:
        _openSiteSettings();
        break;
    }
  }

  PopupMenuEntry<_RightRailMenuAction> _buildMenuItem(
    _RightRailMenuAction action,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_RightRailMenuAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverflowMenu(BuildContext context) {
    final items = <PopupMenuEntry<_RightRailMenuAction>>[];
    if (widget.onExportCsv != null) {
      items.add(
        _buildMenuItem(
          _RightRailMenuAction.exportCsv,
          Icons.file_download,
          'Export CSV & DAT',
        ),
      );
    }
    if (widget.onExportSitePdf != null) {
      items.add(
        _buildMenuItem(
          _RightRailMenuAction.exportSitePdf,
          Icons.picture_as_pdf,
          'Site PDF…',
        ),
      );
    }
    if (widget.onExportAllSitesPdf != null) {
      items.add(
        _buildMenuItem(
          _RightRailMenuAction.exportAllSitesPdf,
          Icons.print,
          'All sites PDF',
        ),
      );
    }
    items.add(
      _buildMenuItem(
        _RightRailMenuAction.settings,
        Icons.tune,
        'Site settings',
      ),
    );
    return PopupMenuButton<_RightRailMenuAction>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_horiz),
      onSelected: _handleMenuSelection,
      itemBuilder: (context) => items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeResult = tryRenderSafe<TwoLayerInversionResult?>(
      widget.inversionResult,
      null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight - 140
              : 320.0;
          final plotHeight = availableHeight.clamp(280.0, 480.0).toDouble();
          final panel = InversionSummaryPanel(
            site: widget.site,
            result: safeResult,
            isLoading: widget.isInversionLoading,
            distanceUnit: widget.distanceUnit,
            margin: EdgeInsets.zero,
            plotHeight: plotHeight,
            trailing: _buildOverflowMenu(context),
          );

          if (!constraints.maxHeight.isFinite) {
            return panel;
          }

          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 12),
              child: panel,
            ),
          );
        },
      ),
    );
  }
}

enum _RightRailMenuAction {
  exportCsv,
  exportSitePdf,
  exportAllSitesPdf,
  settings,
}
