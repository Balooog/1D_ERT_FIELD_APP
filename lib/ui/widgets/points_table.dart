import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/inversion_model.dart';
import '../../models/spacing_point.dart';
import '../../services/qc_rules.dart';
import '../../state/providers.dart';
import '../../utils/distance_unit.dart';
import '../layout/sizing.dart';
import 'res_cluster.dart' show tinyIconButton;

class PointsTable extends ConsumerStatefulWidget {
  const PointsTable({
    super.key,
    required this.points,
    required this.inversion,
    required this.distanceUnit,
  });

  final List<SpacingPoint> points;
  final InversionModel inversion;
  final DistanceUnit distanceUnit;

  @override
  ConsumerState<PointsTable> createState() => _PointsTableState();
}

class _PointsTableState extends ConsumerState<PointsTable> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant PointsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _syncControllers();
    } else {
      // Notes could have been updated externally (e.g. load project).
      for (final point in widget.points) {
        final controller = _controllers[point.id];
        final focusNode = _focusNodes[point.id];
        final text = point.notes ?? '';
        if (controller != null &&
            focusNode != null &&
            !focusNode.hasFocus &&
            controller.text != text) {
          controller.text = text;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final existingIds = widget.points.map((p) => p.id).toSet();
    final keysToRemove =
        _controllers.keys.where((id) => !existingIds.contains(id)).toList();
    for (final id in keysToRemove) {
      _controllers.remove(id)?.dispose();
      _focusNodes.remove(id)?.dispose();
    }
    for (final point in widget.points) {
      _controllers.putIfAbsent(
          point.id, () => TextEditingController(text: point.notes ?? ''));
      _focusNodes.putIfAbsent(point.id, () => FocusNode());
      final focusNode = _focusNodes[point.id]!;
      final controller = _controllers[point.id]!;
      if (!focusNode.hasFocus && controller.text != (point.notes ?? '')) {
        controller.text = point.notes ?? '';
      }
    }
  }

  Text _cellText(
    String text, {
    TextAlign textAlign = TextAlign.start,
  }) {
    return Text(
      text,
      textAlign: textAlign,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final spacingLabel = widget.distanceUnit == DistanceUnit.feet ? 'ft' : 'm';
    final predicted = widget.inversion.predictedRho;

    final rows = <DataRow>[];
    for (var i = 0; i < widget.points.length; i++) {
      final point = widget.points[i];
      final controller = _controllers[point.id]!;
      final focusNode = _focusNodes[point.id]!;
      final predictedValue = (i < predicted.length) ? predicted[i] : null;
      final residual = predictedValue != null && predictedValue != 0
          ? (point.rhoAppOhmM - predictedValue) / predictedValue
          : 0.0;
      final coefficientOfVariation =
          point.sigmaRhoOhmM == null || point.rhoAppOhmM == 0
              ? null
              : (point.sigmaRhoOhmM! / point.rhoAppOhmM);
      final qaLevel = classifyPoint(
        residual: residual,
        coefficientOfVariation: coefficientOfVariation,
        point: point,
      );
      final qaColor = _qaColor(qaLevel);
      final rhoText =
          point.rhoAppOhmM.isFinite ? point.rhoAppOhmM.toStringAsFixed(2) : '—';
      final resistance = point.resistanceOhm;
      final sigma = point.sigmaRhoOhmM;
      final isExcluded = point.excluded;

      rows.add(
        DataRow(
          color: isExcluded
              ? WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4))
              : null,
          cells: [
            DataCell(_cellText('${i + 1}', textAlign: TextAlign.center)),
            DataCell(_cellText(point.arrayType.name)),
            DataCell(_cellText(point.direction.label)),
            DataCell(_cellText(
                widget.distanceUnit.formatSpacing(point.spacingMeters))),
            DataCell(_cellText(rhoText)),
            DataCell(_cellText(
                resistance.isFinite ? resistance.toStringAsFixed(2) : '—')),
            DataCell(_cellText(sigma != null ? sigma.toStringAsFixed(2) : '—')),
            DataCell(Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: qaColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: theme.colorScheme.onSurface, width: 0.5),
                ),
              ),
            )),
            DataCell(
              SizedBox(
                width: 180,
                height: kRowH,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Add note',
                  ),
                  textInputAction: TextInputAction.done,
                  textAlignVertical: TextAlignVertical.center,
                  minLines: 1,
                  maxLines: 1,
                  onSubmitted: (value) => _commitNote(point.id, value),
                  onEditingComplete: () =>
                      _commitNote(point.id, controller.text),
                ),
              ),
            ),
            DataCell(
              Tooltip(
                message: 'Delete point',
                waitDuration: const Duration(milliseconds: 400),
                child: tinyIconButton(
                  icon: Icons.delete_outline,
                  onPressed: () => ref
                      .read(spacingPointsProvider.notifier)
                      .removePoint(point.id),
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 720),
          child: DataTable(
            headingRowHeight: kRowH,
            columnSpacing: kGutter,
            headingTextStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              height: 1.1,
            ),
            dataRowMinHeight: kRowH,
            dataRowMaxHeight: kRowH,
            columns: [
              const DataColumn(
                label: Text(
                  '#',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(
                label: Text(
                  'Array',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(
                label: Text(
                  'Direction',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              DataColumn(
                label: Text(
                  'a-spacing ($spacingLabel)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(
                label: Text(
                  'ρₐ (Ω·m)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(
                label: Text(
                  'R (Ω)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(
                label: Text(
                  'σρ (Ω·m)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(
                label: Text(
                  'QA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(
                label: Text(
                  'Note',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const DataColumn(label: Text('')),
            ],
            rows: rows,
          ),
        ),
      ),
    );
  }

  void _commitNote(String id, String value) {
    final trimmed = value.trim();
    ref.read(spacingPointsProvider.notifier).updatePoint(
          id,
          (point) => point.copyWith(notes: trimmed.isEmpty ? null : trimmed),
        );
  }

  Color _qaColor(QaLevel level) {
    switch (level) {
      case QaLevel.green:
        return Colors.green;
      case QaLevel.yellow:
        return Colors.orange;
      case QaLevel.red:
        return Colors.red;
    }
  }
}
