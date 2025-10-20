import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/calc.dart';
import '../../models/direction_reading.dart';
import '../../models/project.dart';
import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../services/troubleshoot_ohmega.dart';
import '../../state/prefs.dart';
import '../../state/providers.dart';
import '../../utils/format.dart';
import '../dev/baseline_overlay.dart';
import '../diagrams/show_electrode_dialog.dart';
import '../layout/grid_4.dart';
import '../layout/inputs.dart';
import '../layout/sizing.dart';
import '../style/density.dart';
import '../widgets/res_cluster.dart';
import '../widgets/troubleshooter_banner.dart';

const double _kTableHeaderHeight = 34;
const double _kHeaderFieldGap = 2;
const double _kCompactWrapBreakpoint = 640;
const double _kAccessoryExpandedBreakpoint = 1500;
const double _kResInlineMinWidth = 170;

class TablePanel extends ConsumerStatefulWidget {
  const TablePanel({
    super.key,
    required this.project,
    required this.site,
    required this.projectDefaultStacks,
    required this.showOutliers,
    required this.onResistanceChanged,
    required this.onSdChanged,
    required this.onInterpretationChanged,
    required this.onToggleBad,
    required this.onMetadataChanged,
    required this.onShowHistory,
    required this.onFocusChanged,
    required this.onLogTroubleshooter,
    this.isSaving = false,
    this.saveStatusLabel,
    this.diagramExportDirectoryBuilder,
  });

  final ProjectRecord project;
  final SiteRecord site;
  final int projectDefaultStacks;
  final bool showOutliers;
  final void Function(
    double spacingFt,
    OrientationKind orientation,
    double? resistance,
    double? sd,
  ) onResistanceChanged;
  final void Function(
    double spacingFt,
    OrientationKind orientation,
    double? sd,
  ) onSdChanged;
  final void Function(double spacingFt, String interpretation)
      onInterpretationChanged;
  final void Function(
    double spacingFt,
    OrientationKind orientation,
    bool isBad,
  ) onToggleBad;
  final void Function({
    double? power,
    int? stacks,
    SoilType? soil,
    MoistureLevel? moisture,
    double? groundTemperatureF,
    SiteLocation? location,
    bool? updateLocation,
  }) onMetadataChanged;
  final Future<void> Function(
    double spacingFt,
    OrientationKind orientation,
  ) onShowHistory;
  final void Function(double spacingFt, OrientationKind orientation)
      onFocusChanged;
  final Future<void> Function(String note) onLogTroubleshooter;
  final bool isSaving;
  final String? saveStatusLabel;
  final Future<Directory> Function(ProjectRecord project, SiteRecord site)?
      diagramExportDirectoryBuilder;

  @visibleForTesting
  static const String sdPromptPattern = r'^[0-9]{0,2}(\.[0-9])?$';

  @visibleForTesting
  static const double accessoryExpandedBreakpoint =
      _kAccessoryExpandedBreakpoint;

  @override
  ConsumerState<TablePanel> createState() => _TablePanelState();
}

enum _FieldType { resistance }

enum _AdvanceDirection { forward, backward, stay }

enum _ClusterMenuAction { editSd, toggleFlag, history }

class _FieldKey {
  _FieldKey({
    required this.spacingFeet,
    required this.orientation,
    required this.type,
  }) : spacingHash = (spacingFeet * 1000).round();

  final double spacingFeet;
  final int spacingHash;
  final OrientationKind? orientation;
  final _FieldType type;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _FieldKey &&
        spacingHash == other.spacingHash &&
        orientation == other.orientation &&
        type == other.type;
  }

  @override
  int get hashCode => Object.hash(spacingHash, orientation, type);
}

class _RowConfig {
  _RowConfig({
    required this.record,
    required this.flags,
    required this.aSample,
    required this.bSample,
    required this.hideA,
    required this.hideB,
    required this.sdWarningA,
    required this.sdWarningB,
    required this.sdValueA,
    required this.sdValueB,
    required this.insideFeet,
    required this.insideMeters,
    required this.outsideFeet,
    required this.outsideMeters,
    required this.aResKey,
    required this.bResKey,
  });

  final SpacingRecord record;
  final QcFlags flags;
  final DirectionReadingSample? aSample;
  final DirectionReadingSample? bSample;
  final bool hideA;
  final bool hideB;
  final bool sdWarningA;
  final bool sdWarningB;
  final double? sdValueA;
  final double? sdValueB;
  final double insideFeet;
  final double insideMeters;
  final double outsideFeet;
  final double outsideMeters;
  final _FieldKey aResKey;
  final _FieldKey bResKey;
}

class _MetadataField {
  const _MetadataField({required this.child, this.flex = 1});

  final Widget child;
  final int flex;
}

class _TablePanelState extends ConsumerState<TablePanel> {
  final Map<_FieldKey, TextEditingController> _controllers = {};
  final Map<_FieldKey, FocusNode> _focusNodes = {};
  Map<_FieldKey, _FieldKey?> _tabOrder = {};
  Map<_FieldKey, _FieldKey?> _reverseTabOrder = {};
  final Map<_FieldKey, double> _tabRanks = {};
  final ScrollController _tableController = ScrollController();
  final Map<_FieldKey, _RowConfig> _rowByField = {};
  final Map<int, GlobalKey> _guideKeys = {
    2: GlobalKey(debugLabel: 'row0_c2'),
    3: GlobalKey(debugLabel: 'row0_c3'),
    4: GlobalKey(debugLabel: 'row0_c4'),
  };
  bool _layoutDumpScheduled = false;
  static final RegExp _sdPromptRegExp = RegExp(TablePanel.sdPromptPattern);
  TablePreferences? _prefs;
  bool _askForSd = true;
  List<_FieldKey> _tabSequence = const [];
  bool _suppressNextSubmitted = false;
  int? _hoveredRowIndex;

  List<FocusNode> get tabOrderForTest {
    final nodes = <FocusNode>[];
    for (final key in _tabSequence) {
      final node = _focusNodes[key];
      if (node != null) {
        nodes.add(node);
      }
    }
    return nodes;
  }

