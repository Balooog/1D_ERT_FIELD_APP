import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/calc.dart';
import '../../models/direction_reading.dart';
import '../../models/site.dart';
import '../../utils/format.dart';

class TablePanel extends StatefulWidget {
  const TablePanel({
    super.key,
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
  });

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
  }) onMetadataChanged;
  final Future<void> Function(
    double spacingFt,
    OrientationKind orientation,
  ) onShowHistory;
  final void Function(double spacingFt, OrientationKind orientation) onFocusChanged;

  @override
  State<TablePanel> createState() => _TablePanelState();
}

enum _FieldType { resistance, sd, interpretation }

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
    required this.insideFeet,
    required this.insideMeters,
    required this.outsideFeet,
    required this.outsideMeters,
    required this.aResKey,
    required this.aSdKey,
    required this.bResKey,
    required this.bSdKey,
    required this.interpretationKey,
  });

  final SpacingRecord record;
  final QcFlags flags;
  final DirectionReadingSample? aSample;
  final DirectionReadingSample? bSample;
  final bool hideA;
  final bool hideB;
  final bool sdWarningA;
  final bool sdWarningB;
  final double insideFeet;
  final double insideMeters;
  final double outsideFeet;
  final double outsideMeters;
  final _FieldKey aResKey;
  final _FieldKey aSdKey;
  final _FieldKey bResKey;
  final _FieldKey bSdKey;
  final _FieldKey interpretationKey;
}

class _TablePanelState extends State<TablePanel> {
  final Map<_FieldKey, TextEditingController> _controllers = {};
  final Map<_FieldKey, FocusNode> _focusNodes = {};
  Map<_FieldKey, _FieldKey?> _tabOrder = {};
  final Map<_FieldKey, double> _tabRanks = {};
  final ScrollController _tableController = ScrollController();
  List<_FieldKey> _tabSequence = const [];

