import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/enums.dart';
import '../../models/spacing_point.dart';
import '../../services/csv_io.dart';
import '../../services/geometry_factors.dart' as geom;
import '../../state/providers.dart';
import '../widgets/header_badges.dart';
import '../widgets/residual_strip.dart';
import '../widgets/sounding_chart.dart';
import '../widgets/telemetry_panel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(spacingPointsProvider);
    final inversion = ref.watch(inversionProvider);
    final qaSummary = ref.watch(qaSummaryProvider);
    final isSimulating = ref.watch(simulationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ResiCheck'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenu(value, context, ref),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'import', child: Text('Import CSV (sample)')),
              PopupMenuItem(value: 'export', child: Text('Export CSV')),
              PopupMenuItem(value: 'settings', child: Text('Settings (stub)')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            HeaderBadges(summary: qaSummary),
            Expanded(
              child: points.isEmpty
                  ? const Center(
                      child: Text('No data yet. Import a CSV or start simulation.'),
                    )
                  : SoundingChart(points: points, inversion: inversion),
            ),
            ResidualStrip(points: points, inversion: inversion),
            TelemetryPanel(state: ref.watch(telemetryProvider)),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Point'),
                onPressed: () => _showAddPointDialog(context, ref),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.replay),
                label: const Text('Re-read'),
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flag),
                label: const Text('Mark bad'),
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                icon: Icon(isSimulating ? Icons.stop : Icons.play_arrow),
                label: Text(isSimulating ? 'Stop' : 'Simulate'),
                onPressed: () => ref.read(simulationControllerProvider.notifier).toggle(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenu(String value, BuildContext context, WidgetRef ref) async {
    switch (value) {
      case 'import':
        final bundle = rootBundle;
        final data = await bundle.loadString('assets/samples/sample_wenner.csv');
        final file = File('${Directory.systemTemp.path}/sample_wenner.csv');
        await file.writeAsString(data);
        final points = await CsvIoService().readFile(file);
        ref.read(spacingPointsProvider.notifier).setPoints(points);
        break;
      case 'export':
        final directory = Directory.systemTemp.path;
        final file = await getDefaultExportFile(directory);
        await CsvIoService().writeFile(file, ref.read(spacingPointsProvider));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported to ${file.path}')),
          );
        }
        break;
      case 'settings':
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Settings'),
              content: const Text('Settings are not yet implemented.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
              ],
            ),
          );
        }
    }
  }

  Future<void> _showAddPointDialog(BuildContext context, WidgetRef ref) async {
    final aFeetController = TextEditingController();
    final rhoController = TextEditingController();
    final resistanceController = TextEditingController();
    final sigmaRhoController = TextEditingController();
    final notesController = TextEditingController();
    final voltageController = TextEditingController();
    final currentController = TextEditingController();
    ArrayType arrayType = ArrayType.wenner;
    SoundingDirection direction = SoundingDirection.ns;
    bool advancedExpanded = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            double? parseValue(TextEditingController controller) {
              final text = controller.text.trim();
              if (text.isEmpty) return null;
              return double.tryParse(text);
            }

            final spacingFeet = parseValue(aFeetController);
            final spacingMeters = spacingFeet != null ? feetToMeters(spacingFeet) : null;
            final geometryFactor = spacingMeters != null && spacingMeters > 0
                ? _geometryFactorForArray(arrayType, spacingMeters)
                : null;
            final rhoInput = parseValue(rhoController);
            final resistanceInput = parseValue(resistanceController);
            final sigmaRho = parseValue(sigmaRhoController);
            final voltage = parseValue(voltageController);
            final current = parseValue(currentController);

            final hasRho = rhoInput != null && rhoInput > 0;
            final hasResistance = resistanceInput != null && resistanceInput > 0;

            double? resolvedRhoValue = hasRho ? rhoInput : null;
            double? resolvedResistanceValue;
            if (hasRho && geometryFactor != null && geometryFactor > 0) {
              resolvedResistanceValue = rhoInput! / geometryFactor;
            } else if (!hasRho && hasResistance && geometryFactor != null && geometryFactor > 0) {
              resolvedResistanceValue = resistanceInput;
              resolvedRhoValue = resistanceInput! * geometryFactor;
            }

            final computedResistance =
                hasRho && geometryFactor != null && geometryFactor > 0 ? rhoInput! / geometryFactor : null;
            final computedRho = !hasRho && hasResistance && geometryFactor != null && geometryFactor > 0
                ? resistanceInput! * geometryFactor
                : null;

            final rhoFromVi = (voltage != null && current != null && current != 0 && spacingMeters != null)
                ? _geometryFactorForArray(arrayType, spacingMeters) * (voltage / current)
                : null;
            final rhoDiffPercent = (resolvedRhoValue != null && rhoFromVi != null && resolvedRhoValue != 0)
                ? ((rhoFromVi - resolvedRhoValue).abs() / resolvedRhoValue) * 100
                : null;

            final hasVoltage = voltageController.text.trim().isNotEmpty;
            final hasCurrent = currentController.text.trim().isNotEmpty;
            final bool baseValid = spacingFeet != null &&
                spacingFeet > 0 &&
                resolvedRhoValue != null &&
                resolvedRhoValue > 0 &&
                (!hasResistance || geometryFactor != null && geometryFactor > 0);
            final bool sigmaValid = sigmaRho == null || sigmaRho >= 0;
            final bool advancedPaired = hasVoltage == hasCurrent;
            final bool advancedCurrentValid = current == null || current > 0;
            final bool isAddEnabled = baseValid && sigmaValid && advancedPaired && advancedCurrentValid;

            return AlertDialog(
              title: const Text('Add manual point'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<ArrayType>(
                            value: arrayType,
                            decoration: const InputDecoration(labelText: 'Array'),
                            onChanged: (value) => setState(() => arrayType = value ?? arrayType),
                            items: const [
                              DropdownMenuItem(value: ArrayType.wenner, child: Text('Wenner')),
                              DropdownMenuItem(value: ArrayType.schlumberger, child: Text('Schlumberger')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<SoundingDirection>(
                            value: direction,
                            decoration: const InputDecoration(labelText: 'Direction'),
                            onChanged: (value) => setState(() => direction = value ?? direction),
                            items: SoundingDirection.values
                                .map((dir) => DropdownMenuItem(value: dir, child: Text(dir.label)))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.paste),
                        label: const Text('Bulk paste'),
                        onPressed: () async {
                          final newDirection = await _showBulkPasteSheet(context, ref, arrayType, direction);
                          if (newDirection != null) {
                            setState(() => direction = newDirection);
                          }
                        },
                      ),
                    ),
                    TextField(
                      controller: aFeetController,
                      decoration: const InputDecoration(labelText: 'A-spacing (ft)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (spacingMeters != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '≈ ${spacingMeters.toStringAsFixed(3)} m',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rhoController,
                      decoration: const InputDecoration(
                        labelText: 'Apparent ρ (Ω·m)',
                        helperText: 'Leave blank if you only logged apparent R',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (computedResistance != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Computed R ≈ ${computedResistance.toStringAsFixed(3)} Ω',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: resistanceController,
                      decoration: const InputDecoration(
                        labelText: 'Apparent R (Ω)',
                        helperText: 'Provide if you logged resistance instead of ρ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (computedRho != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Computed ρ ≈ ${computedRho.toStringAsFixed(2)} Ω·m',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ),
                    if (!hasRho && !hasResistance)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Enter apparent ρ or apparent R.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sigmaRhoController,
                      decoration: const InputDecoration(labelText: 'Std dev σρ (Ω·m, optional)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'Notes / tag (optional)'),
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 12),
                    if (resolvedRhoValue != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Preview ρ: ${resolvedRhoValue.toStringAsFixed(2)} Ω·m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (resolvedResistanceValue != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Preview R: ${resolvedResistanceValue.toStringAsFixed(3)} Ω',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (rhoDiffPercent != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Δρ vs V/I: ${rhoDiffPercent.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: rhoDiffPercent > SpacingPoint.rhoQaThresholdPercent
                                    ? Colors.orange
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: const Text('Advanced'),
                      initiallyExpanded: advancedExpanded,
                      onExpansionChanged: (value) => setState(() => advancedExpanded = value),
                      childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        TextField(
                          controller: voltageController,
                          decoration: const InputDecoration(labelText: 'Potential (V)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                        ),
                        TextField(
                          controller: currentController,
                          decoration: const InputDecoration(labelText: 'Current (A)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (rhoFromVi != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0, bottom: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('ρ (from V/I): ${rhoFromVi.toStringAsFixed(2)} Ω·m'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  onPressed: isAddEnabled
                      ? () {
                          if (hasVoltage != hasCurrent) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Provide both Potential and Current for advanced QA.')),
                            );
                            return;
                          }
                          if (current != null && current <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Current must be greater than zero.')),
                            );
                            return;
                          }

                          final spacingFeetValue = spacingFeet!;
                          final spacingMetersValue = feetToMeters(spacingFeetValue);
                          final geometry = _geometryFactorForArray(arrayType, spacingMetersValue);
                          double? finalRho = resolvedRhoValue;
                          double? finalResistance = resolvedResistanceValue;
                          if (finalRho == null && hasResistance && geometry > 0) {
                            finalRho = resistanceInput! * geometry;
                            finalResistance = resistanceInput;
                          }
                          if (finalRho == null || finalRho <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not resolve apparent resistivity.')),
                            );
                            return;
                          }
                          final sigmaValue = sigmaRho != null && sigmaRho >= 0 ? sigmaRho : null;
                          final manualId = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
                          try {
                            final point = SpacingPoint(
                              id: manualId,
                              arrayType: arrayType,
                              aFeet: spacingFeetValue,
                              spacingMetric: spacingMetersValue,
                              rhoAppOhmM: finalRho,
                              sigmaRhoOhmM: sigmaValue,
                              resistanceOhm: finalResistance,
                              direction: direction,
                              voltageV: voltage,
                              currentA: current,
                              contactR: const {},
                              spDriftMv: null,
                              stacks: 1,
                              repeats: null,
                              timestamp: DateTime.now(),
                              notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                            );
                            ref.read(spacingPointsProvider.notifier).addPoint(point);
                            if (voltage != null && current != null) {
                              ref.read(telemetryProvider.notifier).addSample(
                                    current: current,
                                    voltage: voltage,
                                  );
                            }
                            Navigator.pop(ctx);
                          } catch (error) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not add point: ${error.toString()}')),
                            );
                          }
                        }
                      : null,
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<SoundingDirection?> _showBulkPasteSheet(
    BuildContext context,
    WidgetRef ref,
    ArrayType arrayType,
    SoundingDirection initialDirection,
  ) async {
    final pasteController = TextEditingController();
    final bulkNotesController = TextEditingController(text: '${initialDirection.label} bulk');
    SoundingDirection selectedDirection = initialDirection;
    int? lastAdded;
    List<String> skippedMessages = const [];
    String? summary;

    return showModalBottomSheet<SoundingDirection?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setState) {
            final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottomInset + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Bulk paste points', style: Theme.of(sheetCtx).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SoundingDirection>(
                    value: selectedDirection,
                    decoration: const InputDecoration(labelText: 'Orientation'),
                    onChanged: (value) => setState(() => selectedDirection = value ?? selectedDirection),
                    items: SoundingDirection.values
                        .map((dir) => DropdownMenuItem(value: dir, child: Text(dir.label)))
                        .toList(),
                  ),
                  TextField(
                    controller: bulkNotesController,
                    decoration: const InputDecoration(labelText: 'Notes / tag (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pasteController,
                    decoration: const InputDecoration(
                      labelText: 'Rows (A ft, Ω)',
                      alignLabelWithHint: true,
                      hintText: 'Example: 10\t15',
                    ),
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(
                          sheetCtx,
                          lastAdded != null && lastAdded! > 0 ? selectedDirection : null,
                        ),
                        child: const Text('Close'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          final raw = pasteController.text;
                          final lines = raw.split(RegExp(r'\r?\n'));
                          final notifier = ref.read(spacingPointsProvider.notifier);
                          final newSkipped = <String>[];
                          var added = 0;
                          for (var i = 0; i < lines.length; i++) {
                            final line = lines[i].trim();
                            if (line.isEmpty) continue;
                            final parts = line.split(RegExp(r'[\s,]+')).where((token) => token.isNotEmpty).toList();
                            if (parts.length < 2) {
                              newSkipped.add('Row ${i + 1}: expected A(ft) and Ω values.');
                              continue;
                            }
                            final aFeet = double.tryParse(parts[0]);
                            final resistance = double.tryParse(parts[1]);
                            if (aFeet == null || resistance == null) {
                              newSkipped.add('Row ${i + 1}: non-numeric value.');
                              continue;
                            }
                            if (aFeet <= 0 || resistance <= 0) {
                              newSkipped.add('Row ${i + 1}: values must be > 0.');
                              continue;
                            }
                            final aMeters = feetToMeters(aFeet);
                            final k = _geometryFactorForArray(arrayType, aMeters);
                            if (k <= 0) {
                              newSkipped.add('Row ${i + 1}: geometry factor unavailable.');
                              continue;
                            }
                            final rho = resistance * k;
                            final notes = bulkNotesController.text.trim();
                            final point = SpacingPoint.newPoint(
                              arrayType: arrayType,
                              aFeet: aFeet,
                              rhoAppOhmM: rho,
                              direction: selectedDirection,
                              spacingMeters: aMeters,
                              notes: notes.isEmpty ? '${selectedDirection.label} bulk' : notes,
                            );
                            notifier.addPoint(point);
                            added++;
                          }
                          setState(() {
                            lastAdded = added;
                            skippedMessages = newSkipped;
                            summary = 'Added ${added.toString()} row(s). Skipped ${newSkipped.length}.';
                          });
                        },
                        child: const Text('Import'),
                      ),
                    ],
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(summary!, style: Theme.of(sheetCtx).textTheme.bodySmall),
                    ),
                    if (skippedMessages.isNotEmpty)
                      ...skippedMessages.map(
                        (msg) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '• ' + msg,
                            style: Theme.of(sheetCtx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Theme.of(sheetCtx).colorScheme.error),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

double _geometryFactorForArray(ArrayType arrayType, double spacingMeters) {
  if (spacingMeters <= 0) {
    return 0;
  }
  switch (arrayType) {
    case ArrayType.wenner:
      return geom.geometryFactor(
        array: geom.GeometryArray.wenner,
        spacing: spacingMeters,
      );
    case ArrayType.schlumberger:
      final mn = spacingMeters / 3;
      return geom.geometryFactor(
        array: geom.GeometryArray.schlumberger,
        spacing: spacingMeters,
        mn: mn,
      );
    case ArrayType.dipoleDipole:
    case ArrayType.poleDipole:
    case ArrayType.custom:
      return 2 * math.pi * spacingMeters;
  }
}
