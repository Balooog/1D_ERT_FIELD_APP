import 'package:flutter/material.dart';

import '../../models/calc.dart';
import '../../models/direction_reading.dart';
import '../../models/site.dart';

class TablePanel extends StatelessWidget {
  const TablePanel({
    super.key,
    required this.site,
    required this.onResistanceChanged,
    required this.onSdChanged,
    required this.onNoteChanged,
    required this.onToggleBad,
    required this.onMetadataChanged,
    required this.onShowHistory,
    required this.onFocusChanged,
  });

  final SiteRecord site;
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
  final void Function(
    double spacingFt,
    OrientationKind orientation,
    String note,
  ) onNoteChanged;
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
  Widget build(BuildContext context) {
    final spacings = [...site.spacings]
      ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
    double? previousAverage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMetadata(context),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: spacings.length,
            itemBuilder: (context, index) {
              final record = spacings[index];
              final aLatest = record.orientationA.latest;
              final bLatest = record.orientationB.latest;
              final flags = evaluateQc(
                spacingFeet: record.spacingFeet,
                resistanceA: aLatest?.resistanceOhm,
                resistanceB: bLatest?.resistanceOhm,
                sdA: aLatest?.standardDeviationPercent,
                sdB: bLatest?.standardDeviationPercent,
                config: const QcConfig(),
                previousRho: previousAverage,
              );
              final avg = averageApparentResistivity(record.spacingFeet, [
                aLatest?.resistanceOhm,
                bLatest?.resistanceOhm,
              ]);
              previousAverage = avg ?? previousAverage;
              return _SpacingRow(
                record: record,
                flags: flags,
                onResistanceChanged: (orientation, resistance) =>
                    onResistanceChanged(
                  record.spacingFeet,
                  orientation,
                  resistance,
                  null,
                ),
                onSdChanged: (orientation, sd) => onSdChanged(
                  record.spacingFeet,
                  orientation,
                  sd,
                ),
                onNoteChanged: (orientation, note) => onNoteChanged(
                  record.spacingFeet,
                  orientation,
                  note,
                ),
                onToggleBad: (orientation, isBad) => onToggleBad(
                  record.spacingFeet,
                  orientation,
                  isBad,
                ),
                onShowHistory: (orientation) => onShowHistory(
                  record.spacingFeet,
                  orientation,
                ),
                onFocusChanged: (orientation) => onFocusChanged(
                  record.spacingFeet,
                  orientation,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMetadata(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            site.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: site.powerMilliAmps.toStringAsFixed(2),
                  decoration: const InputDecoration(
                    labelText: 'Power (mA)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onFieldSubmitted: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) {
                      onMetadataChanged(power: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: site.stacks.toString(),
                  decoration: const InputDecoration(labelText: 'Stacks'),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      onMetadataChanged(stacks: parsed);
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
                  initialValue: site.soil,
                  decoration: const InputDecoration(labelText: 'Soil'),
                  items: SoilType.values
                      .map(
                        (soil) => DropdownMenuItem(
                          value: soil,
                          child: Text(soil.label),
                        ),
                      )
                      .toList(),
                  onChanged: (soil) => onMetadataChanged(soil: soil),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<MoistureLevel>(
                  initialValue: site.moisture,
                  decoration: const InputDecoration(labelText: 'Moisture'),
                  items: MoistureLevel.values
                      .map(
                        (level) => DropdownMenuItem(
                          value: level,
                          child: Text(level.label),
                        ),
                      )
                      .toList(),
                  onChanged: (level) => onMetadataChanged(moisture: level),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpacingRow extends StatelessWidget {
  const _SpacingRow({
    required this.record,
    required this.flags,
    required this.onResistanceChanged,
    required this.onSdChanged,
    required this.onNoteChanged,
    required this.onToggleBad,
    required this.onShowHistory,
    required this.onFocusChanged,
  });

  final SpacingRecord record;
  final QcFlags flags;
  final void Function(OrientationKind orientation, double? resistance)
      onResistanceChanged;
  final void Function(OrientationKind orientation, double? sd) onSdChanged;
  final void Function(OrientationKind orientation, String note) onNoteChanged;
  final void Function(OrientationKind orientation, bool isBad) onToggleBad;
  final Future<void> Function(OrientationKind orientation) onShowHistory;
  final void Function(OrientationKind orientation) onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final insideFt = record.tapeInsideFeet;
    final outsideFt = record.tapeOutsideFeet;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'a = ${record.spacingFeet.toStringAsFixed(1)} ft',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message:
                      'Inside: ${insideFt.toStringAsFixed(1)} ft (${feetToMeters(insideFt).toStringAsFixed(2)} m)\n'
                      'Outside: ${outsideFt.toStringAsFixed(1)} ft (${feetToMeters(outsideFt).toStringAsFixed(2)} m)',
                  child: Chip(
                    avatar: const Icon(Icons.straighten),
                    label: Text(
                        'Inside ${insideFt.toStringAsFixed(1)} ft • Outside ${outsideFt.toStringAsFixed(1)} ft'),
                  ),
                ),
                const Spacer(),
                if (flags.outlier)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Chip(
                      label: const Text('Outlier'),
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                    ),
                  ),
                if (flags.highVariance)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Chip(
                      label: const Text('High %SD'),
                      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                    ),
                  ),
                if (flags.anisotropy)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Chip(
                      label: const Text('Anisotropy'),
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    ),
                  ),
                if (flags.jump)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Chip(
                      label: const Text('Jump'),
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _OrientationCell(
                    history: record.orientationA,
                    onFocus: () => onFocusChanged(OrientationKind.a),
                    onResistanceChanged: (value) =>
                        onResistanceChanged(OrientationKind.a, value),
                    onSdChanged: (value) => onSdChanged(OrientationKind.a, value),
                    onNoteChanged: (value) => onNoteChanged(OrientationKind.a, value),
                    onToggleBad: (value) => onToggleBad(OrientationKind.a, value),
                    onShowHistory: () => onShowHistory(OrientationKind.a),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OrientationCell(
                    history: record.orientationB,
                    onFocus: () => onFocusChanged(OrientationKind.b),
                    onResistanceChanged: (value) =>
                        onResistanceChanged(OrientationKind.b, value),
                    onSdChanged: (value) => onSdChanged(OrientationKind.b, value),
                    onNoteChanged: (value) => onNoteChanged(OrientationKind.b, value),
                    onToggleBad: (value) => onToggleBad(OrientationKind.b, value),
                    onShowHistory: () => onShowHistory(OrientationKind.b),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrientationCell extends StatefulWidget {
  const _OrientationCell({
    required this.history,
    required this.onFocus,
    required this.onResistanceChanged,
    required this.onSdChanged,
    required this.onNoteChanged,
    required this.onToggleBad,
    required this.onShowHistory,
  });

  final DirectionReadingHistory history;
  final VoidCallback onFocus;
  final ValueChanged<double?> onResistanceChanged;
  final ValueChanged<double?> onSdChanged;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<bool> onToggleBad;
  final Future<void> Function() onShowHistory;

  @override
  State<_OrientationCell> createState() => _OrientationCellState();
}

class _OrientationCellState extends State<_OrientationCell> {
  late TextEditingController _resistanceController;
  late TextEditingController _sdController;
  late FocusNode _resistanceFocus;
  late FocusNode _sdFocus;

  @override
  void initState() {
    super.initState();
    _resistanceController = TextEditingController(
      text: widget.history.latest?.resistanceOhm?.toStringAsFixed(2) ?? '',
    );
    _sdController = TextEditingController(
      text: widget.history.latest?.standardDeviationPercent?.toStringAsFixed(1) ?? '',
    );
    _resistanceFocus = FocusNode();
    _sdFocus = FocusNode();
    _resistanceFocus.addListener(_handleFocus);
    _sdFocus.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _OrientationCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.history.latest?.timestamp != oldWidget.history.latest?.timestamp) {
      _resistanceController.text =
          widget.history.latest?.resistanceOhm?.toStringAsFixed(2) ?? '';
      _sdController.text =
          widget.history.latest?.standardDeviationPercent?.toStringAsFixed(1) ?? '';
    }
  }

  @override
  void dispose() {
    _resistanceFocus.removeListener(_handleFocus);
    _sdFocus.removeListener(_handleFocus);
    _resistanceFocus.dispose();
    _sdFocus.dispose();
    _resistanceController.dispose();
    _sdController.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (_resistanceFocus.hasFocus || _sdFocus.hasFocus) {
      widget.onFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.history.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.history.label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _resistanceController,
          focusNode: _resistanceFocus,
          decoration: const InputDecoration(labelText: 'R (Ω)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onFieldSubmitted: (value) {
            widget.onResistanceChanged(double.tryParse(value));
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _sdController,
          focusNode: _sdFocus,
          decoration: const InputDecoration(labelText: '%SD'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onFieldSubmitted: (value) {
            widget.onSdChanged(double.tryParse(value));
          },
        ),
        Row(
          children: [
            Checkbox(
              value: latest?.isBad ?? false,
              onChanged: (value) {
                widget.onToggleBad(value ?? false);
              },
            ),
            const Text('Bad'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.note_alt),
              tooltip: 'Edit note',
              onPressed: () async {
                final controller = TextEditingController(text: latest?.note ?? '');
                final note = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Note — ${widget.history.label}'),
                    content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: 'Note'),
                      maxLines: 3,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(latest?.note ?? ''),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(controller.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (note != null) {
                  widget.onNoteChanged(note);
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Re-read history',
              onPressed: widget.onShowHistory,
            ),
          ],
        ),
      ],
    );
  }
}