  List<FocusNode> get tabOrderForTest {
    return [
      for (final key in _tabSequence)
        if (_focusNodes[key] != null) _focusNodes[key]!,
    ];
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

    final qcConfig = const QcConfig();
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
      final aSdKey = _FieldKey(
        spacingFeet: record.spacingFeet,
        orientation: OrientationKind.a,
        type: _FieldType.sd,
      );
      final bResKey = _FieldKey(
        spacingFeet: record.spacingFeet,
        orientation: OrientationKind.b,
        type: _FieldType.resistance,
      );
      final bSdKey = _FieldKey(
        spacingFeet: record.spacingFeet,
        orientation: OrientationKind.b,
        type: _FieldType.sd,
      );
      final interpretationKey = _FieldKey(
        spacingFeet: record.spacingFeet,
        orientation: null,
        type: _FieldType.interpretation,
      );

      requiredKeys
        ..add(aResKey)
        ..add(aSdKey)
        ..add(bResKey)
        ..add(bSdKey)
        ..add(interpretationKey);

      values[aResKey] = _formatResistance(aSample?.resistanceOhm);
      values[aSdKey] = _formatSd(aSample?.standardDeviationPercent);
      values[bResKey] = _formatResistance(bSample?.resistanceOhm);
      values[bSdKey] = _formatSd(bSample?.standardDeviationPercent);
      final interpretationText =
          record.interpretation ?? record.computeAutoInterpretation() ?? '';
      values[interpretationKey] = interpretationText;

      final hideA = !widget.showOutliers && (aSample?.isBad ?? false);
      final hideB = !widget.showOutliers && (bSample?.isBad ?? false);
      final sdWarningA =
          (aSample?.standardDeviationPercent ?? 0) > qcConfig.sdThresholdPercent;
      final sdWarningB =
          (bSample?.standardDeviationPercent ?? 0) > qcConfig.sdThresholdPercent;

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
          insideFeet: record.tapeInsideFeet,
          insideMeters: record.tapeInsideMeters,
          outsideFeet: record.tapeOutsideFeet,
          outsideMeters: record.tapeOutsideMeters,
          aResKey: aResKey,
          aSdKey: aSdKey,
          bResKey: bResKey,
          bSdKey: bSdKey,
          interpretationKey: interpretationKey,
        ),
      );
    }

    _syncControllers(requiredKeys, values);
    _tabOrder = _buildTabOrder(rowConfigs);
    _tabRanks
      ..clear()
      ..addAll(_buildTabRanks(rowConfigs));

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
            ? math.min(constraints.maxHeight, 420.0)
            : 420.0;
        final minWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 640.0;
        final headingStyle = theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          height: 1.1,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        final dataStyle = theme.textTheme.bodySmall?.copyWith(
          fontSize: 11,
          height: 1.1,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: maxHeight,
            child: Scrollbar(
              controller: _tableController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _tableController,
                primary: false,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minWidth),
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: DataTable(
                        headingTextStyle: headingStyle,
                        dataTextStyle: dataStyle,
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 44,
                        headingRowHeight: 40,
                        columnSpacing: 12,
                        horizontalMargin: 12,
                        columns: [
                          const DataColumn(
                            label: SizedBox(
                              height: 40,
                              child: Center(child: Text('a-spacing (ft)')),
                            ),
                          ),
                          const DataColumn(
                            label: SizedBox(
                              height: 40,
                              child: Center(
                                child: Text(
                                  'Inside / Outside (ft)',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: SizedBox(
                              height: 40,
                              child: Center(
                                child: Text(
                                  'Res $orientationALabel (Ω)',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          const DataColumn(
                            label: SizedBox(
                              height: 40,
                              child: Center(child: Text('SD (%)')),
                            ),
                          ),
                          DataColumn(
                            label: SizedBox(
                              height: 40,
                              child: Center(
                                child: Text(
                                  'Res $orientationBLabel (Ω)',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          const DataColumn(
                            label: SizedBox(
                              height: 40,
                              child: Center(child: Text('SD (%)')),
                            ),
                          ),
                          const DataColumn(
                            label: SizedBox(
                              height: 40,
                              child: Center(child: Text('Interpretation')),
                            ),
                          ),
                        ],
                        rows: rows
                            .map((row) => _buildDataRow(context, theme, row))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Map<_FieldKey, _FieldKey?> _buildTabOrder(List<_RowConfig> rows) {
    final orderedKeys = <_FieldKey>[];
    final orientationADesc = [...rows]
      ..sort((a, b) => b.record.spacingFeet.compareTo(a.record.spacingFeet));
    for (final row in orientationADesc) {
      orderedKeys
        ..add(row.aResKey)
        ..add(row.aSdKey);
    }
    final orientationBAsc = [...rows]
      ..sort((a, b) => a.record.spacingFeet.compareTo(b.record.spacingFeet));
    for (final row in orientationBAsc) {
      orderedKeys
        ..add(row.bResKey)
        ..add(row.bSdKey);
    }
    for (final row in rows) {
      orderedKeys.add(row.interpretationKey);
    }
    final map = <_FieldKey, _FieldKey?>{};
    _tabSequence = List.unmodifiable(orderedKeys);
    for (var i = 0; i < orderedKeys.length; i++) {
      final current = orderedKeys[i];
      final next = i + 1 < orderedKeys.length ? orderedKeys[i + 1] : null;
      map[current] = next;
    }
    return map;
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
      addKey(row.aSdKey);
    }
    final orientationBAsc = [...rows]
      ..sort((a, b) => a.record.spacingFeet.compareTo(b.record.spacingFeet));
    for (final row in orientationBAsc) {
      addKey(row.bResKey);
      addKey(row.bSdKey);
    }
    for (final row in rows) {
      addKey(row.interpretationKey);
    }
    return ranks;
  }

  DataRow _buildDataRow(BuildContext context, ThemeData theme, _RowConfig row) {
    final color = row.flags.outlier
        ? WidgetStatePropertyAll(
            theme.colorScheme.errorContainer
                .withValues(alpha: (0.35 * 255).round().toDouble()),
          )
        : null;

    return DataRow(
      color: color,
      cells: [
        DataCell(_buildSpacingCell(theme, row)),
        DataCell(_buildTapeCell(theme, row)),
        DataCell(
          _buildResistanceCell(
            theme,
            row,
            row.aResKey,
            row.aSample,
            OrientationKind.a,
            row.hideA,
          ),
        ),
        DataCell(
          _buildSdCell(
            theme,
            row,
            row.aSdKey,
            row.hideA,
            row.sdWarningA,
          ),
        ),
        DataCell(
          _buildResistanceCell(
            theme,
            row,
            row.bResKey,
            row.bSample,
            OrientationKind.b,
            row.hideB,
          ),
        ),
        DataCell(
          _buildSdCell(
            theme,
            row,
            row.bSdKey,
            row.hideB,
            row.sdWarningB,
          ),
        ),
        DataCell(_buildInterpretationCell(row)),
      ],
    );
  }

  Widget _buildSpacingCell(ThemeData theme, _RowConfig row) {
    final spacingText = formatCompactValue(row.record.spacingFeet);
    final tooltip =
        'Inside: ${formatCompactValue(row.insideFeet)} ft (${formatMetersTooltip(row.insideMeters)} m)\n'
        'Outside: ${formatCompactValue(row.outsideFeet)} ft (${formatMetersTooltip(row.outsideMeters)} m)';

    return Center(
      child: Tooltip(
        message: tooltip,
        child: Text(
          '$spacingText ft',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildTapeCell(ThemeData theme, _RowConfig row) {
    return Center(
      child: _compactCell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Inside ${formatCompactValue(row.insideFeet)} ft',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
            ),
            Text(
              'Outside ${formatCompactValue(row.outsideFeet)} ft',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildResistanceCell(
    ThemeData theme,
    _RowConfig row,
    _FieldKey key,
    DirectionReadingSample? sample,
    OrientationKind orientation,
    bool hide,
  ) {
    final controller = _controllers[key]!;
    final focusNode = _focusNodes[key]!;
    final isBad = sample?.isBad ?? false;
    final label = orientation == OrientationKind.a
        ? row.record.orientationA.label
        : row.record.orientationB.label;
    final showLabel = controller.text.trim().isNotEmpty || focusNode.hasFocus;
    final rank = _tabRanks[key] ?? 0;

    return Center(
      child: Opacity(
        opacity: hide ? 0.45 : 1.0,
        child: _compactCell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 96,
                    child: FocusTraversalOrder(
                      order: NumericFocusOrder(rank * 2),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !hide,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        textAlign: TextAlign.right,
                        maxLengthEnforcement:
                            MaxLengthEnforcement.truncateAfterCompositionEnds,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(6),
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^[0-9]{0,4}(\.[0-9]{0,2})?$'),
                          ),
                        ],
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.1,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 6,
                          ),
                          hintText: hide ? 'Hidden' : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (value) => _submitResistance(key, value),
                        onEditingComplete: () =>
                            _submitResistance(key, controller.text),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: isBad
                        ? 'Marked bad — tap to clear flag'
                        : 'Mark reading bad',
                    child: IconButton(
                      iconSize: 18,
                      visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: hide
                          ? null
                          : () => widget.onToggleBad(
                                row.record.spacingFeet,
                                orientation,
                                !isBad,
                              ),
                      icon: Icon(
                        isBad ? Icons.flag : Icons.outlined_flag,
                        color: isBad
                            ? theme.colorScheme.error
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Show edit history',
                    child: IconButton(
                      iconSize: 18,
                      visualDensity:
                          const VisualDensity(horizontal: -4, vertical: -4),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => widget.onShowHistory(
                        row.record.spacingFeet,
                        orientation,
                      ),
                      icon: const Icon(Icons.history),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSdCell(
    ThemeData theme,
    _RowConfig row,
    _FieldKey key,
    bool hide,
    bool warning,
  ) {
    final controller = _controllers[key]!;
    final focusNode = _focusNodes[key]!;
    final showLabel = controller.text.trim().isNotEmpty || focusNode.hasFocus;
    final rank = _tabRanks[key] ?? 0;
    return Center(
      child: Opacity(
        opacity: hide ? 0.45 : 1.0,
        child: _compactCell(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'SD',
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              SizedBox(
                width: 64,
                child: FocusTraversalOrder(
                  order: NumericFocusOrder(rank * 2 + 1),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !hide,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    textAlign: TextAlign.right,
                    maxLengthEnforcement:
                        MaxLengthEnforcement.truncateAfterCompositionEnds,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(4),
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^[0-9]{0,2}(\.[0-9])?$'),
                      ),
                    ],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.1,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 6,
                      ),
                      suffixText: warning ? '!' : null,
                      suffixStyle: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                      hintText: hide ? 'Hidden' : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (value) => _submitSd(key, value),
                    onEditingComplete: () => _submitSd(key, controller.text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactCell({
    required Widget child,
    double width = 140,
    double height = 44,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1, minHeight: 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildInterpretationCell(_RowConfig row) {
    final controller = _controllers[row.interpretationKey]!;
    final focusNode = _focusNodes[row.interpretationKey]!;
    final rank = _tabRanks[row.interpretationKey] ?? _tabRanks.length.toDouble();
    return Center(
      child: FocusTraversalOrder(
        order: NumericFocusOrder(rank * 2 + 1),
        child: SizedBox(
          width: 200,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 2,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Notes',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            ),
            onSubmitted: (value) =>
                widget.onInterpretationChanged(row.record.spacingFeet, value),
            onEditingComplete: () => widget.onInterpretationChanged(
              row.record.spacingFeet,
              controller.text,
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildMetadata(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.site.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: widget.site.powerMilliAmps.toStringAsFixed(2),
                  decoration: const InputDecoration(
                    labelText: 'Power (mA)',
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) {
                      widget.onMetadataChanged(power: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              ..._buildStacksControls(context),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SoilType>(
                  initialValue: widget.site.soil,
                  decoration: const InputDecoration(
                    labelText: 'Soil',
                    isDense: true,
                  ),
                  isDense: true,
                  iconSize: 18,
                  menuMaxHeight: 240,
                  alignment: AlignmentDirectional.centerStart,
                  style: theme.textTheme.bodySmall,
                  items: SoilType.values
                      .map(
                        (soil) => DropdownMenuItem(
                          value: soil,
                          child: Text(
                            soil.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (soil) => widget.onMetadataChanged(soil: soil),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<MoistureLevel>(
                  initialValue: widget.site.moisture,
                  decoration: const InputDecoration(
                    labelText: 'Moisture',
                    isDense: true,
                  ),
                  isDense: true,
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
                  onChanged: (level) => widget.onMetadataChanged(moisture: level),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStacksControls(BuildContext context) {
    final theme = Theme.of(context);
    final stacksLocked = widget.site.stacks == widget.projectDefaultStacks;
    if (stacksLocked) {
      return [
        Tooltip(
          message: 'Stacks locked to project default',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  'Project default: ${widget.projectDefaultStacks} stacks',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SizedBox(
        width: 96,
        child: TextFormField(
          initialValue: widget.site.stacks.toString(),
          decoration: const InputDecoration(labelText: 'Stacks'),
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
    ];
  }
  void _syncControllers(List<_FieldKey> keys, Map<_FieldKey, String> values) {
    final staleKeys = _controllers.keys.where((key) => !keys.contains(key)).toList();
    for (final key in staleKeys) {
      _controllers.remove(key)?.dispose();
      _focusNodes.remove(key)?.dispose();
    }

    for (final key in keys) {
      final text = values[key] ?? '';
      final controller =
          _controllers.putIfAbsent(key, () => TextEditingController(text: text));
      final focusNode = _focusNodes.putIfAbsent(key, () => _createFocusNode(key));
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
      setState(() {});
      if (node.hasFocus && key.orientation != null) {
        widget.onFocusChanged(key.spacingFeet, key.orientation!);
      }
    });
    return node;
  }

  void _submitResistance(_FieldKey key, String value) {
    final parsed = _clampResistance(_parseMaybeDouble(value));
    widget.onResistanceChanged(
      key.spacingFeet,
      key.orientation!,
      parsed,
      null,
    );
    _moveFocus(key);
  }

  void _submitSd(_FieldKey key, String value) {
    final parsed = _clampSd(_parseMaybeDouble(value));
    widget.onSdChanged(
      key.spacingFeet,
      key.orientation!,
      parsed,
    );
    _moveFocus(key);
  }

  void _moveFocus(_FieldKey key) {
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

  DirectionReadingSample? _latestSample(DirectionReadingHistory history) {
    if (history.samples.isEmpty) {
      return null;
    }
    return history.samples.last;
  }

  String _formatDistance(double value) {
    return formatCompactValue(value);
  }

  String _formatMeters(double value) {
    return formatMetersTooltip(value);
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
