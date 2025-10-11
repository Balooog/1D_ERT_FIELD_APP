import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/calc.dart';
import '../../models/direction_reading.dart';
import '../../models/project.dart';
import '../../models/site.dart';
import '../../services/export_service.dart';
import '../../services/storage_service.dart';
import '../../services/templates_service.dart';
import '../../utils/distance_unit.dart';
import '../import/import_sheet.dart';
import 'depth_profile_tab.dart';
import 'plots_panel.dart';
import 'shortcuts.dart';
import 'table_panel.dart';

class ProjectShell extends StatefulWidget {
  const ProjectShell({
    super.key,
    required this.initialProject,
    required this.storageService,
    required this.projectDirectory,
  });

  final ProjectRecord initialProject;
  final ProjectStorageService storageService;
  final Directory projectDirectory;

  @override
  State<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends State<ProjectShell> {
  late ProjectRecord _project;
  SiteRecord? _selectedSite;
  bool _showOutliers = false;
  bool _lockAxes = false;
  bool _showAllSites = false;
  GhostTemplate? _selectedTemplate;
  final TemplatesService _templatesService = TemplatesService();
  List<GhostTemplate> _templates = const [];
  late ProjectAutosaveController _autosave;
  late ExportService _exportService;
  String _saveIndicator = 'Saved';
  final List<ProjectRecord> _history = [];
  int _historyIndex = -1;
  double? _focusedSpacing;
  OrientationKind? _focusedOrientation;
  DistanceUnit _distanceUnit = DistanceUnit.feet;

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    _selectedSite = _project.sites.firstOrNull;
    _exportService = ExportService(widget.storageService);
    _autosave = ProjectAutosaveController(onPersist: _persistProject);
    _history.add(_project);
    _historyIndex = 0;
    _loadTemplates();
  }

