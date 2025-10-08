import 'package:flutter/material.dart';

import '../../models/calc.dart';
import '../../models/direction_reading.dart';
import '../../models/site.dart';

class TablePanel extends StatefulWidget {
  const TablePanel({
    super.key,
    required this.site,
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

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
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
    final focusOrder = <_FieldKey>[];
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

      focusOrder
        ..add(aResKey)
        ..add(aSdKey)
        ..add(bResKey)
        ..add(bSdKey);

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
    _tabOrder = {};
    for (var i = 0; i < focusOrder.length; i++) {
      final current = focusOrder[i];
      final next = i + 1 < focusOrder.length ? focusOrder[i + 1] : null;
      _tabOrder[current] = next;
    }

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
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle:
                theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            dataRowMinHeight: 76,
            dataRowMaxHeight: 120,
            columns: [
              const DataColumn(label: Text('a-spacing (ft)')),
              DataColumn(label: Text('Res $orientationALabel (Ω)')),
              const DataColumn(label: Text('SD (%)')),
              DataColumn(label: Text('Res $orientationBLabel (Ω)')),
              const DataColumn(label: Text('SD (%)')),
              const DataColumn(label: Text('Interpretation')),
            ],
            rows: rows.map((row) => _buildDataRow(context, theme, row)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(BuildContext context, ThemeData theme, _RowConfig row) {
    final color = row.flags.outlier
        ? MaterialStatePropertyAll(
            theme.colorScheme.errorContainer.withOpacity(0.35),
          )
        : null;

    return DataRow(
      color: color,
      cells: [
        DataCell(_buildSpacingCell(theme, row)),
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
    final spacingText = row.record.spacingFeet.toStringAsFixed(2);
    final tooltip =
        'Inside: ${row.insideFeet.toStringAsFixed(2)} ft (${row.insideMeters.toStringAsFixed(2)} m)\n'
        'Outside: ${row.outsideFeet.toStringAsFixed(2)} ft (${row.outsideMeters.toStringAsFixed(2)} m)';

    return Tooltip(
      message: tooltip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$spacingText ft', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Inside ${row.insideFeet.toStringAsFixed(2)} ft • Outside ${row.outsideFeet.toStringAsFixed(2)} ft',
            style: theme.textTheme.bodySmall,
          ),
        ],
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

    return Opacity(
      opacity: hide ? 0.45 : 1.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !hide,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: hide ? 'Hidden while outliers hidden' : null,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (value) => _submitResistance(key, value),
            onEditingComplete: () => _submitResistance(key, controller.text),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: isBad
                    ? 'Marked bad — tap to clear flag'
                    : 'Mark reading bad',
                child: Checkbox(
                  value: isBad,
                  onChanged: sample == null
                      ? null
                      : (value) => widget.onToggleBad(
                            row.record.spacingFeet,
                            orientation,
                            value ?? false,
                          ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.history, size: 18),
                tooltip: 'Show $label history',
                onPressed: () => widget.onShowHistory(
                  row.record.spacingFeet,
                  orientation,
                ),
              ),
            ],
          ),
          if (isBad)
            Text(
              'Marked bad',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
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
    return Opacity(
      opacity: hide ? 0.45 : 1.0,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: !hide,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          suffixText: warning ? '⚠' : null,
          suffixStyle: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        onSubmitted: (value) => _submitSd(key, value),
        onEditingComplete: () => _submitSd(key, controller.text),
      ),
    );
  }

  Widget _buildInterpretationCell(_RowConfig row) {
    final controller = _controllers[row.interpretationKey]!;
    final focusNode = _focusNodes[row.interpretationKey]!;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: 2,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        hintText: 'Add interpretation notes',
      ),
      onSubmitted: (value) =>
          widget.onInterpretationChanged(row.record.spacingFeet, value),
      onEditingComplete: () => widget.onInterpretationChanged(
        row.record.spacingFeet,
        controller.text,
      ),
    );
  }
  Widget _buildMetadata(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.site.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: widget.site.powerMilliAmps.toStringAsFixed(2),
                  decoration: const InputDecoration(
                    labelText: 'Power (mA)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onFieldSubmitted: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) {
                      widget.onMetadataChanged(power: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: widget.site.stacks.toString(),
                  decoration: const InputDecoration(labelText: 'Stacks'),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      widget.onMetadataChanged(stacks: parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<SoilType>(
                  value: widget.site.soil,
                  decoration: const InputDecoration(labelText: 'Soil'),
                  items: SoilType.values
                      .map(
                        (soil) => DropdownMenuItem(
                          value: soil,
                          child: Text(soil.label),
                        ),
                      )
                      .toList(),
                  onChanged: (soil) => widget.onMetadataChanged(soil: soil),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<MoistureLevel>(
                  value: widget.site.moisture,
                  decoration: const InputDecoration(labelText: 'Moisture'),
                  items: MoistureLevel.values
                      .map(
                        (level) => DropdownMenuItem(
                          value: level,
                          child: Text(level.label),
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
    if (key.orientation != null) {
      node.addListener(() {
        if (node.hasFocus) {
          widget.onFocusChanged(key.spacingFeet, key.orientation!);
        }
      });
    }
    return node;
  }

  void _submitResistance(_FieldKey key, String value) {
    final parsed = double.tryParse(value);
    widget.onResistanceChanged(
      key.spacingFeet,
      key.orientation!,
      parsed,
      null,
    );
    _moveFocus(key);
  }

  void _submitSd(_FieldKey key, String value) {
    final parsed = double.tryParse(value);
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

  String _formatResistance(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return '';
    }
    return value.toStringAsFixed(2);
  }

  String _formatSd(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return '';
    }
    return value.toStringAsFixed(1);
  }
}
