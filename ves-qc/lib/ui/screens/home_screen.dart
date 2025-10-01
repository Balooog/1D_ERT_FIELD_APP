import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/enums.dart';
import '../../models/spacing_point.dart';
import '../../services/csv_io.dart';
import '../../services/geometry_factors.dart';
import '../../services/qc_rules.dart';
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
        title: const Text('VES QC'),
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
    final spacingController = TextEditingController();
    final voltageController = TextEditingController();
    final currentController = TextEditingController();
    ArrayType arrayType = ArrayType.wenner;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Add manual point'),
            content: Column(
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
                  controller: spacingController,
                  decoration: const InputDecoration(labelText: 'Spacing (m)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: voltageController,
                  decoration: const InputDecoration(labelText: 'Potential (V)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: currentController,
                  decoration: const InputDecoration(labelText: 'Current (A)'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final spacing = double.tryParse(spacingController.text);
                  final voltage = double.tryParse(voltageController.text);
                  final current = double.tryParse(currentController.text);
                  if (spacing == null || voltage == null || current == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all numeric fields.')),
                    );
                    return;
                  }
                  final geometry = arrayType == ArrayType.wenner
                      ? GeometryArray.wenner
                      : GeometryArray.schlumberger;
                  final result = rhoAppFromReadings(
                    array: geometry,
                    spacing: spacing,
                    voltage: voltage,
                    current: current,
                    mn: arrayType == ArrayType.schlumberger ? spacing / 3 : null,
                  );
                  final point = SpacingPoint(
                    id: DateFormat('yyyyMMddHHmmss').format(DateTime.now()),
                    arrayType: arrayType,
                    spacingMetric: spacing,
                    vp: voltage,
                    current: current,
                    contactR: const {},
                    spDriftMv: null,
                    stacks: 1,
                    repeats: null,
                    rhoApp: result['rho']!,
                    sigmaRhoApp: null,
                    timestamp: DateTime.now(),
                  );
                  ref.read(spacingPointsProvider.notifier).addPoint(point);
                  ref.read(telemetryProvider.notifier).addSample(
                        current: current,
                        voltage: voltage,
                      );
                  Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          );
        });
      },
    );
  }
}