  @override
  void dispose() {
    _autosave.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await _templatesService.loadTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load template curves: $error')),
      );
    }
  }

  Future<void> _persistProject(ProjectRecord project) async {
    final saved = await widget.storageService.saveProject(
      project,
      directoryOverride: widget.projectDirectory,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _project = saved;
      _selectedSite = saved.siteById(_selectedSite?.siteId ?? '') ?? saved.sites.firstOrNull;
      _saveIndicator = 'Saved ${DateFormat('HH:mm:ss').format(DateTime.now())}';
    });
  }

  void _scheduleAutosave() {
    setState(() {
      _saveIndicator = 'Saving…';
    });
    _autosave.schedule(_project);
  }

  void _selectSite(SiteRecord site) {
    setState(() {
      _selectedSite = site;
    });
  }

  void _recordFocus(double spacingFt, OrientationKind orientation) {
    _focusedSpacing = spacingFt;
    _focusedOrientation = orientation;
  }

  void _pushHistory(ProjectRecord project) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(project);
    _historyIndex = _history.length - 1;
  }

  void _applyProjectUpdate(ProjectRecord Function(ProjectRecord current) updater) {
    final updated = updater(_project);
    setState(() {
      _project = updated;
      _selectedSite = updated.siteById(_selectedSite?.siteId ?? '') ?? updated.sites.firstOrNull;
      _pushHistory(updated);
    });
    _scheduleAutosave();
  }

  void _handleReadingSubmitted(
    double spacingFt,
    OrientationKind orientation,
    double? resistance,
    double? sd,
  ) {
    final site = _selectedSite;
    if (site == null) {
      return;
    }
    if (resistance == null && sd == null) {
      return;
    }
    _applyProjectUpdate((project) {
      return project.updateSite(site.siteId, (current) {
        return current.updateSpacing(spacingFt, (record) {
          final history = record.historyFor(orientation);
          final latest = history.latest;
          final sample = DirectionReadingSample(
            timestamp: DateTime.now(),
            resistanceOhm: resistance ?? latest?.resistanceOhm,
            standardDeviationPercent: sd ?? latest?.standardDeviationPercent,
            note: latest?.note ?? '',
            isBad: false,
          );
          final updatedHistory = history.addSample(sample);
          final updatedRecord =
              record.updateHistory(orientation, updatedHistory).applyAutoInterpretation();
          return updatedRecord;
        });
      });
    });
  }

  void _handleBadToggle(
    double spacingFt,
    OrientationKind orientation,
    bool isBad,
  ) {
    final site = _selectedSite;
    if (site == null) {
      return;
    }
    _applyProjectUpdate((project) {
      return project.updateSite(site.siteId, (current) {
        return current.updateSpacing(spacingFt, (record) {
          final history = record.historyFor(orientation);
          final updatedHistory = history.updateLatest(
            (sample) => sample.copyWith(isBad: isBad),
          );
          return record.updateHistory(orientation, updatedHistory);
        });
      });
    });
  }

  void _handleSdChanged(
    double spacingFt,
    OrientationKind orientation,
    double? sd,
  ) {
    _handleReadingSubmitted(spacingFt, orientation, null, sd);
  }

  void _handleMetadataChanged({
    double? power,
    int? stacks,
    SoilType? soil,
    MoistureLevel? moisture,
  }) {
    final site = _selectedSite;
    if (site == null) {
      return;
    }
    _applyProjectUpdate((project) {
      return project.updateSite(site.siteId, (current) {
        return current.updateMetadata(
          powerMilliAmps: power,
          stacks: stacks,
          soil: soil,
          moisture: moisture,
        );
      });
    });
  }

  void _handleInterpretationChanged(double spacingFt, String interpretation) {
    final site = _selectedSite;
    if (site == null) {
      return;
    }
    _applyProjectUpdate((project) {
      return project.updateSite(site.siteId, (current) {
        return current.updateSpacing(spacingFt, (record) {
          final trimmed = interpretation.trim();
          final nextInterpretation = trimmed.isEmpty ? null : trimmed;
          final updated = record.copyWith(interpretation: nextInterpretation);
          return updated;
        });
      });
    });
  }

  Future<void> _showHistory(
    double spacingFt,
    OrientationKind orientation,
  ) async {
    final site = _selectedSite;
    if (site == null) {
      return;
    }
    final record = site.spacing(spacingFt);
    final history = record?.historyFor(orientation);
    if (history == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'History for ${history.label} @ ${spacingFt.toStringAsFixed(1)} ft',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final sample in history.samples.reversed)
              ListTile(
                leading: Icon(
                  sample.isBad ? Icons.flag : Icons.check_circle,
                  color: sample.isBad
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                    'R=${sample.resistanceOhm?.toStringAsFixed(2) ?? '—'} Ω, SD=${sample.standardDeviationPercent?.toStringAsFixed(1) ?? '—'}%'),
                subtitle: Text(
                  '${DateFormat('y-MM-dd HH:mm:ss').format(sample.timestamp)}\n${sample.note}',
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _addSite() async {
    final controller = TextEditingController();
    String orientationA = 'N–S';
    String orientationB = 'W–E';
    final result = await showDialog<_NewSiteConfig>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Site'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Site ID'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: orientationA,
                decoration: const InputDecoration(labelText: 'Orientation A'),
                items: const [
                  DropdownMenuItem(value: 'N–S', child: Text('N–S')),
                  DropdownMenuItem(value: 'W–E', child: Text('W–E')),
                  DropdownMenuItem(value: 'NW–SE', child: Text('NW–SE')),
                  DropdownMenuItem(value: 'SW–NE', child: Text('SW–NE')),
                ],
                onChanged: (value) {
                  orientationA = value ?? orientationA;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: orientationB,
                decoration: const InputDecoration(labelText: 'Orientation B'),
                items: const [
                  DropdownMenuItem(value: 'N–S', child: Text('N–S')),
                  DropdownMenuItem(value: 'W–E', child: Text('W–E')),
                  DropdownMenuItem(value: 'NW–SE', child: Text('NW–SE')),
                  DropdownMenuItem(value: 'SW–NE', child: Text('SW–NE')),
                ],
                onChanged: (value) {
                  orientationB = value ?? orientationB;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final id = controller.text.trim();
                if (id.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(_NewSiteConfig(
                  siteId: id,
                  orientationA: orientationA,
                  orientationB: orientationB,
                ));
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (result == null) {
      return;
    }
    final canonicalSpacings = _project.canonicalSpacingsFeet;
    final site = SiteRecord(
      siteId: result.siteId,
      displayName: result.siteId,
      powerMilliAmps: _project.defaultPowerMilliAmps,
      stacks: _project.defaultStacks,
      spacings: canonicalSpacings
          .map(
            (spacing) => SpacingRecord.seed(
              spacingFeet: spacing,
              orientationALabel: result.orientationA,
              orientationBLabel: result.orientationB,
            ),
          )
          .toList(),
    );
    _applyProjectUpdate((project) => project.upsertSite(site));
    setState(() {
      _selectedSite = site;
    });
  }

  void _toggleAllSitesView() {
    setState(() {
      _showAllSites = !_showAllSites;
    });
  }

  void _toggleOutliers() {
    setState(() {
      _showOutliers = !_showOutliers;
    });
  }

  void _toggleLockAxes() {
    setState(() {
      _lockAxes = !_lockAxes;
    });
  }

  Future<void> _exportSite() async {
    final site = _selectedSite;
    if (site == null) {
      return;
    }
    try {
      final csvFile = await _exportService.exportFieldCsv(_project, site);
      await _exportService.exportSurferDat(_project, site);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported CSV & DAT to ${csvFile.parent.path}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }

  Future<void> _showImportSheet() async {
    final outcome = await showModalBottomSheet<ImportSheetOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ImportSheet(
        project: _project,
        initialSiteId: _selectedSite?.siteId,
      ),
    );
    if (outcome == null) {
      return;
    }
    final siteId = outcome.site.siteId;
    _applyProjectUpdate((project) => project.upsertSite(outcome.site));
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedSite = _project.siteById(siteId) ?? outcome.site;
    });
    final message = outcome.merge
        ? 'Merged import into ${outcome.site.displayName}'
        : 'Imported ${outcome.site.displayName}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _undo() {
    if (_historyIndex <= 0) {
      return;
    }
    setState(() {
      _historyIndex--;
      _project = _history[_historyIndex];
      _selectedSite =
          _project.siteById(_selectedSite?.siteId ?? '') ?? _project.sites.firstOrNull;
    });
  }

  void _redo() {
    if (_historyIndex >= _history.length - 1) {
      return;
    }
    setState(() {
      _historyIndex++;
      _project = _history[_historyIndex];
      _selectedSite =
          _project.siteById(_selectedSite?.siteId ?? '') ?? _project.sites.firstOrNull;
    });
  }

  void _markFocusedBad() {
    final site = _selectedSite;
    final spacingId = _focusedSpacing;
    final orientation = _focusedOrientation;
    if (site == null || spacingId == null || orientation == null) {
      return;
    }
    final record = site.spacing(spacingId);
    final history = record?.historyFor(orientation);
    if (history == null || history.samples.isEmpty) {
      return;
    }
    final latest = history.latest;
    final isBad = !(latest?.isBad ?? false);
    _handleBadToggle(spacingId, orientation, isBad);
  }

  List<GhostSeriesPoint> _computeSiteAverage(SiteRecord? site) {
    if (site == null) {
      return const [];
    }
    final points = <GhostSeriesPoint>[];
    for (final spacing in site.spacings) {
      final rhoValues = <double>[];
      final aSample = spacing.orientationA.latest;
      final bSample = spacing.orientationB.latest;
      if (aSample != null && !aSample.isBad && aSample.resistanceOhm != null) {
        rhoValues.add(rhoAWenner(spacing.spacingFeet, aSample.resistanceOhm!));
      }
      if (bSample != null && !bSample.isBad && bSample.resistanceOhm != null) {
        rhoValues.add(rhoAWenner(spacing.spacingFeet, bSample.resistanceOhm!));
      }
      if (rhoValues.isEmpty) {
        continue;
      }
      final avg = rhoValues.reduce((a, b) => a + b) / rhoValues.length;
      points.add(GhostSeriesPoint(spacingFt: spacing.spacingFeet, rho: avg));
    }
    points.sort((a, b) => a.spacingFt.compareTo(b.spacingFt));
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final site = _selectedSite;
    final averageGhost = _computeSiteAverage(site);
    final templateOptions = _templates;

    return ProjectWorkflowShortcuts(
      onToggleOutliers: _toggleOutliers,
      onToggleAllSites: _toggleAllSitesView,
      onToggleLockAxes: _toggleLockAxes,
      onSave: () {
        _autosave.flush();
      },
      onExport: _exportSite,
      onImport: _showImportSheet,
      onNewSite: _addSite,
      onUndo: _undo,
      onRedo: _redo,
      onMarkBad: _markFocusedBad,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_project.projectName),
          actions: [
            if (_selectedTemplate != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Chip(
                  avatar: const Icon(Icons.timeline),
                  label: Text(_selectedTemplate!.name),
                ),
              ),
            IconButton(
              icon: Icon(_showOutliers ? Icons.visibility : Icons.visibility_off),
              tooltip: _showOutliers ? 'Hide outliers' : 'Show outliers',
              onPressed: _toggleOutliers,
            ),
            IconButton(
              icon: const Icon(Icons.save_alt),
              tooltip: 'Export CSV & DAT',
              onPressed: _exportSite,
            ),
            PopupMenuButton<String>(
              tooltip: 'Add',
              icon: const Icon(Icons.add),
              onSelected: (value) {
                switch (value) {
                  case 'import':
                    _showImportSheet();
                    break;
                  case 'new_site':
                    _addSite();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'import',
                  child: Text('Import from file…'),
                ),
                PopupMenuItem(
                  value: 'new_site',
                  child: Text('New site'),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: site == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No sites yet. Import existing data or add a new site to begin.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.file_open),
                      label: const Text('Import from file…'),
                      onPressed: _showImportSheet,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('New site'),
                      onPressed: _addSite,
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(_saveIndicator),
                        const SizedBox(width: 16),
                        DropdownButton<GhostTemplate?>(
                          value: _selectedTemplate,
                          hint: const Text('Template ghost curve'),
                          items: [
                            const DropdownMenuItem<GhostTemplate?>(
                              value: null,
                              child: Text('No template'),
                            ),
                            for (final template in templateOptions)
                              DropdownMenuItem<GhostTemplate?>(
                                value: template,
                                child: Text(template.name),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedTemplate = value;
                            });
                          },
                        ),
                        const Spacer(),
                        Text('Outliers ${_showOutliers ? 'shown' : 'hidden'}'),
                        const SizedBox(width: 12),
                        Text('Axes ${_lockAxes ? 'locked' : 'auto'}'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 220,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: _buildSiteList(),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: PlotsPanel(
                                  project: _project,
                                  selectedSite: site,
                                  showOutliers: _showOutliers,
                                  lockAxes: _lockAxes,
                                  showAllSites: _showAllSites,
                                  template: _selectedTemplate,
                                  averageGhost: averageGhost,
                                ),
                              ),
                              SizedBox(
                                width: 420,
                                child: TablePanel(
                                  site: site,
                                  projectDefaultStacks: _project.defaultStacks,
                                  showOutliers: _showOutliers,
                                  onResistanceChanged: _handleReadingSubmitted,
                                  onSdChanged: _handleSdChanged,
                                  onInterpretationChanged: _handleInterpretationChanged,
                                  onToggleBad: _handleBadToggle,
                                  onMetadataChanged: _handleMetadataChanged,
                                  onShowHistory: _showHistory,
                                  onFocusChanged: _recordFocus,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DepthProfileTab(
                        site: site,
                        distanceUnit: _distanceUnit,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSiteList() {
    return ListView(
      children: [
        for (final site in _project.sites)
          ListTile(
            title: Text(site.displayName),
            subtitle: Text(
              'Valid ${_validSpacingCount(site)}/${site.spacings.length} spacings',
            ),
            selected: _selectedSite?.siteId == site.siteId,
            onTap: () => _selectSite(site),
          ),
      ],
    );
  }

  int _validSpacingCount(SiteRecord site) {
    var valid = 0;
    for (final spacing in site.spacings) {
      final a = spacing.orientationA.latest;
      final b = spacing.orientationB.latest;
      final hasValidA =
          a != null && !a.isBad && a.resistanceOhm != null;
      final hasValidB =
          b != null && !b.isBad && b.resistanceOhm != null;
      if (hasValidA || hasValidB) {
        valid++;
      }
    }
    return valid;
  }
}

class _NewSiteConfig {
  _NewSiteConfig({
    required this.siteId,
    required this.orientationA,
    required this.orientationB,
  });

  final String siteId;
  final String orientationA;
  final String orientationB;
}