  String? _lastTroubleshooterCode;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await TablePreferences.load();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _askForSd = prefs.askForSd;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _prefs = null;
        _askForSd = true;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _tableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacings = [...widget.site.spacings]
      ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));

    const qcConfig = QcConfig();
    final rowConfigs = <_RowConfig>[];
    final requiredKeys = <_FieldKey>[];
    final values = <_FieldKey, String>{};
    double? previousAverage;

    for (final record in spacings) {
      final aValid = record.orientationA.latest;
      final bValid = record.orientationB.latest;
      final aSample = _latestSample(record.orientationA);
      final bSample = _latestSample(record.orientationB);
      final flags = evaluateQc(
        spacingFeet: record.spacingFeet,
        resistanceA: aValid?.resistanceOhm,
        resistanceB: bValid?.resistanceOhm,
        sdA: aValid?.standardDeviationPercent,
        sdB: bValid?.standardDeviationPercent,
        config: qcConfig,
        previousRho: previousAverage,
      );
      final avg = averageApparentResistivity(record.spacingFeet, [
        aValid?.resistanceOhm,
        bValid?.resistanceOhm,
      ]);
      previousAverage = avg ?? previousAverage;

      final aResKey = _FieldKey(
        spacingFeet: record.spacingFeet,
        orientation: OrientationKind.a,
        type: _FieldType.resistance,
      );
      final bResKey = _FieldKey(
        spacingFeet: record.spacingFeet,
        orientation: OrientationKind.b,
        type: _FieldType.resistance,
      );

      requiredKeys
        ..add(aResKey)
        ..add(bResKey);

      values[aResKey] = _formatResistance(aSample?.resistanceOhm);
      values[bResKey] = _formatResistance(bSample?.resistanceOhm);

      final hideA = !widget.showOutliers && (aSample?.isBad ?? false);
      final hideB = !widget.showOutliers && (bSample?.isBad ?? false);
      final sdWarningA = (aSample?.standardDeviationPercent ?? 0) >
          qcConfig.sdThresholdPercent;
      final sdWarningB = (bSample?.standardDeviationPercent ?? 0) >
          qcConfig.sdThresholdPercent;

      rowConfigs.add(
        _RowConfig(
          record: record,
          flags: flags,
          aSample: aSample,
          bSample: bSample,
          hideA: hideA,
          hideB: hideB,
          sdWarningA: sdWarningA,
          sdWarningB: sdWarningB,
          sdValueA: aSample?.standardDeviationPercent,
          sdValueB: bSample?.standardDeviationPercent,
          insideFeet: record.tapeInsideFeet,
          insideMeters: record.tapeInsideMeters,
          outsideFeet: record.tapeOutsideFeet,
          outsideMeters: record.tapeOutsideMeters,
          aResKey: aResKey,
          bResKey: bResKey,
        ),
      );
    }

    _syncControllers(requiredKeys, values);
    _tabOrder = _buildTabOrder(rowConfigs);
    _tabRanks
      ..clear()
      ..addAll(_buildTabRanks(rowConfigs));
    _rowByField
      ..clear()
      ..addEntries([
        for (final row in rowConfigs) ...[
          MapEntry(row.aResKey, row),
          MapEntry(row.bResKey, row),
        ],
      ]);

    final theme = Theme.of(context);
    final orientationALabel =
        spacings.isEmpty ? 'N–S' : spacings.first.orientationA.label;
    final orientationBLabel =
        spacings.isEmpty ? 'W–E' : spacings.first.orientationB.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMetadata(context),
        const Divider(height: 1),
        Expanded(
          child: spacings.isEmpty
              ? Center(
                  child: Text(
                    'No spacings configured for this site.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : _buildTable(
                  context,
                  theme,
                  rowConfigs,
                  orientationALabel,
                  orientationBLabel,
                ),
        ),
      ],
    );
  }

  Widget _buildTable(
    BuildContext context,
    ThemeData theme,
    List<_RowConfig> rows,
    String orientationALabel,
    String orientationBLabel,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.hasBoundedHeight
            ? math.min(constraints.maxHeight, 520.0)
            : 520.0;
        final minWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : 520.0;
        final isCompact = constraints.maxWidth < 920;
        final headerStyle = theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          height: 1.05,
          letterSpacing: 0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: theme.colorScheme.onSurfaceVariant,
        );

        final tableContent = isCompact
            ? _buildCompactTableContent(
                context,
                theme,
                rows,
                orientationALabel,
                orientationBLabel,
                headerStyle,
                maxHeight,
              )
            : _buildWideTableContent(
                context,
                theme,
                rows,
                orientationALabel,
                orientationBLabel,
                headerStyle,
                minWidth,
                maxHeight,
              );

        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: maxHeight,
            child: tableContent,
          ),
        );
      },
    );
  }

  Widget _buildWideTableContent(
    BuildContext context,
    ThemeData theme,
    List<_RowConfig> rows,
    String orientationALabel,
    String orientationBLabel,
    TextStyle? headerStyle,
    double minWidth,
    double maxHeight,
  ) {
    final showAccessories = minWidth >= _kAccessoryExpandedBreakpoint;
    final scrollView = CustomScrollView(
      controller: _tableController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          sliver: SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              minExtent: _kTableHeaderHeight + _kHeaderFieldGap + 1,
              maxExtent: _kTableHeaderHeight + _kHeaderFieldGap + 1,
              builder: (context, overlaps) {
                return _StickyHeaderContainer(
                  overlaps: overlaps,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildWideHeaderRow(
                        context,
                        headerStyle,
                        orientationALabel,
                        orientationBLabel,
                      ),
                      const SizedBox(height: _kHeaderFieldGap),
                      const Divider(height: 1),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final row = rows[index];
                final isLast = index == rows.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
                  child: _buildWideRow(
                    theme,
                    row,
                    index,
                    showAccessories: showAccessories,
                  ),
                );
              },
              childCount: rows.length,
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.only(bottom: 8),
        ),
      ],
    );

    final vertical = Scrollbar(
      controller: _tableController,
      thumbVisibility: true,
      child: scrollView,
    );

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minWidth,
            maxWidth: minWidth,
          ),
          child: SizedBox(
            height: maxHeight,
            child: vertical,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTableContent(
    BuildContext context,
    ThemeData theme,
    List<_RowConfig> rows,
    String orientationALabel,
    String orientationBLabel,
    TextStyle? headerStyle,
    double maxHeight,
  ) {
    final scrollView = CustomScrollView(
      controller: _tableController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          sliver: SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              minExtent: _kTableHeaderHeight + _kHeaderFieldGap + 1,
              maxExtent: _kTableHeaderHeight + _kHeaderFieldGap + 1,
              builder: (context, overlaps) {
                return _StickyHeaderContainer(
                  overlaps: overlaps,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCompactHeaderRow(
                        context,
                        headerStyle,
                        orientationALabel,
                        orientationBLabel,
                      ),
                      const SizedBox(height: _kHeaderFieldGap),
                      const Divider(height: 1),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final row = rows[index];
                final isLast = index == rows.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
                  child: _buildCompactRow(theme, row, index),
                );
              },
              childCount: rows.length,
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.only(bottom: 8),
        ),
      ],
    );

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SizedBox(
        height: maxHeight,
        child: Scrollbar(
          controller: _tableController,
          thumbVisibility: true,
          child: scrollView,
        ),
      ),
    );
  }

  Widget _buildWideHeaderRow(
    BuildContext context,
    TextStyle? style,
    String orientationALabel,
    String orientationBLabel,
  ) {
    return _buildHeaderGrid(
      context: context,
      style: style,
      orientationALabel: orientationALabel,
      orientationBLabel: orientationBLabel,
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildCompactHeaderRow(
    BuildContext context,
    TextStyle? style,
    String orientationALabel,
    String orientationBLabel,
  ) {
    return _buildHeaderGrid(
      context: context,
      style: style,
      orientationALabel: orientationALabel,
      orientationBLabel: orientationBLabel,
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildHeaderGrid({
    required BuildContext context,
    required TextStyle? style,
    required String orientationALabel,
    required String orientationBLabel,
    required EdgeInsets padding,
  }) {
    return FourColLayout(
      padding: padding,
      gutter: kGutter,
      builder: (ctx, spec) {
        Widget buildCell({
          required Key key,
          required double width,
          required String label,
          String? subLabel,
          String? tooltip,
        }) {
          return SizedBox(
            key: key,
            width: width,
            child: _headerLabel(
              context,
              label,
              style: style,
              tooltip: tooltip ?? label,
              subLabel: subLabel,
            ),
          );
        }

        final children = <Widget>[
          buildCell(
            key: const Key('hdr_c1'),
            width: spec.c1,
            label: 'a-spacing (ft)',
            tooltip: 'Source electrode spacing, feet',
          ),
          if (spec.gutter > 0) SizedBox(width: spec.gutter),
          buildCell(
            key: const Key('hdr_c2'),
            width: spec.c2,
            label: 'Pins (ft)',
            subLabel: 'in / out',
            tooltip:
                'Inside/outside electrode positions derived from spacing (feet)',
          ),
          if (spec.gutter > 0) SizedBox(width: spec.gutter),
          buildCell(
            key: const Key('hdr_c3'),
            width: spec.c3,
            label: 'Res $orientationALabel',
            tooltip:
                'Apparent resistance for $orientationALabel orientation (ohms)',
          ),
          if (spec.gutter > 0) SizedBox(width: spec.gutter),
          buildCell(
            key: const Key('hdr_c4'),
            width: spec.c4,
            label: 'Res $orientationBLabel',
            tooltip:
                'Apparent resistance for $orientationBLabel orientation (ohms)',
          ),
        ];

        return Row(children: children);
      },
    );
  }

  Widget _buildWideRow(
    ThemeData theme,
    _RowConfig row,
    int index, {
    required bool showAccessories,
  }) {
    final highlight = _hoveredRowIndex == index;
    final background = highlight
        ? theme.colorScheme.surfaceTint.withValues(alpha: 0.08)
        : Colors.transparent;
    final borderColor =
        highlight ? theme.colorScheme.primary.withValues(alpha: 0.24) : null;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hoveredRowIndex = index;
        });
      },
      onExit: (_) {
        setState(() {
          _hoveredRowIndex = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: borderColor == null
              ? null
              : Border.all(color: borderColor, width: 1),
        ),
        padding: EdgeInsets.zero,
        child: FourColLayout(
          gutter: kGutter,
          builder: (ctx, spec) {
            final rowChild = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDataColumnCell(
                  width: spec.c1,
                  columnIndex: 1,
                  rowIndex: index,
                  child: _buildSpacingCell(theme, row),
                ),
                if (spec.gutter > 0) SizedBox(width: spec.gutter),
                _buildDataColumnCell(
                  width: spec.c2,
                  columnIndex: 2,
                  rowIndex: index,
                  child: _buildPinsCell(theme, row),
                ),
                if (spec.gutter > 0) SizedBox(width: spec.gutter),
                _buildCluster(
                  theme: theme,
                  row: row,
                  key: row.aResKey,
                  orientation: OrientationKind.a,
                  hide: row.hideA,
                  rowIndex: index,
                  columnIndex: 3,
                  width: spec.c3,
                  showAccessories: showAccessories,
                ),
                if (spec.gutter > 0) SizedBox(width: spec.gutter),
                _buildCluster(
                  theme: theme,
                  row: row,
                  key: row.bResKey,
                  orientation: OrientationKind.b,
                  hide: row.hideB,
                  rowIndex: index,
                  columnIndex: 4,
                  width: spec.c4,
                  showAccessories: showAccessories,
                ),
              ],
            );
            final footerWidth =
                spec.c1 + (spec.gutter > 0 ? spec.gutter : 0) + spec.c2;
            final content = Stack(
              clipBehavior: Clip.none,
              children: [
                rowChild,
                Positioned(
                  left: 0,
                  bottom: 2,
                  width: footerWidth,
                  child: _buildInterpretationFooter(
                    theme,
                    row,
                    width: footerWidth,
                  ),
                ),
              ],
            );
            return SizedBox(
              height: kRowH,
              child: kShowLayoutGuides
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        content,
                        const Positioned.fill(
                          child: BaselineOverlay(),
                        ),
                      ],
                    )
                  : content,
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompactRow(ThemeData theme, _RowConfig row, int index) {
    final highlight = _hoveredRowIndex == index;
    final background = highlight
        ? theme.colorScheme.surfaceTint.withValues(alpha: 0.08)
        : Colors.transparent;
    final borderColor =
        highlight ? theme.colorScheme.primary.withValues(alpha: 0.24) : null;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hoveredRowIndex = index;
        });
      },
      onExit: (_) {
        setState(() {
          _hoveredRowIndex = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: borderColor == null
              ? null
              : Border.all(color: borderColor, width: 1),
        ),
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width;
            final showAccessories = maxWidth >= _kAccessoryExpandedBreakpoint;

            return FourColLayout(
              gutter: kGutter,
              builder: (ctx, spec) {
                final gutter = spec.gutter > 0 ? spec.gutter : 0.0;
                final collapseResColumns = maxWidth < _kCompactWrapBreakpoint ||
                    spec.c3 < _kResInlineMinWidth ||
                    spec.c4 < _kResInlineMinWidth;

                if (!collapseResColumns) {
                  final rowChild = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDataColumnCell(
                        width: spec.c1,
                        columnIndex: 1,
                        rowIndex: index,
                        child: _buildSpacingCell(theme, row),
                      ),
                      if (gutter > 0) SizedBox(width: gutter),
                      _buildDataColumnCell(
                        width: spec.c2,
                        columnIndex: 2,
                        rowIndex: index,
                        child: _buildPinsCell(theme, row),
                      ),
                      if (gutter > 0) SizedBox(width: gutter),
                      _buildCluster(
                        theme: theme,
                        row: row,
                        key: row.aResKey,
                        orientation: OrientationKind.a,
                        hide: row.hideA,
                        rowIndex: index,
                        columnIndex: 3,
                        width: spec.c3,
                        showAccessories: showAccessories,
                      ),
                      if (gutter > 0) SizedBox(width: gutter),
                      _buildCluster(
                        theme: theme,
                        row: row,
                        key: row.bResKey,
                        orientation: OrientationKind.b,
                        hide: row.hideB,
                        rowIndex: index,
                        columnIndex: 4,
                        width: spec.c4,
                        showAccessories: showAccessories,
                      ),
                    ],
                  );
                  final footerWidth =
                      spec.c1 + (gutter > 0 ? gutter : 0) + spec.c2;
                  final content = Stack(
                    clipBehavior: Clip.none,
                    children: [
                      rowChild,
                      Positioned(
                        left: 0,
                        bottom: 2,
                        width: footerWidth,
                        child: _buildInterpretationFooter(
                          theme,
                          row,
                          width: footerWidth,
                        ),
                      ),
                    ],
                  );
                  return SizedBox(
                    height: kRowH,
                    child: content,
                  );
                }

                final staticWidth =
                    spec.c1 + (gutter > 0 ? gutter : 0) + spec.c2;
                final lineARow = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDataColumnCell(
                      width: spec.c1,
                      columnIndex: 1,
                      rowIndex: index,
                      child: _buildSpacingCell(theme, row),
                    ),
                    if (gutter > 0) SizedBox(width: gutter),
                    _buildDataColumnCell(
                      width: spec.c2,
                      columnIndex: 2,
                      rowIndex: index,
                      child: _buildPinsCell(theme, row),
                    ),
                  ],
                );
                final lineA = SizedBox(
                  height: kRowH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      lineARow,
                      Positioned(
                        left: 0,
                        bottom: 2,
                        width: staticWidth,
                        child: _buildInterpretationFooter(
                          theme,
                          row,
                          width: staticWidth,
                        ),
                      ),
                    ],
                  ),
                );

                final indent =
                    spec.c1 + spec.c2 + (gutter > 0 ? gutter * 2 : 0);

                final lineB = SizedBox(
                  height: kRowH,
                  child: Row(
                    children: [
                      if (indent > 0) SizedBox(width: indent),
                      _buildCluster(
                        theme: theme,
                        row: row,
                        key: row.aResKey,
                        orientation: OrientationKind.a,
                        hide: row.hideA,
                        rowIndex: index,
                        columnIndex: 3,
                        width: spec.c3,
                        showAccessories: false,
                      ),
                      if (gutter > 0) SizedBox(width: gutter),
                      _buildCluster(
                        theme: theme,
                        row: row,
                        key: row.bResKey,
                        orientation: OrientationKind.b,
                        hide: row.hideB,
                        rowIndex: index,
                        columnIndex: 4,
                        width: spec.c4,
                        showAccessories: false,
                      ),
                    ],
                  ),
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    lineA,
                    const SizedBox(height: 6),
                    lineB,
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDataColumnCell({
    required double width,
    required int columnIndex,
    required int rowIndex,
    required Widget child,
  }) {
    Widget content = child;
    if (kShowLayoutGuides && rowIndex == 0) {
      final guideKey = _guideKeys[columnIndex];
      if (guideKey != null) {
        content = Container(key: guideKey, child: child);
        _scheduleLayoutDump();
      }
    }
    return SizedBox(
      key: Key('row${rowIndex}_c$columnIndex'),
      width: width,
      child: content,
    );
  }

  void _scheduleLayoutDump() {
    if (!kShowLayoutGuides || _layoutDumpScheduled) {
      return;
    }
    _layoutDumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final entry in _guideKeys.entries) {
        final context = entry.value.currentContext;
        if (context == null) {
          continue;
        }
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) {
          continue;
        }
        final origin = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        debugPrint(
          'layout rect row0_c${entry.key}: '
          '(${origin.dx.toStringAsFixed(1)}, ${origin.dy.toStringAsFixed(1)}) '
          '${size.width.toStringAsFixed(1)}×${size.height.toStringAsFixed(1)}',
        );
      }
      _layoutDumpScheduled = false;
    });
  }

  Widget _buildCluster({
    required ThemeData theme,
    required _RowConfig row,
    required _FieldKey key,
    required OrientationKind orientation,
    required bool hide,
    required int rowIndex,
    required int columnIndex,
    required double width,
    required bool showAccessories,
  }) {
    final sample = orientation == OrientationKind.a ? row.aSample : row.bSample;
    final sdValue =
        orientation == OrientationKind.a ? row.sdValueA : row.sdValueB;
    final sdWarning =
        orientation == OrientationKind.a ? row.sdWarningA : row.sdWarningB;
    final isFlagged = sample?.isBad ?? false;

    final accessories = showAccessories
        ? <Widget>[
            _buildAccessoryIcon(
              theme: theme,
              key: Key('row${rowIndex}_c${columnIndex}_sd_icon'),
              icon: Icons.percent,
              tooltip: 'Standard deviation',
              selected: sdValue != null,
              warning: sdWarning,
              onPressed: hide ? null : () => _editStandardDeviation(key),
            ),
            _buildAccessoryIcon(
              theme: theme,
              key: Key('row${rowIndex}_c${columnIndex}_flag_icon'),
              icon: isFlagged ? Icons.flag : Icons.flag_outlined,
              tooltip: isFlagged ? 'Clear flag' : 'Mark reading bad',
              selected: isFlagged,
              onPressed: hide
                  ? null
                  : () => widget.onToggleBad(
                        row.record.spacingFeet,
                        orientation,
                        !isFlagged,
                      ),
            ),
            _buildAccessoryIcon(
              theme: theme,
              key: Key('row${rowIndex}_c${columnIndex}_history_icon'),
              icon: Icons.history,
              tooltip: 'Show edit history',
              onPressed:
                  hide ? null : () => _showHistoryOverlay(row, orientation),
            ),
          ]
        : const <Widget>[];

    final menuButton = compactMenuButton<_ClusterMenuAction>(
      key: Key('row${rowIndex}_c${columnIndex}_menu'),
      tooltip: 'More actions',
      itemBuilder: (context) => <PopupMenuEntry<_ClusterMenuAction>>[
        PopupMenuItem(
          value: _ClusterMenuAction.editSd,
          enabled: !hide,
          child: const Text('Edit SD'),
        ),
        PopupMenuItem(
          value: _ClusterMenuAction.toggleFlag,
          enabled: !hide,
          child: Text(isFlagged ? 'Clear flag' : 'Mark reading bad'),
        ),
        PopupMenuItem(
          value: _ClusterMenuAction.history,
          enabled: !hide,
          child: const Text('Show edit history'),
        ),
      ],
      onSelected: (action) => _handleClusterMenuAction(
        action: action,
        row: row,
        key: key,
        orientation: orientation,
        hide: hide,
        isFlagged: isFlagged,
      ),
    );

    return SizedBox(
      key: Key('row${rowIndex}_c$columnIndex'),
      width: width,
      child: Opacity(
        opacity: hide ? 0.45 : 1,
        child: ResCluster(
          primary: _buildResistanceField(
            theme: theme,
            row: row,
            key: key,
            sample: sample,
            orientation: orientation,
            hide: hide,
            rowIndex: rowIndex,
            columnIndex: columnIndex,
          ),
          accessories: accessories,
          menu: menuButton,
        ),
      ),
    );
  }

  void _handleClusterMenuAction({
    required _ClusterMenuAction action,
    required _RowConfig row,
    required _FieldKey key,
    required OrientationKind orientation,
    required bool hide,
    required bool isFlagged,
  }) {
    if (hide) return;
    switch (action) {
      case _ClusterMenuAction.editSd:
        unawaited(_editStandardDeviation(key));
        break;
      case _ClusterMenuAction.toggleFlag:
        widget.onToggleBad(
          row.record.spacingFeet,
          orientation,
          !isFlagged,
        );
        break;
      case _ClusterMenuAction.history:
        unawaited(_showHistoryOverlay(row, orientation));
        break;
    }
  }

  Future<void> _editStandardDeviation(_FieldKey key) async {
    await _handleSdPrompt(
      key,
      direction: _AdvanceDirection.stay,
      forcePrompt: true,
    );
  }

  Widget _buildResistanceField({
    required ThemeData theme,
    required _RowConfig row,
    required _FieldKey key,
    required DirectionReadingSample? sample,
    required OrientationKind orientation,
    required bool hide,
    required int rowIndex,
    required int columnIndex,
  }) {
    final controller = _controllers[key];
    final focusNode = _focusNodes[key];
    if (controller == null || focusNode == null) {
      return const SizedBox.shrink();
    }

    final rank = _tabRanks[key] ?? 0;

    final invalidInput = !hide &&
        controller.text.trim().isNotEmpty &&
        _parseMaybeDouble(controller.text) == null;

    final decoration = resFieldDecoration().copyWith(
      hintText: hide ? 'Hidden' : null,
      suffixIcon: invalidInput
          ? Tooltip(
              message: 'Enter a numeric value, e.g. 132 or 132.5',
              waitDuration: const Duration(milliseconds: 400),
              child: Icon(
                Icons.error_outline,
                size: 16,
                color: theme.colorScheme.error,
              ),
            )
          : null,
    );

    focusNode.onKeyEvent =
        (node, event) => _handleResistanceKeyEvent(key, controller, event);

    final textField = FocusTraversalOrder(
      order: NumericFocusOrder(rank),
      child: Tooltip(
        message:
            'Apparent resistance ${orientation == OrientationKind.a ? "(N-S)" : "(W-E)"}',
        waitDuration: const Duration(milliseconds: 400),
        child: TextField(
          key: Key('row${rowIndex}_c${columnIndex}_primary'),
          controller: controller,
          focusNode: focusNode,
          enabled: !hide,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.top,
          minLines: 1,
          maxLines: 1,
          maxLengthEnforcement:
              MaxLengthEnforcement.truncateAfterCompositionEnds,
          inputFormatters: [
            LengthLimitingTextInputFormatter(6),
            FilteringTextInputFormatter.allow(
              RegExp(r'^[0-9]{0,4}(\.[0-9]{0,2})?$'),
            ),
          ],
          style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
                height: 1.1,
              ) ??
              const TextStyle(
                fontSize: 20,
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
          decoration: decoration,
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            if (_suppressNextSubmitted) {
              _suppressNextSubmitted = false;
              return;
            }
            _submitResistance(key, value);
          },
        ),
      ),
    );

    return SizedBox(
      height: kFieldH,
      child: textField,
    );
  }

  Widget _buildAccessoryIcon({
    required ThemeData theme,
    required Key key,
    required IconData icon,
    required String tooltip,
    bool selected = false,
    bool warning = false,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = theme.colorScheme;
    Color iconColor;
    if (warning) {
      iconColor = colorScheme.error;
    } else if (selected) {
      iconColor = colorScheme.primary;
    } else {
      iconColor = colorScheme.onSurfaceVariant;
    }
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: tinyIconButton(
        key: key,
        icon: icon,
        onPressed: onPressed,
        color: iconColor,
      ),
    );
  }

  Future<void> _showHistoryOverlay(
    _RowConfig row,
    OrientationKind orientation,
  ) async {
    final history = orientation == OrientationKind.a
        ? row.record.orientationA.samples
        : row.record.orientationB.samples;
    final orientationLabel = orientation == OrientationKind.a
        ? row.record.orientationA.label
        : row.record.orientationB.label;
    final dateFormat = DateFormat('MMM d, HH:mm');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'History — ${formatCompactValue(row.record.spacingFeet)} ft $orientationLabel',
          ),
          content: SizedBox(
            width: 320,
            child: history.isEmpty
                ? const Text('No prior measurements recorded.')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final sample = history[index];
                        final timestamp = dateFormat.format(
                          sample.timestamp.toLocal(),
                        );
                        final resistance = sample.resistanceOhm;
                        final formattedResistance = resistance == null
                            ? '—'
                            : '${formatCompactValue(resistance)} Ω';
                        final sd = sample.standardDeviationPercent;
                        final sdText = sd == null
                            ? 'SD —'
                            : 'SD ${formatCompactValue(sd, maxDecimals: 1)}%';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(timestamp),
                          subtitle: Text('$formattedResistance · $sdText'),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
    unawaited(
      widget.onShowHistory(
        row.record.spacingFeet,
        orientation,
      ),
    );
  }

  Widget _headerLabel(
    BuildContext context,
    String label, {
    TextStyle? style,
    String? tooltip,
    String? subLabel,
  }) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    final subText = subLabel == null
        ? null
        : Text(
            subLabel,
            textAlign: TextAlign.center,
            style: style?.copyWith(
              fontSize: (style.fontSize ?? 11) - 1,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );

    return SizedBox(
      height: _kTableHeaderHeight,
      child: Tooltip(
        message: tooltip ?? label,
        waitDuration: const Duration(milliseconds: 400),
        child: Align(
          alignment: Alignment.center,
          child: subText == null
              ? text
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    text,
                    const SizedBox(height: 2),
                    subText,
                  ],
                ),
        ),
      ),
    );
  }

  Map<_FieldKey, _FieldKey?> _buildTabOrder(List<_RowConfig> rows) {
    final orderedKeys = <_FieldKey>[];
    final orientationADesc = [...rows]
      ..sort((a, b) => b.record.spacingFeet.compareTo(a.record.spacingFeet));
    for (final row in orientationADesc) {
      orderedKeys.add(row.aResKey);
    }
    final orientationBAsc = [...rows]
      ..sort((a, b) => a.record.spacingFeet.compareTo(b.record.spacingFeet));
    for (final row in orientationBAsc) {
      orderedKeys.add(row.bResKey);
    }
    final forward = <_FieldKey, _FieldKey?>{};
    final reverse = <_FieldKey, _FieldKey?>{};
    _tabSequence = List.unmodifiable(orderedKeys);
    for (var i = 0; i < orderedKeys.length; i++) {
      final current = orderedKeys[i];
      final next = i + 1 < orderedKeys.length ? orderedKeys[i + 1] : null;
      final previous = i - 1 >= 0 ? orderedKeys[i - 1] : null;
      forward[current] = next;
      reverse[current] = previous;
    }
    _reverseTabOrder = reverse;
    return forward;
  }

  Map<_FieldKey, double> _buildTabRanks(List<_RowConfig> rows) {
    final ranks = <_FieldKey, double>{};
    var order = 0;
    void addKey(_FieldKey key) {
      ranks[key] = order.toDouble();
      order++;
    }

    final orientationADesc = [...rows]
      ..sort((a, b) => b.record.spacingFeet.compareTo(a.record.spacingFeet));
    for (final row in orientationADesc) {
      addKey(row.aResKey);
    }
    final orientationBAsc = [...rows]
      ..sort((a, b) => a.record.spacingFeet.compareTo(b.record.spacingFeet));
    for (final row in orientationBAsc) {
      addKey(row.bResKey);
    }
    return ranks;
  }

  Widget _buildSpacingCell(ThemeData theme, _RowConfig row) {
    final spacingText = formatCompactValue(row.record.spacingFeet);
    final spacingTooltip =
        'Inside: ${formatCompactValue(row.insideFeet)} ft (${formatMetersTooltip(row.insideMeters)} m)\n'
        'Outside: ${formatCompactValue(row.outsideFeet)} ft (${formatMetersTooltip(row.outsideMeters)} m)';

    return SizedBox(
      height: kRowH,
      child: Tooltip(
        message: spacingTooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              spacingText,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInterpretationFooter(
    ThemeData theme,
    _RowConfig row, {
    required double width,
  }) {
    final customNote = row.record.interpretation?.trim();
    final customNoteText = customNote ?? '';
    final autoNote = row.record.computeAutoInterpretation();
    final hasCustom = customNote != null && customNote.isNotEmpty;
    final tooltip =
        hasCustom ? customNoteText : 'Tap to record interpretation notes';
    final consistencySummary = hasCustom ? null : _consistencySummary(row);
    final subtitle =
        hasCustom ? customNoteText : consistencySummary ?? 'Add note';
    final subtitleStyle = hasCustom
        ? theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          )
        : consistencySummary != null
            ? theme.textTheme.labelSmall?.copyWith(
                color: _consistencyColor(autoNote, theme),
                fontWeight: FontWeight.w600,
              )
            : theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.secondary,
                fontStyle: FontStyle.italic,
              );

    return SizedBox(
      width: width,
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _editInterpretation(row),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              subtitle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: subtitleStyle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinsCell(ThemeData theme, _RowConfig row) {
    final inside = formatCompactValue(row.insideFeet);
    final outside = formatCompactValue(row.outsideFeet);
    final value = '$inside / $outside';
    final valid =
        RegExp(r'^[0-9]+(?:\.[0-9]+)? \/ [0-9]+(?:\.[0-9]+)?$').hasMatch(value);
    final tooltip =
        'Inside electrodes at ${formatMetersTooltip(row.insideMeters)} m\n'
        'Outside electrodes at ${formatMetersTooltip(row.outsideMeters)} m';

    return SizedBox(
      height: kRowH,
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: Align(
          alignment: Alignment.topCenter,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => unawaited(_showElectrodeDiagram(row)),
            onLongPress: () => unawaited(_showElectrodeDiagram(row)),
            child: Padding(
              padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.image_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  if (!valid) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showElectrodeDiagram(_RowConfig row) {
    final siteName = widget.site.displayName.isNotEmpty
        ? widget.site.displayName
        : widget.site.siteId;
    DiagramExportDirectoryBuilder? builder;
    final resolver = widget.diagramExportDirectoryBuilder;
    if (resolver != null) {
      builder = () => resolver(widget.project, widget.site);
    }
    return showElectrodeDiagramDialog(
      context: context,
      projectName: widget.project.projectName,
      siteName: siteName,
      aFt: row.record.spacingFeet,
      pinInFt: row.insideFeet,
      pinOutFt: row.outsideFeet,
      exportDirectoryBuilder: builder,
    );
  }

  String? _consistencySummary(_RowConfig row) {
    final autoNote = row.record.computeAutoInterpretation();
    if (autoNote == null) {
      return null;
    }
    final sdCandidates = <double>[];
    final a = row.sdValueA;
    final b = row.sdValueB;
    if (a != null) sdCandidates.add(a);
    if (b != null) sdCandidates.add(b);
    final worstSd = sdCandidates.isEmpty ? null : sdCandidates.reduce(math.max);
    final label = autoNote.startsWith('Good')
        ? 'Consistency: Good'
        : autoNote.startsWith('Minor')
            ? 'Consistency: Fair'
            : 'Consistency: High SD';
    if (worstSd == null) {
      return label;
    }
    return '$label • SD ${_formatSd(worstSd)}%';
  }

  Color _consistencyColor(String? autoNote, ThemeData theme) {
    if (autoNote == null) {
      return theme.colorScheme.secondary;
    }
    if (autoNote.contains('High SD')) {
      return theme.colorScheme.error;
    }
    if (autoNote.startsWith('Minor')) {
      return theme.colorScheme.tertiary;
    }
    return theme.colorScheme.secondary;
  }

  KeyEventResult _handleResistanceKeyEvent(
    _FieldKey key,
    TextEditingController controller,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      final isShiftPressed = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight);
      _suppressNextSubmitted = true;
      _submitResistance(
        key,
        controller.text,
        direction: isShiftPressed
            ? _AdvanceDirection.backward
            : _AdvanceDirection.forward,
      );
      Timer(const Duration(milliseconds: 80), () {
        _suppressNextSubmitted = false;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focusNodes[key]?.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _maybeShowTroubleshooter(String? raw) {
    final issue = TroubleshootOhmega.detect(raw);
    if (issue == null) {
      return;
    }
    if (_lastTroubleshooterCode == issue.code) {
      return;
    }
    _lastTroubleshooterCode = issue.code;
    if (!mounted) {
      return;
    }
    unawaited(
      showTroubleshooterBanner(
        context: context,
        issue: issue,
        onLogFixAttempt: widget.onLogTroubleshooter,
      ),
    );
  }

  void _editInterpretation(_RowConfig row) async {
    final existing = row.record.interpretation ?? '';
    final controller = TextEditingController(text: existing);
    final presets = SpacingRecord.interpretationPresets.toList()..sort();
    _lastTroubleshooterCode = null;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
              'Notes for ${formatCompactValue(row.record.spacingFeet)} ft'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Interpretation',
                  border: OutlineInputBorder(),
                ),
                onChanged: _maybeShowTroubleshooter,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in presets)
                    ActionChip(
                      label: Text(preset),
                      onPressed: () {
                        _maybeShowTroubleshooter(preset);
                        Navigator.of(context).pop(preset);
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      _maybeShowTroubleshooter(result);
      widget.onInterpretationChanged(row.record.spacingFeet, result);
    }
  }

  Widget _buildMetadata(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel =
        widget.saveStatusLabel ?? (widget.isSaving ? 'Saving…' : 'Saved');
    final statusChip = Tooltip(
      message: statusLabel,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isSaving)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              )
            else
              Icon(
                Icons.check_circle,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            const SizedBox(width: 6),
            Text(
              statusLabel,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );

    final metadataFields = <_MetadataField>[
      _MetadataField(child: _buildPowerField()),
      _MetadataField(
        child: _buildSoilDropdown(
          context,
          value: widget.site.soil,
          onChanged: (soil) => widget.onMetadataChanged(soil: soil),
        ),
      ),
      _MetadataField(
        child: _buildMoistureDropdown(
          context,
          value: widget.site.moisture,
          onChanged: (level) => widget.onMetadataChanged(moisture: level),
        ),
      ),
      _MetadataField(child: _buildGroundTemperatureField()),
      _MetadataField(child: _buildLocationCaptureField(context), flex: 2),
      ..._buildStacksControls(context),
    ];

    final fieldRowChildren = <Widget>[];
    for (var i = 0; i < metadataFields.length; i++) {
      final field = metadataFields[i];
      if (i > 0) {
        fieldRowChildren.add(const SizedBox(width: kDenseGap));
      }
      fieldRowChildren.add(
        Flexible(
          flex: field.flex,
          fit: FlexFit.tight,
          child: field.child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  widget.site.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: kDenseGap),
              statusChip,
            ],
          ),
          const SizedBox(height: kDenseGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: fieldRowChildren,
          ),
        ],
      ),
    );
  }

  Widget _buildPowerField() {
    return SizedBox(
      height: kFieldH,
      child: TextFormField(
        initialValue: widget.site.powerMilliAmps.toStringAsFixed(2),
        decoration: const InputDecoration(
          labelText: 'Power (mA)',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: kDenseFieldPadding,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        onFieldSubmitted: (value) {
          final parsed = double.tryParse(value);
          if (parsed != null) {
            widget.onMetadataChanged(power: parsed);
          }
        },
      ),
    );
  }

  Widget _buildGroundTemperatureField() {
    return SizedBox(
      height: kFieldH,
      child: TextFormField(
        initialValue: widget.site.groundTemperatureF.toStringAsFixed(1),
        decoration: const InputDecoration(
          labelText: 'Ground T (°F)',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: kDenseFieldPadding,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        onFieldSubmitted: (value) {
          final parsed = double.tryParse(value);
          if (parsed != null) {
            widget.onMetadataChanged(groundTemperatureF: parsed);
          }
        },
      ),
    );
  }

  Widget _buildLocationCaptureField(BuildContext context) {
    final state = ref.watch(locationCaptureProvider);
    final theme = Theme.of(context);
    final sessionResult = state.latest;
    final storedLocation = widget.site.location;
    final storedReading =
        storedLocation != null ? _readingFromLocation(storedLocation) : null;
    final sessionReading = sessionResult != null &&
            sessionResult.status == LocationStatus.success &&
            sessionResult.reading != null
        ? sessionResult.reading
        : null;
    final displayReading = sessionReading ?? storedReading;
    final busy = state.isLoading;

    final hasFix = displayReading != null;
    final coordinateLabel = hasFix
        ? '${displayReading.latitude.toStringAsFixed(4)}, '
            '${displayReading.longitude.toStringAsFixed(4)}'
        : 'No fix';
    final statusText = _locationStatusText(
      hasFix: hasFix,
      busy: busy,
      result: sessionResult,
      reading: displayReading,
    );
    final statusColor = _locationStatusColor(
      theme,
      hasFix: hasFix,
      busy: busy,
      result: sessionResult,
    );
    final showClear = storedLocation != null && !busy;
    final statusParts = <String>[
      coordinateLabel,
      if (statusText.isNotEmpty) statusText,
    ];
    final statusLabel =
        statusParts.where((value) => value.trim().isNotEmpty).join(' • ');

    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: kDenseButtonPadding,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      textStyle: theme.textTheme.labelSmall,
    );

    return SizedBox(
      height: kFieldH,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'GPS',
          isDense: true,
          contentPadding: kDenseFieldPadding,
          border: OutlineInputBorder(),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: busy ? null : () => _requestLocationCapture(context),
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      hasFix ? Icons.gps_fixed : Icons.gps_not_fixed,
                      size: 18,
                    ),
              label: const Text('GPS'),
            ),
            const SizedBox(width: kDenseGap),
            Expanded(
              child: Text(
                statusLabel.isEmpty ? coordinateLabel : statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor ?? theme.textTheme.labelSmall?.color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (showClear) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Clear stored GPS fix',
                waitDuration: const Duration(milliseconds: 400),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  onPressed: () => _clearLocation(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _requestLocationCapture(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(locationCaptureProvider.notifier);
    final result = await notifier.request();
    if (!mounted) {
      return;
    }
    final message = result.message;
    if (result.status == LocationStatus.success) {
      final reading = result.reading;
      if (reading == null) {
        return;
      }
      widget.onMetadataChanged(
        location: SiteLocation(
          latitude: reading.latitude,
          longitude: reading.longitude,
          altitudeMeters: reading.altitudeMeters,
          accuracyMeters: reading.accuracyMeters,
          capturedAt: reading.timestamp,
        ),
        updateLocation: true,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'GPS fix captured '
            '${reading.latitude.toStringAsFixed(5)}, '
            '${reading.longitude.toStringAsFixed(5)}',
          ),
        ),
      );
    } else if (message != null && message.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  void _clearLocation(BuildContext context) {
    widget.onMetadataChanged(location: null, updateLocation: true);
    ref.read(locationCaptureProvider.notifier).reset();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GPS fix cleared')),
    );
  }

  LocationReading _readingFromLocation(SiteLocation location) {
    return LocationReading(
      latitude: location.latitude,
      longitude: location.longitude,
      altitudeMeters: location.altitudeMeters,
      accuracyMeters: location.accuracyMeters,
      timestamp: location.capturedAt,
    );
  }

  String _locationStatusText({
    required bool hasFix,
    required bool busy,
    required LocationResult? result,
    required LocationReading? reading,
  }) {
    if (busy) {
      return '';
    }
    if (result != null && result.status != LocationStatus.success) {
      return result.message ?? _statusFallbackLabel(result.status);
    }
    return '';
  }

  Color? _locationStatusColor(
    ThemeData theme, {
    required bool hasFix,
    required bool busy,
    required LocationResult? result,
  }) {
    if (busy) {
      return theme.colorScheme.primary;
    }
    if (result != null && result.status != LocationStatus.success) {
      return theme.colorScheme.error;
    }
    if (hasFix) {
      return theme.colorScheme.primary;
    }
    return theme.colorScheme.outline;
  }

  String _statusFallbackLabel(LocationStatus status) {
    switch (status) {
      case LocationStatus.permissionDenied:
        return 'Permission denied';
      case LocationStatus.permissionsUnknown:
        return 'Permissions unavailable';
      case LocationStatus.servicesDisabled:
        return 'GPS disabled';
      case LocationStatus.timeout:
        return 'Timed out waiting for GPS';
      case LocationStatus.unavailable:
        return 'GPS unavailable';
      case LocationStatus.error:
        return 'GPS error';
      case LocationStatus.success:
        return 'GPS ready';
    }
  }

  Widget _buildSoilDropdown(
    BuildContext context, {
    required SoilType value,
    required ValueChanged<SoilType?> onChanged,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: kFieldH,
      child: DropdownButtonFormField<SoilType>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Soil',
          isDense: true,
          contentPadding: kDenseFieldPadding,
          border: OutlineInputBorder(),
        ),
        iconSize: 18,
        menuMaxHeight: 240,
        alignment: AlignmentDirectional.centerStart,
        style: theme.textTheme.bodySmall,
        items: SoilType.values
            .map(
              (soil) => DropdownMenuItem(
                value: soil,
                child: Text(
                  _soilShortLabel(soil),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildMoistureDropdown(
    BuildContext context, {
    required MoistureLevel value,
    required ValueChanged<MoistureLevel?> onChanged,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: kFieldH,
      child: DropdownButtonFormField<MoistureLevel>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Moisture',
          isDense: true,
          contentPadding: kDenseFieldPadding,
          border: OutlineInputBorder(),
        ),
        iconSize: 18,
        menuMaxHeight: 240,
        alignment: AlignmentDirectional.centerStart,
        style: theme.textTheme.bodySmall,
        items: MoistureLevel.values
            .map(
              (level) => DropdownMenuItem(
                value: level,
                child: Text(
                  level.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  List<_MetadataField> _buildStacksControls(BuildContext context) {
    final stacksLocked = widget.site.stacks == widget.projectDefaultStacks;
    if (stacksLocked) {
      return const [];
    }
    return [
      _MetadataField(
        child: SizedBox(
          height: kFieldH,
          child: TextFormField(
            initialValue: widget.site.stacks.toString(),
            decoration: const InputDecoration(
              labelText: 'Stacks',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: kDenseFieldPadding,
            ),
            keyboardType: const TextInputType.numberWithOptions(signed: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onFieldSubmitted: (value) {
              final parsed = _parseMaybeInt(value);
              if (parsed != null && parsed > 0) {
                widget.onMetadataChanged(stacks: parsed);
              }
            },
          ),
        ),
      ),
    ];
  }

  void _syncControllers(List<_FieldKey> keys, Map<_FieldKey, String> values) {
    final staleKeys =
        _controllers.keys.where((key) => !keys.contains(key)).toList();
    for (final key in staleKeys) {
      _controllers.remove(key)?.dispose();
      _focusNodes.remove(key)?.dispose();
    }

    for (final key in keys) {
      final text = values[key] ?? '';
      final controller = _controllers.putIfAbsent(
          key, () => TextEditingController(text: text));
      final focusNode =
          _focusNodes.putIfAbsent(key, () => _createFocusNode(key));
      if (!focusNode.hasFocus && controller.text != text) {
        controller.text = text;
      }
    }
  }

  FocusNode _createFocusNode(_FieldKey key) {
    final node = FocusNode();
    node.debugLabel = [
      key.orientation?.name ?? 'interpretation',
      key.type.name,
      key.spacingFeet.toStringAsFixed(1),
    ].join('-');
    node.addListener(() {
      if (!mounted) return;
      final orientation = key.orientation;
      if (node.hasFocus && orientation != null) {
        widget.onFocusChanged(key.spacingFeet, orientation);
      }
    });
    return node;
  }

  void _submitResistance(
    _FieldKey key,
    String value, {
    _AdvanceDirection direction = _AdvanceDirection.forward,
  }) {
    final parsed = _clampResistance(_parseMaybeDouble(value));
    final orientation = key.orientation;
    if (orientation == null) {
      return;
    }
    widget.onResistanceChanged(
      key.spacingFeet,
      orientation,
      parsed,
      null,
    );
    unawaited(_handleSdPrompt(
      key,
      direction: direction,
    ));
  }

  Future<void> _handleSdPrompt(
    _FieldKey key, {
    _AdvanceDirection direction = _AdvanceDirection.forward,
    bool forcePrompt = false,
  }) async {
    if (!forcePrompt && !_askForSd) {
      _advanceFocus(key, direction);
      return;
    }

    final row = _rowByField[key];
    if (row == null) {
      _advanceFocus(key, direction);
      return;
    }

    final orientation = key.orientation;
    if (orientation == null) {
      _advanceFocus(key, direction);
      return;
    }
    final sample = orientation == OrientationKind.a ? row.aSample : row.bSample;
    final sdValue = sample?.standardDeviationPercent;
    final label = orientation == OrientationKind.a
        ? row.record.orientationA.label
        : row.record.orientationB.label;

    final result = await _showSdPrompt(
      spacingFeet: row.record.spacingFeet,
      orientationLabel: label,
      initialValue: sdValue,
      allowSkip: !forcePrompt,
    );

    if (result != null) {
      if (result.sd != null) {
        final clamped = _clampSd(result.sd);
        widget.onSdChanged(key.spacingFeet, orientation, clamped);
      }
      if (_askForSd != result.askAgain) {
        setState(() {
          _askForSd = result.askAgain;
        });
        final prefs = _prefs;
        if (prefs != null) {
          await prefs.setAskForSd(result.askAgain);
        }
      }
    }

    _advanceFocus(key, direction);
  }

  Future<_SdPromptResult?> _showSdPrompt({
    required double spacingFeet,
    required String orientationLabel,
    required double? initialValue,
    required bool allowSkip,
  }) async {
    final controller = TextEditingController(
      text: initialValue == null ? '' : _formatSd(initialValue),
    );
    var parsed = _clampSd(initialValue);
    var dontAskAgain = !_askForSd;
    return showDialog<_SdPromptResult>(
      context: context,
      barrierDismissible: allowSkip,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'Enter SD (%) for ${formatCompactValue(spacingFeet)} ft $orientationLabel',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(_sdPromptRegExp),
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Optional',
                    ),
                    onChanged: (value) {
                      parsed = _clampSd(_parseMaybeDouble(value));
                      setState(() {});
                    },
                  ),
                  CheckboxListTile(
                    value: dontAskAgain,
                    onChanged: (value) {
                      setState(() {
                        dontAskAgain = value ?? false;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text("Don't ask again"),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                if (allowSkip)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      _SdPromptResult(sd: null, askAgain: !dontAskAgain),
                    ),
                    child: const Text('Skip'),
                  ),
                TextButton(
                  onPressed: parsed != null
                      ? () => Navigator.of(context).pop(
                            _SdPromptResult(
                              sd: parsed,
                              askAgain: !dontAskAgain,
                            ),
                          )
                      : null,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _advanceFocus(_FieldKey key, _AdvanceDirection direction) {
    switch (direction) {
      case _AdvanceDirection.forward:
        _moveFocusForward(key);
        break;
      case _AdvanceDirection.backward:
        _moveFocusBackward(key);
        break;
      case _AdvanceDirection.stay:
        break;
    }
  }

  void _moveFocusForward(_FieldKey key) {
    final next = _tabOrder[key];
    if (next == null) {
      _focusNodes[key]?.unfocus();
      return;
    }
    final nextNode = _focusNodes[next];
    if (nextNode != null) {
      FocusScope.of(context).requestFocus(nextNode);
    }
  }

  void _moveFocusBackward(_FieldKey key) {
    final previous = _reverseTabOrder[key];
    if (previous == null) {
      _focusNodes[key]?.unfocus();
      return;
    }
    final previousNode = _focusNodes[previous];
    if (previousNode != null) {
      FocusScope.of(context).requestFocus(previousNode);
    }
  }

  DirectionReadingSample? _latestSample(DirectionReadingHistory history) {
    if (history.samples.isEmpty) {
      return null;
    }
    return history.samples.last;
  }

  String _formatResistance(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return '';
    }
    return formatCompactValue(value);
  }

  String _formatSd(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return '';
    }
    final oneDecimal = (value * 10).roundToDouble() / 10;
    return formatCompactValue(oneDecimal, maxDecimals: 1);
  }

  double? _parseMaybeDouble(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }

  int? _parseMaybeInt(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  double? _clampResistance(double? value) {
    if (value == null) {
      return null;
    }
    return value.clamp(0.0, 9999.0).toDouble();
  }

  double? _clampSd(double? value) {
    if (value == null) {
      return null;
    }
    return value.clamp(0.0, 99.9).toDouble();
  }
}

class _SdPromptResult {
  const _SdPromptResult({required this.sd, required this.askAgain});

  final double? sd;
  final bool askAgain;
}

@visibleForTesting
class TablePanelDebugFixture extends StatelessWidget {
  const TablePanelDebugFixture({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime(2024, 1, 1, 12);
    final spacings = [5.0, 10.0, 15.0, 20.0]
        .map(
          (spacing) => SpacingRecord(
            spacingFeet: spacing,
            orientationA: DirectionReadingHistory(
              orientation: OrientationKind.a,
              label: 'N–S',
              samples: [
                DirectionReadingSample(
                  timestamp: now,
                  resistanceOhm: 100 + spacing,
                  standardDeviationPercent: 2.5,
                ),
              ],
            ),
            orientationB: DirectionReadingHistory(
              orientation: OrientationKind.b,
              label: 'W–E',
              samples: [
                DirectionReadingSample(
                  timestamp: now,
                  resistanceOhm: 95 + spacing,
                  standardDeviationPercent: 3.0,
                ),
              ],
            ),
          ),
        )
        .toList();

    final site = SiteRecord(
      siteId: 'debug-site',
      displayName: 'Debug Site',
      spacings: spacings,
    );
    final project = ProjectRecord.newProject(
      projectId: 'debug-project',
      projectName: 'Debug Project',
    );

    return ProviderScope(
      child: TablePanel(
        project: project,
        site: site,
        projectDefaultStacks: 4,
        showOutliers: true,
        onResistanceChanged: (_, __, ___, ____) {},
        onSdChanged: (_, __, ___) {},
        onInterpretationChanged: (_, __) {},
        onToggleBad: (_, __, ___) {},
        onMetadataChanged: ({
          double? power,
          int? stacks,
          SoilType? soil,
          MoistureLevel? moisture,
          double? groundTemperatureF,
          SiteLocation? location,
          bool? updateLocation,
        }) {},
        onShowHistory: (_, __) async {},
        onFocusChanged: (_, __) {},
        onLogTroubleshooter: (_) async {},
        isSaving: false,
        saveStatusLabel: 'Saved',
      ),
    );
  }
}

String _soilShortLabel(SoilType soil) {
  switch (soil) {
    case SoilType.unknown:
      return 'Unknown';
    case SoilType.clay:
      return 'Clay';
    case SoilType.sandy:
      return 'Sandy';
    case SoilType.gravelly:
      return 'Gravel';
    case SoilType.mixed:
      return 'Mixed';
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.builder,
  });

  @override
  final double minExtent;

  @override
  final double maxExtent;

  final Widget Function(BuildContext context, bool overlapsContent) builder;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return builder(context, overlapsContent);
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) => false;
}

class _StickyHeaderContainer extends StatelessWidget {
  const _StickyHeaderContainer({
    required this.child,
    required this.overlaps,
  });

  final Widget child;
  final bool overlaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: overlaps
            ? [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
