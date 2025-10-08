import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/calc.dart';
import '../../models/direction_reading.dart';
import '../../models/site.dart';
import '../../utils/format.dart';
import '../../state/prefs.dart';

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

  @visibleForTesting
  static const String sdPromptPattern = r'^[0-9]{0,2}(\.[0-9])?$';

  @override
  State<TablePanel> createState() => _TablePanelState();
}

enum _FieldType { resistance }

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

class _TablePanelState extends State<TablePanel> {
  final Map<_FieldKey, TextEditingController> _controllers = {};
  final Map<_FieldKey, FocusNode> _focusNodes = {};
  Map<_FieldKey, _FieldKey?> _tabOrder = {};
  final Map<_FieldKey, double> _tabRanks = {};
  final ScrollController _tableController = ScrollController();
  final Map<_FieldKey, _RowConfig> _rowByField = {};
  static final RegExp _sdPromptRegExp = RegExp(TablePanel.sdPromptPattern);
  TablePreferences? _prefs;
  bool _askForSd = true;
  List<_FieldKey> _tabSequence = const [];

  List<FocusNode> get tabOrderForTest {
    return [
      for (final key in _tabSequence)
        if (_focusNodes[key] != null) _focusNodes[key]!,
    ];
  }

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
            ? math.min(constraints.maxHeight, 460.0)
            : 460.0;
        final minWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 520.0;
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
                        dataRowMinHeight: 72,
                        dataRowMaxHeight: 84,
                        headingRowHeight: 40,
                        columnSpacing: 8,
                        horizontalMargin: 8,
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
                                  'Pins at (ft)',
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
                                  'Res $orientationALabel\n(Ω)',
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
                                  'Res $orientationBLabel\n(Ω)',
                                  textAlign: TextAlign.center,
                                ),
                              ),
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
      orderedKeys.add(row.aResKey);
    }
    final orientationBAsc = [...rows]
      ..sort((a, b) => a.record.spacingFeet.compareTo(b.record.spacingFeet));
    for (final row in orientationBAsc) {
      orderedKeys.add(row.bResKey);
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
    }
    final orientationBAsc = [...rows]
      ..sort((a, b) => a.record.spacingFeet.compareTo(b.record.spacingFeet));
    for (final row in orientationBAsc) {
      addKey(row.bResKey);
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
        DataCell(_buildPinsCell(theme, row)),
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
          _buildResistanceCell(
            theme,
            row,
            row.bResKey,
            row.bSample,
            OrientationKind.b,
            row.hideB,
          ),
        ),
      ],
    );
  }

  Widget _buildSpacingCell(ThemeData theme, _RowConfig row) {
    final spacingText = formatCompactValue(row.record.spacingFeet);
    final customNote = row.record.interpretation?.trim();
    final autoNote = row.record.computeAutoInterpretation();
    final hasCustom = customNote != null && customNote.isNotEmpty;
    final displayText = hasCustom
        ? customNote!
        : (autoNote != null ? '$autoNote (auto)' : 'Add note');
    final tooltip = hasCustom
        ? customNote!
        : (autoNote ?? 'Tap to record interpretation notes');
    return Center(
      child: SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message:
                  'Inside: ${formatCompactValue(row.insideFeet)} ft (${formatMetersTooltip(row.insideMeters)} m)\n'
                  'Outside: ${formatCompactValue(row.outsideFeet)} ft (${formatMetersTooltip(row.outsideMeters)} m)',
              child: Text(
                '$spacingText ft',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Tooltip(
              message: tooltip,
              child: GestureDetector(
                onTap: () => _editInterpretation(row),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Text(
                    displayText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasCustom
                          ? theme.colorScheme.primary
                          : theme.colorScheme.secondary,
                      fontStyle: hasCustom ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinsCell(ThemeData theme, _RowConfig row) {
    final inside = formatCompactValue(row.insideFeet);
    final outside = formatCompactValue(row.outsideFeet);
    final tooltip =
        'Inside electrodes at ${formatMetersTooltip(row.insideMeters)} m\n'
        'Outside electrodes at ${formatMetersTooltip(row.outsideMeters)} m';

    return Center(
      child: SizedBox(
        width: 120,
        child: Tooltip(
          message: tooltip,
          child: Text(
            '$inside / $outside',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
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
    final controller = _controllers[key];
    final focusNode = _focusNodes[key];
    if (controller == null || focusNode == null) {
      return const SizedBox.shrink();
    }

    final isBad = sample?.isBad ?? false;
    final rank = _tabRanks[key] ?? 0;
    final sdValue = orientation == OrientationKind.a ? row.sdValueA : row.sdValueB;
    final sdWarning =
        orientation == OrientationKind.a ? row.sdWarningA : row.sdWarningB;
    final sdText = hide
        ? 'Hidden'
        : sdValue == null
            ? '—'
            : '${_formatSd(sdValue)}%';
    final sdColor = sdWarning
        ? theme.colorScheme.error
        : theme.textTheme.labelSmall?.color ?? theme.colorScheme.onSurfaceVariant;
    final buttonStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
    );
    const controlDensity = VisualDensity(horizontal: -3, vertical: -3);

    return Center(
      child: Opacity(
        opacity: hide ? 0.45 : 1.0,
        child: SizedBox(
          width: 140,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: FocusTraversalOrder(
                  order: NumericFocusOrder(rank),
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
                        vertical: 6,
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
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: hide
                          ? null
                          : () => _handleSdPrompt(
                                key,
                                shouldMoveFocus: false,
                                forcePrompt: true,
                              ),
                      style: buttonStyle,
                      child: Text(
                        'SD $sdText',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: sdColor,
                          fontWeight:
                              sdWarning ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    iconSize: 18,
                    visualDensity: controlDensity,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: isBad
                        ? 'Marked bad — tap to clear flag'
                        : 'Mark reading bad',
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
                  IconButton(
                    iconSize: 18,
                    visualDensity: controlDensity,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Show edit history',
                    onPressed: () => widget.onShowHistory(
                      row.record.spacingFeet,
                      orientation,
                    ),
                    icon: const Icon(Icons.history),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editInterpretation(_RowConfig row) async {
    final existing = row.record.interpretation ?? '';
    final controller = TextEditingController(text: existing);
    final presets = SpacingRecord.interpretationPresets.toList()..sort();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Notes for ${formatCompactValue(row.record.spacingFeet)} ft'),
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
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in presets)
                    ActionChip(
                      label: Text(preset),
                      onPressed: () => Navigator.of(context).pop(preset),
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
      widget.onInterpretationChanged(row.record.spacingFeet, result);
    }
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
    unawaited(_handleSdPrompt(key, shouldMoveFocus: true));
  }

  Future<void> _handleSdPrompt(
    _FieldKey key, {
    bool shouldMoveFocus = true,
    bool forcePrompt = false,
  }) async {
    if (!forcePrompt && !_askForSd) {
      if (shouldMoveFocus) {
        _moveFocus(key);
      }
      return;
    }

    final row = _rowByField[key];
    if (row == null) {
      if (shouldMoveFocus) {
        _moveFocus(key);
      }
      return;
    }

    final orientation = key.orientation!;
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
        if (_prefs != null) {
          await _prefs!.setAskForSd(result.askAgain);
        }
      }
    }

    if (shouldMoveFocus) {
      _moveFocus(key);
    }
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
    try {
      return await showDialog<_SdPromptResult>(
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
    } finally {
      controller.dispose();
    }
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
