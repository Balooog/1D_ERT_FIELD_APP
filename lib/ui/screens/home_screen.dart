import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/enums.dart';
import '../../models/project_models.dart' as project_models;
import '../../models/spacing_point.dart';
import '../../services/csv_io.dart';
import '../../services/geometry_factors.dart' as geom;
import '../../services/persistence.dart';
import '../../state/providers.dart';
import '../../state/project_controller.dart';
import '../../utils/distance_unit.dart';
import '../widgets/header_badges.dart';
import '../widgets/points_table.dart';
import '../widgets/residual_strip.dart';
import '../widgets/sounding_chart.dart';
import '../widgets/telemetry_panel.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _projectNameController;
  late final TextEditingController _lineController;
  late final TextEditingController _operatorController;
  late final TextEditingController _projectNotesController;
  late final FocusNode _projectNameFocus;
  late final FocusNode _lineFocus;
  late final FocusNode _operatorFocus;
  late final FocusNode _notesFocus;
  late final ProviderSubscription<ProjectState> _projectSubscription;
  bool _projectExpanded = false;
  DistanceUnit _distanceUnit = DistanceUnit.feet;

  @override
  void initState() {
    super.initState();
    _projectNameController = TextEditingController();
    _lineController = TextEditingController();
    _operatorController = TextEditingController();
    _projectNotesController = TextEditingController();
    _projectNameFocus = FocusNode();
    _lineFocus = FocusNode();
    _operatorFocus = FocusNode();
    _notesFocus = FocusNode();
    final projectState = ref.read(projectControllerProvider);
    _applyProjectState(projectState);
    _projectSubscription = ref.listenManual<ProjectState>(
      projectControllerProvider,
      (previous, next) {
        if (previous?.project != next.project) {
          _applyProjectState(next);
        }
      },
    );
  }

  @override
  void dispose() {
    _projectSubscription.close();
    _projectNameController.dispose();
    _lineController.dispose();
    _operatorController.dispose();
    _projectNotesController.dispose();
    _projectNameFocus.dispose();
    _lineFocus.dispose();
    _operatorFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(spacingPointsProvider);
    final inversion = ref.watch(inversionProvider);
    final qaSummary = ref.watch(qaSummaryProvider);
    final isSimulating = ref.watch(simulationControllerProvider);
    final telemetry = ref.watch(telemetryProvider);
    final projectState = ref.watch(projectControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ResiCheck'),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenu,
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
            _buildProjectPanel(projectState, points),
            HeaderBadges(summary: qaSummary),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: points.isEmpty
                        ? const Center(
                            child: Text('No data yet. Import a CSV or start simulation.'),
                          )
                        : SoundingChart(
                            points: points,
                            inversion: inversion,
                            distanceUnit: _distanceUnit,
                          ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: points.isEmpty
                          ? Center(
                              child: Text(
                                'No spacing points recorded yet.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            )
                          : PointsTable(
                              points: points,
                              inversion: inversion,
                              distanceUnit: _distanceUnit,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            ResidualStrip(points: points, inversion: inversion),
            TelemetryPanel(state: telemetry),
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
                onPressed: _showAddPointDialog,
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
              child: Tooltip(
                message: 'Generate a synthetic VES (ρₐ vs a-spacing) for demo/QA.',
                child: FilledButton.tonalIcon(
                  icon: Icon(isSimulating ? Icons.stop : Icons.play_arrow),
                  label: Text(isSimulating ? 'Stop simulation' : 'Simulate sounding'),
                  onPressed: () => ref.read(simulationControllerProvider.notifier).toggle(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenu(String value) async {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported to ${file.path}')),
          );
        }
        break;
      case 'settings':
        if (mounted) {
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

  Widget _buildProjectPanel(ProjectState projectState, List<SpacingPoint> points) {
    final theme = Theme.of(context);
    final isSaving = projectState.isSaving;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        child: ExpansionTile(
          initiallyExpanded: _projectExpanded,
          onExpansionChanged: (expanded) => setState(() => _projectExpanded = expanded),
          title: const Text('Project'),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            TextField(
              controller: _projectNameController,
              focusNode: _projectNameFocus,
              decoration: const InputDecoration(labelText: 'Project / Site name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lineController,
              focusNode: _lineFocus,
              decoration: const InputDecoration(labelText: 'Line / Station'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _operatorController,
              focusNode: _operatorFocus,
              decoration: const InputDecoration(labelText: 'Operator'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _projectNotesController,
              focusNode: _notesFocus,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DistanceUnit>(
              initialValue: _distanceUnit,
              decoration: const InputDecoration(labelText: 'Distance units'),
              items: DistanceUnit.values
                  .map((unit) => DropdownMenuItem(value: unit, child: Text(unit.label)))
                  .toList(),
              onChanged: (unit) {
                if (unit != null) {
                  setState(() => _distanceUnit = unit);
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isSaving ? null : () => _saveProject(points),
                    icon: isSaving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.save_alt),
                    label: Text(isSaving ? 'Saving…' : 'Save Project'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadProject,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Load Project'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _applyProjectState(ProjectState state) {
    final project = state.project;
    final site = project?.sites.isNotEmpty == true ? project!.sites.first : null;
    final meta = site?.meta ?? const <String, dynamic>{};
    final projectName = project?.projectName ?? '';
    final line = (meta['line'] as String?) ?? site?.displayName ?? '';
    final operator = meta['operator'] as String? ?? '';
    final notes = meta['notes'] as String? ?? '';
    final distance = DistanceUnitX.parse(meta['distanceUnit'] as String?, fallback: _distanceUnit);

    void update(TextEditingController controller, FocusNode focusNode, String value) {
      if (!focusNode.hasFocus && controller.text != value) {
        controller.text = value;
      }
    }

    update(_projectNameController, _projectNameFocus, projectName);
    update(_lineController, _lineFocus, line);
    update(_operatorController, _operatorFocus, operator);
    update(_projectNotesController, _notesFocus, notes);

    if (_distanceUnit != distance) {
      setState(() => _distanceUnit = distance);
    }
  }

  Future<void> _saveProject(List<SpacingPoint> points) async {
    final controller = ref.read(projectControllerProvider.notifier);
    final project = _buildProjectModel(points);
    controller.setProject(project);
    try {
      await controller.saveProject(
        asName: project.projectName,
        fileId: PersistenceService.defaultProjectFileId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save project: $error')),
        );
      }
    }
  }

  Future<void> _loadProject() async {
    final controller = ref.read(projectControllerProvider.notifier);
    try {
      await controller.loadProject(PersistenceService.defaultProjectFileId);
      final state = ref.read(projectControllerProvider);
      final project = state.project;
      if (project != null) {
        final restored = _restoreSpacingPoints(project);
        ref.read(spacingPointsProvider.notifier).setPoints(restored);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project loaded.')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved project found.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load project: $error')),
        );
      }
    }
  }

  project_models.Project _buildProjectModel(List<SpacingPoint> points) {
    final name = _projectNameController.text.trim();
    final siteId = _lineController.text.trim();
    final operator = _operatorController.text.trim();
    final notes = _projectNotesController.text.trim();
    final sortedPoints = List<SpacingPoint>.from(points)
      ..sort((a, b) => a.spacingMeters.compareTo(b.spacingMeters));

    final dirA = <project_models.SpacingPoint>[];
    final dirB = <project_models.SpacingPoint>[];
    for (final point in sortedPoints) {
      final projectPoint = project_models.SpacingPoint(
        spacingMeters: point.spacingMeters,
        rho: point.rhoAppOhmM,
        excluded: point.excluded,
        note: point.notes ?? '',
      );
      switch (_mapDirection(point.direction)) {
        case project_models.Direction.a:
          dirA.add(projectPoint);
          break;
        case project_models.Direction.b:
          dirB.add(projectPoint);
          break;
      }
    }

    final meta = <String, dynamic>{
      if (siteId.isNotEmpty) 'line': siteId,
      if (operator.isNotEmpty) 'operator': operator,
      if (notes.isNotEmpty) 'notes': notes,
      'distanceUnit': _distanceUnit.name,
      'rawPoints': sortedPoints.map((p) => p.toJson()).toList(),
    };

    final site = project_models.Site(
      siteId: siteId.isNotEmpty ? siteId : 'site-1',
      displayName: siteId.isNotEmpty ? siteId : null,
      dirA: project_models.DirectionReadings(dir: project_models.Direction.a, points: dirA),
      dirB: project_models.DirectionReadings(dir: project_models.Direction.b, points: dirB),
      meta: meta.isEmpty ? null : meta,
    );

    return project_models.Project(
      projectName: name.isNotEmpty ? name : 'Untitled project',
      arrayType: points.isNotEmpty ? points.first.arrayType.name : ArrayType.wenner.name,
      spacingsMeters: sortedPoints.map((p) => p.spacingMeters).toList(),
      sites: [site],
    );
  }

  List<SpacingPoint> _restoreSpacingPoints(project_models.Project project) {
    if (project.sites.isEmpty) {
      return [];
    }
    final site = project.sites.first;
    final meta = site.meta ?? const <String, dynamic>{};
    final raw = meta['rawPoints'];
    if (raw is List) {
      final restored = <SpacingPoint>[];
      for (final entry in raw) {
        if (entry is Map) {
          try {
            restored.add(SpacingPoint.fromJson(Map<String, dynamic>.from(entry as Map)));
          } catch (_) {
            continue;
          }
        }
      }
      restored.sort((a, b) => a.spacingMeters.compareTo(b.spacingMeters));
      return restored;
    }

    final arrayType = _resolveArrayType(project.arrayType);
    final restored = <SpacingPoint>[];

    void addPoints(project_models.Direction direction, List<project_models.SpacingPoint> source) {
      for (var i = 0; i < source.length; i++) {
        final point = source[i];
        if (point.rho == null) continue;
        restored.add(
          SpacingPoint(
            id: '${direction.name}_${point.spacingMeters}_$i',
            arrayType: arrayType,
            spacingMetric: point.spacingMeters,
            rhoAppOhmM: point.rho,
            direction: direction == project_models.Direction.b
                ? SoundingDirection.we
                : SoundingDirection.ns,
            contactR: const {},
            spDriftMv: null,
            stacks: 1,
            repeats: null,
            timestamp: DateTime.now(),
            notes: point.note.isEmpty ? null : point.note,
            excluded: point.excluded,
          ),
        );
      }
    }

    addPoints(project_models.Direction.a, site.dirA.points);
    addPoints(project_models.Direction.b, site.dirB.points);
    restored.sort((a, b) => a.spacingMeters.compareTo(b.spacingMeters));
    return restored;
  }

  project_models.Direction _mapDirection(SoundingDirection direction) {
    switch (direction) {
      case SoundingDirection.we:
        return project_models.Direction.b;
      case SoundingDirection.ns:
      case SoundingDirection.other:
        return project_models.Direction.a;
    }
  }

  ArrayType _resolveArrayType(String name) {
    return ArrayType.values.firstWhere(
      (type) => type.name.toLowerCase() == name.toLowerCase(),
      orElse: () => ArrayType.wenner,
    );
  }

  Future<void> _showAddPointDialog() async {
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
                            initialValue: arrayType,
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
                            initialValue: direction,
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
                          final newDirection = await _showBulkPasteSheet(arrayType, direction);
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
                    initialValue: selectedDirection,
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
