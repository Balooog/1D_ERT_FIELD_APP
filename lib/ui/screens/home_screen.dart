import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/enums.dart';
import '../../models/spacing_point.dart';
import '../../services/csv_io.dart';
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
    final sigmaRhoController = TextEditingController();
    final voltageController = TextEditingController();
    final currentController = TextEditingController();
    ArrayType arrayType = ArrayType.wenner;
    SoundingDirection direction = SoundingDirection.ns;
    bool advancedExpanded = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          double? parseValue(TextEditingController controller) {
            final text = controller.text.trim();
            if (text.isEmpty) return null;
            return double.tryParse(text);
          }

          final aFeet = parseValue(aFeetController);
          final rho = parseValue(rhoController);
          final sigmaRho = parseValue(sigmaRhoController);
          final aMeters = aFeet != null ? feetToMeters(aFeet) : null;
          final voltage = parseValue(voltageController);
          final current = parseValue(currentController);
          final rhoFromVi = (voltage != null && current != null && current != 0 && aMeters != null)
              ? 2 * math.pi * aMeters * (voltage / current)
              : null;
          final rhoDiffPercent = (rho != null && rhoFromVi != null && rho != 0)
              ? ((rhoFromVi - rho).abs() / rho) * 100
              : null;
          final hasVoltage = voltageController.text.trim().isNotEmpty;
          final hasCurrent = currentController.text.trim().isNotEmpty;
          final bool baseValid = aFeet != null && aFeet > 0 && rho != null && rho > 0;
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
                  DropdownButtonFormField<ArrayType>(
                    value: arrayType,
                    onChanged: (value) => setState(() => arrayType = value ?? arrayType),
                    items: ArrayType.values
                        .map((type) => DropdownMenuItem(value: type, child: Text(type.label)))
                        .toList(),
                  ),
                  TextField(
                    controller: aFeetController,
                    decoration: const InputDecoration(labelText: 'A-Spacing (ft)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: rhoController,
                    decoration: const InputDecoration(labelText: 'Apparent Resistivity ρ (Ω·m)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: sigmaRhoController,
                    decoration: const InputDecoration(labelText: 'StdDev σρ (Ω·m)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  DropdownButtonFormField<SoundingDirection>(
                    value: direction,
                    decoration: const InputDecoration(labelText: 'Direction'),
                    onChanged: (value) => setState(() => direction = value ?? direction),
                    items: SoundingDirection.values
                        .map((dir) => DropdownMenuItem(value: dir, child: Text(dir.label)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Spacing (m): ${aMeters != null ? aMeters.toStringAsFixed(3) : '—'}'),
                        if (rho != null)
                          Text('Apparent ρ (Ω·m): ${rho.toStringAsFixed(2)}'),
                        if (sigmaRho != null)
                          Text('σρ (Ω·m): ${sigmaRho.toStringAsFixed(2)}'),
                        if (rhoDiffPercent != null)
                          Text(
                            'Δρ vs V/I: ${rhoDiffPercent.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: rhoDiffPercent > SpacingPoint.rhoQaThresholdPercent
                                  ? Colors.orange
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                      ],
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
                      String? invalidField;
                      double? parseRequired(TextEditingController controller, String label) {
                        final text = controller.text.trim();
                        final value = double.tryParse(text);
                        if (text.isEmpty || value == null) {
                          invalidField = label;
                          return null;
                        }
                        if (value <= 0) {
                          invalidField = '$label must be > 0';
                          return null;
                        }
                        return value;
                      }

                      double? parseOptional(TextEditingController controller, {bool allowNegative = false}) {
                        final text = controller.text.trim();
                        if (text.isEmpty) return null;
                        final value = double.tryParse(text);
                        if (value == null) {
                          invalidField = 'Invalid number "${controller.text}"';
                          return null;
                        }
                        if (!allowNegative && value < 0) {
                          invalidField = 'Values must be ≥ 0';
                          return null;
                        }
                        return value;
                      }

                      final aFeetValue = parseRequired(aFeetController, 'A-Spacing (ft)');
                      final rhoValue = parseRequired(rhoController, 'Apparent Resistivity ρ (Ω·m)');
                      final sigmaRhoValue = parseOptional(sigmaRhoController);
                      final voltageValue = parseOptional(voltageController);
                      final currentValue = parseOptional(currentController);

                      if ((voltageController.text.trim().isNotEmpty) !=
                          (currentController.text.trim().isNotEmpty)) {
                        invalidField = 'Provide both Potential and Current for advanced QA.';
                      }

                      if (invalidField != null || aFeetValue == null || rhoValue == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(invalidField ?? 'Please fill required fields.')),
                        );
                        return;
                      }

                      if (currentValue != null && currentValue == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Current must be greater than zero.')),
                        );
                        return;
                      }

                      final aMetersValue = feetToMeters(aFeetValue);
                      final manualId = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
                      final point = SpacingPoint(
                        id: manualId,
                        arrayType: arrayType,
                        aFeet: aFeetValue,
                        spacingMetric: aMetersValue,
                    rhoAppOhmM: rhoValue,
                    sigmaRhoOhmM: sigmaRhoValue,
                        direction: direction,
                        voltageV: voltageValue,
                        currentA: currentValue,
                        contactR: const {},
                        spDriftMv: null,
                        stacks: 1,
                        repeats: null,
                        timestamp: DateTime.now(),
                      );

                      ref.read(spacingPointsProvider.notifier).addPoint(point);
                      if (voltageValue != null && currentValue != null) {
                        ref.read(telemetryProvider.notifier).addSample(
                              current: currentValue,
                              voltage: voltageValue,
                            );
                      }
                      Navigator.pop(ctx);
                    }
                    : null,
                child: const Text('Add'),
              ),
            ],
          );
        });
      },
    );
  }
}
