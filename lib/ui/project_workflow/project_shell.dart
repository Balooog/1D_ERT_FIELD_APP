import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../core/logging.dart';
import '../../core/render_safety.dart';
import '../../models/calc.dart';
import '../../models/direction_reading.dart';
import '../../models/project.dart';
import '../../models/site.dart';
import '../../services/export_service.dart';
import '../../services/inversion.dart';
import '../../services/screenshot_service.dart';
import '../../services/storage_service.dart';
import '../../services/templates_service.dart';
import '../../state/settings_state.dart';
import '../../utils/distance_unit.dart';
import '../style/density.dart';
import '../style/icons.dart';
import '../import/import_sheet.dart';
import 'plots_panel.dart';
import 'right_rail.dart';
import 'shortcuts.dart';
import 'table_panel.dart';

class ProjectShell extends ConsumerStatefulWidget {
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
  ConsumerState<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends ConsumerState<ProjectShell> {
  late ProjectRecord _project;
  SiteRecord? _selectedSite;
  bool _showOutliers = false;
  bool _lockAxes = false;
  bool _showAllSites = false;
  GhostTemplate? _selectedTemplate;
  final TemplatesService _templatesService = TemplatesService();
  List<GhostTemplate> _templates = const [];
  final ScreenshotService _screenshotService = ScreenshotService();
  bool _isCapturingScreenshot = false;
  late ProjectAutosaveController _autosave;
  late ExportService _exportService;
  String _saveIndicator = 'Saved';
  final List<ProjectRecord> _history = [];
  int _historyIndex = -1;
  double? _focusedSpacing;
  OrientationKind? _focusedOrientation;
  final DistanceUnit _distanceUnit = DistanceUnit.feet;
  TwoLayerInversionResult? _inversionResult;
  bool _inversionLoading = false;
  Future<TwoLayerInversionResult?>? _inversionTask;
  Timer? _inversionDebounce;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queueInversionRefresh();
    });
  }

  @override
  void dispose() {
    _autosave.dispose();
    _inversionDebounce?.cancel();
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

  Widget _wrapWithScreenshot(ScreenshotRegion region, Widget child) {
    return _screenshotService.wrapRegion(region: region, child: child);
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
      _selectedSite = saved.siteById(_selectedSite?.siteId ?? '') ??
          saved.sites.firstOrNull;
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
    _queueInversionRefresh();
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

  void _applyProjectUpdate(
      ProjectRecord Function(ProjectRecord current) updater) {
    final updated = updater(_project);
    setState(() {
      _project = updated;
      _selectedSite = updated.siteById(_selectedSite?.siteId ?? '') ??
          updated.sites.firstOrNull;
      _pushHistory(updated);
    });
    _scheduleAutosave();
    _queueInversionRefresh();
  }

  void _showInlineUndo(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
          duration: const Duration(seconds: 5),
          content: Text(message),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: _undo,
          ),
        ),
      );
  }

  void _handleReadingSubmitted(
    double spacingFt,
    OrientationKind orientation,
    double? resistance,
    double? sd,
  ) {
    final site = tryRenderSafe<SiteRecord?>(
      _selectedSite,
      _project.sites.firstOrNull,
    );
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
          final updatedRecord = record
              .updateHistory(orientation, updatedHistory)
              .applyAutoInterpretation();
          return updatedRecord;
        });
      });
    });
    final spacingRecord = site.spacings
        .firstWhereOrNull((record) => record.spacingFeet == spacingFt);
    final orientationLabel = spacingRecord?.historyFor(orientation).label ??
        orientation.defaultLabel;
    final spacingLabel = spacingFt.toStringAsFixed(1);
    _showInlineUndo('Saved $spacingLabel ft • $orientationLabel');
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
    double? groundTemperatureF,
    SiteLocation? location,
    bool? updateLocation,
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
          groundTemperatureF: groundTemperatureF,
          location: location,
          updateLocation: updateLocation ?? false,
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

  String _generateNextSiteId() {
    var maxValue = 0;
    for (final site in _project.sites) {
      final upper = site.siteId.toUpperCase();
      if (upper.startsWith('ERT_')) {
        final suffix = upper.substring(4);
        final parsed = int.tryParse(suffix);
        if (parsed != null && parsed > maxValue) {
          maxValue = parsed;
        }
      }
    }
    final next = maxValue + 1;
    return 'ERT_${next.toString().padLeft(3, '0')}';
  }

  Future<void> _addSite() async {
    final controller = TextEditingController(text: _generateNextSiteId());
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
      groundTemperatureF: _selectedSite?.groundTemperatureF ?? 68.0,
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

  void _duplicateSite(SiteRecord site) {
    final nextId = _generateNextSiteId();
    final duplicate = SiteRecord(
      siteId: nextId,
      displayName: nextId,
      powerMilliAmps: site.powerMilliAmps,
      stacks: site.stacks,
      soil: site.soil,
      moisture: site.moisture,
      groundTemperatureF: site.groundTemperatureF,
      spacings: [
        for (final spacing in site.spacings)
          SpacingRecord(
            spacingFeet: spacing.spacingFeet,
            orientationA: spacing.orientationA,
            orientationB: spacing.orientationB,
            interpretation: spacing.interpretation,
          ),
      ],
    );
    _applyProjectUpdate((project) => project.addSite(duplicate));
    setState(() {
      _selectedSite = _project.siteById(nextId) ?? duplicate;
    });
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Duplicated ${site.displayName} → $nextId')),
    );
  }

  Future<void> _deleteSite(SiteRecord site) async {
    if (_project.sites.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Projects must contain at least one site.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete site'),
          content:
              Text('Delete ${site.displayName}? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    _applyProjectUpdate((project) {
      final remaining = project.sites
          .where((element) => element.siteId != site.siteId)
          .toList();
      return project.copyWith(sites: remaining);
    });
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted ${site.displayName}')),
    );
  }

  void _toggleAllSitesView() {
    final next = !_showAllSites;
    setState(() {
      _showAllSites = next;
    });
    LOG.info('toggle_all_sites', extra: {'show_all_sites': next});
  }

  void _toggleOutliers() {
    final next = !_showOutliers;
    setState(() {
      _showOutliers = next;
    });
    LOG.info('toggle_outliers', extra: {'show_outliers': next});
  }

  void _toggleLockAxes() {
    final next = !_lockAxes;
    setState(() {
      _lockAxes = next;
    });
    LOG.info('toggle_lock_axes', extra: {'lock_axes': next});
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

  Future<void> _exportSitePdf() async {
    final site = _selectedSite;
    if (site == null) {
      return;
    }
    final siteId = site.siteId;
    try {
      final summary = await _refreshInversion();
      if (!mounted) {
        return;
      }
      final resolvedSite = _project.siteById(siteId) ?? site;
      final inversion = summary ?? _inversionResult;
      if (inversion == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Need at least two valid spacings to export PDF.')),
        );
        return;
      }
      final entry = InversionReportEntry(
        site: resolvedSite,
        result: inversion,
        distanceUnit: _distanceUnit,
      );
      final file = await _exportService.exportInversionPdf(_project, entry);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved PDF to ${file.path}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $error')),
      );
    }
  }

  Future<void> _exportAllSitesPdf() async {
    final sites = _project.sites;
    if (sites.isEmpty) {
      return;
    }
    try {
      final entries = <InversionReportEntry>[];
      for (final site in sites) {
        final summary = await invertTwoLayerSite(site);
        if (summary != null) {
          entries.add(
            InversionReportEntry(
              site: site,
              result: summary,
              distanceUnit: _distanceUnit,
            ),
          );
        }
      }
      if (entries.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No sites have enough data to export a PDF report.')),
        );
        return;
      }
      final file =
          await _exportService.exportBatchInversionPdf(_project, entries);
      if (!mounted) {
        return;
      }
      final skipped = sites.length - entries.length;
      final suffix = skipped > 0
          ? ' (skipped $skipped site${skipped == 1 ? '' : 's'})'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved batch PDF to ${file.path}$suffix')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Batch PDF export failed: $error')),
      );
    }
  }

  Future<void> _promptExcelExport() async {
    if (_project.sites.isEmpty) {
      if (!mounted) return;
      await _showExcelInfoDialog(
        title: 'Nothing to export',
        message: 'Add at least one site before exporting Excel.',
      );
      return;
    }
    final scope = await showDialog<_ExcelExportScope>(
      context: context,
      builder: (context) {
        final site = _selectedSite;
        final siteName = site?.displayName ?? 'Select a site';
        return AlertDialog(
          title: const Text('Export Excel (THG)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.timeline),
                title: const Text('Selected site'),
                subtitle: Text(siteName),
                enabled: site != null,
                onTap: site == null
                    ? null
                    : () => Navigator.of(context)
                        .pop<_ExcelExportScope>(_ExcelExportScope.site),
              ),
              ListTile(
                leading: const Icon(Icons.library_books),
                title: const Text('All project sites'),
                subtitle:
                    Text('${_project.sites.length} site(s) in this project'),
                onTap: () => Navigator.of(context)
                    .pop<_ExcelExportScope>(_ExcelExportScope.project),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (!mounted || scope == null) {
      return;
    }
    switch (scope) {
      case _ExcelExportScope.site:
        await _exportExcelSite();
        break;
      case _ExcelExportScope.project:
        await _exportExcelProject();
        break;
    }
  }

  Future<void> _exportExcelSite() async {
    final site = _selectedSite;
    if (site == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a site to export.')),
      );
      return;
    }
    try {
      final file = await _exportService.exportExcelForSite(_project, site);
      if (!mounted) return;
      await _showExcelConfirmation(file);
    } catch (error) {
      if (!mounted) return;
      await _showExcelFailure(error);
    }
  }

  Future<void> _exportExcelProject() async {
    if (_project.sites.isEmpty) {
      if (!mounted) return;
      await _showExcelInfoDialog(
        title: 'Nothing to export',
        message: 'Add at least one site before exporting Excel.',
      );
      return;
    }
    try {
      final file = await _exportService.exportExcelForProject(_project);
      if (!mounted) return;
      await _showExcelConfirmation(file);
    } catch (error) {
      if (!mounted) return;
      await _showExcelFailure(error);
    }
  }

  Future<void> _showExcelConfirmation(File file) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excel export saved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Workbook saved to:'),
            const SizedBox(height: 8),
            SelectableText(file.path),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExcelFailure(Object error) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excel export failed'),
        content: Text('$error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExcelInfoDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
      _selectedSite = _project.siteById(_selectedSite?.siteId ?? '') ??
          _project.sites.firstOrNull;
    });
  }

  void _redo() {
    if (_historyIndex >= _history.length - 1) {
      return;
    }
    setState(() {
      _historyIndex++;
      _project = _history[_historyIndex];
      _selectedSite = _project.siteById(_selectedSite?.siteId ?? '') ??
          _project.sites.firstOrNull;
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

  Future<TwoLayerInversionResult?> _refreshInversion() {
    final inFlight = _inversionTask;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _solveCurrentInversion();
    _inversionTask = future;
    future.whenComplete(() {
      if (identical(_inversionTask, future)) {
        _inversionTask = null;
      }
    });
    return future;
  }

  void _queueInversionRefresh() {
    _inversionDebounce?.cancel();
    _inversionDebounce = Timer(const Duration(milliseconds: 80), () {
      _inversionDebounce = null;
      unawaited(_refreshInversion());
    });
  }

  Future<TwoLayerInversionResult?> _solveCurrentInversion() async {
    final site = _selectedSite;
    if (site == null) {
      if (mounted) {
        setState(() {
          _inversionResult = null;
          _inversionLoading = false;
        });
      }
      return null;
    }
    final siteId = site.siteId;
    if (mounted) {
      setState(() {
        _inversionLoading = true;
      });
    }
    final summary = await invertTwoLayerSite(site);
    if (!mounted) {
      return summary;
    }
    if (_selectedSite == null || _selectedSite!.siteId != siteId) {
      return summary;
    }
    setState(() {
      _inversionResult = summary;
      _inversionLoading = false;
    });
    return summary;
  }

  @override
  Widget build(BuildContext context) {
    final site = _selectedSite;
    final averageGhost = _computeSiteAverage(site);
    final templateOptions = _templates;
    final settings = ref.watch(settingsProvider);
    final devScreenshotEnabled = !kReleaseMode && settings.devScreenshotEnabled;

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
      child: _wrapWithScreenshot(
        ScreenshotRegion.workspace,
        Scaffold(
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
                icon: Icon(
                    _showOutliers ? Icons.visibility : Icons.visibility_off),
                tooltip: _showOutliers ? 'Hide outliers' : 'Show outliers',
                onPressed: _toggleOutliers,
              ),
              PopupMenuButton<String>(
                tooltip: 'Export',
                icon: const Icon(Icons.file_download),
                onSelected: (value) {
                  switch (value) {
                    case 'csv':
                      _exportSite();
                      break;
                    case 'pdf_site':
                      unawaited(_exportSitePdf());
                      break;
                    case 'pdf_all':
                      unawaited(_exportAllSitesPdf());
                      break;
                    case 'excel':
                      unawaited(_promptExcelExport());
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'csv',
                    child: Text('Export CSV & DAT'),
                  ),
                  PopupMenuItem(
                    value: 'pdf_site',
                    child: Text('Save site PDF…'),
                  ),
                  PopupMenuItem(
                    value: 'pdf_all',
                    child: Text('Save all sites to PDF'),
                  ),
                  PopupMenuItem(
                    value: 'excel',
                    child: Text('Export Excel (THG)…'),
                  ),
                ],
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
          floatingActionButton: devScreenshotEnabled
              ? FloatingActionButton.small(
                  heroTag: 'project-shell-screenshot',
                  tooltip: 'Capture workspace screenshot',
                  onPressed: _isCapturingScreenshot
                      ? null
                      : _captureWorkspaceScreenshot,
                  child: _isCapturingScreenshot
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : const Icon(AppIcons.camera),
                )
              : null,
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
                    _buildWorkspaceToolbar(context, templateOptions),
                    Expanded(
                      child: _buildResponsiveWorkspace(
                        context,
                        site,
                        averageGhost,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSiteListCard(
    BuildContext context,
    SiteRecord site, {
    EdgeInsets margin = const EdgeInsets.all(12),
  }) {
    return _wrapWithScreenshot(
      ScreenshotRegion.siteList,
      Card(
        margin: margin,
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SiteListPanel(
          sites: _project.sites,
          selectedSiteId: site.siteId,
          onSelect: _selectSite,
          onAdd: _addSite,
          onDuplicate: _duplicateSite,
          onDelete: _deleteSite,
          validSpacingCount: _validSpacingCount,
        ),
      ),
    );
  }

  Widget _buildWorkspaceToolbar(
    BuildContext context,
    List<GhostTemplate> templateOptions,
  ) {
    final theme = Theme.of(context);
    final templateSelector = SizedBox(
      width: 240,
      child: DropdownButtonFormField<GhostTemplate?>(
        initialValue: _selectedTemplate,
        decoration: const InputDecoration(
          labelText: 'Ghost template',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: kDenseFieldPadding,
        ),
        items: [
          const DropdownMenuItem<GhostTemplate?>(
            value: null,
            child: Text('None'),
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
    );

    final isSaving = _saveIndicator.startsWith('Saving');
    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSaving)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          else
            Icon(
              Icons.check_circle,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          const SizedBox(width: 6),
          Text(
            'Status: $_saveIndicator',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    final statusGroup = Wrap(
      spacing: kDenseGap,
      runSpacing: kDenseGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        statusBadge,
        templateSelector,
      ],
    );

    const chipDensity = VisualDensity(horizontal: -2, vertical: -2);
    final togglesGroup = Wrap(
      spacing: kDenseGap,
      runSpacing: kDenseGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          avatar: Icon(
            _showOutliers ? Icons.visibility : Icons.visibility_off,
            size: 16,
          ),
          label: Text(_showOutliers ? 'Outliers shown' : 'Outliers hidden'),
          selected: _showOutliers,
          visualDensity: chipDensity,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => _toggleOutliers(),
        ),
        FilterChip(
          avatar: Icon(
            _lockAxes ? Icons.center_focus_strong : Icons.auto_graph,
            size: 16,
          ),
          label: Text(_lockAxes ? 'Axes locked' : 'Axes auto'),
          selected: _lockAxes,
          visualDensity: chipDensity,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => _toggleLockAxes(),
        ),
        FilterChip(
          avatar: Icon(
            _showAllSites ? Icons.grid_view : Icons.insights,
            size: 16,
          ),
          label: Text(_showAllSites ? 'All sites view' : 'Single site view'),
          selected: _showAllSites,
          visualDensity: chipDensity,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) => _toggleAllSitesView(),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                statusGroup,
                const SizedBox(height: 8),
                togglesGroup,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: statusGroup),
              const SizedBox(width: 12),
              togglesGroup,
            ],
          );
        },
      ),
    );
  }

  Widget _buildResponsiveWorkspace(
    BuildContext context,
    SiteRecord site,
    List<GhostSeriesPoint> averageGhost,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < 1024) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildSiteListCard(
                context,
                site,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: _showAllSites ? 420 : 360,
                child: _buildPlotsCard(
                  context,
                  site,
                  averageGhost,
                  margin: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 520,
                child: _buildTableCard(
                  context,
                  site,
                  margin: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 12),
              _buildRightRail(site),
            ],
          );
        }

        final isLarge = width >= 1440;
        final mainFlex = isLarge ? 6 : 7;
        final railFlex = isLarge ? 5 : 4;
        final siteListWidth = isLarge ? 260.0 : 220.0;

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: siteListWidth,
                child: _buildSiteListCard(
                  context,
                  site,
                  margin: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: mainFlex,
                child: Column(
                  children: [
                    Expanded(
                      flex: _showAllSites ? 5 : 4,
                      child: _buildPlotsCard(
                        context,
                        site,
                        averageGhost,
                        margin: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      flex: 6,
                      child: _buildTableCard(
                        context,
                        site,
                        margin: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: railFlex,
                child: _buildRightRail(site),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _captureWorkspaceScreenshot() async {
    if (_isCapturingScreenshot) {
      return;
    }
    setState(() {
      _isCapturingScreenshot = true;
    });

    final result = await _screenshotService.captureRegion(
      region: ScreenshotRegion.workspace,
      projectDirectory: widget.projectDirectory,
      prefixOverride: ScreenshotRegion.workspace.filePrefix,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isCapturingScreenshot = false;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (result.isSuccess && result.path != null) {
      final displayPath = _formatScreenshotPath(result.path!);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Screenshot saved to $displayPath'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Screenshot failed: ${result.error}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatScreenshotPath(String absolutePath) {
    try {
      return p.relative(absolutePath);
    } on ArgumentError {
      return absolutePath;
    }
  }

  Widget _buildPlotsCard(
    BuildContext context,
    SiteRecord site,
    List<GhostSeriesPoint> averageGhost, {
    EdgeInsets margin = const EdgeInsets.all(12),
  }) {
    final theme = Theme.of(context);
    final chart = PlotsPanel(
      project: _project,
      selectedSite: site,
      showOutliers: _showOutliers,
      lockAxes: _lockAxes,
      showAllSites: _showAllSites,
      template: _selectedTemplate,
      averageGhost: averageGhost,
    );
    return _wrapWithScreenshot(
      ScreenshotRegion.plotsPanel,
      Card(
        margin: margin,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: chart),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(
    BuildContext context,
    SiteRecord site, {
    EdgeInsets margin = const EdgeInsets.all(12),
  }) {
    final theme = Theme.of(context);
    final isSaving = _saveIndicator.startsWith('Saving');
    return _wrapWithScreenshot(
      ScreenshotRegion.tablePanel,
      Card(
        margin: margin,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerHighest,
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
          isSaving: isSaving,
          saveStatusLabel: _saveIndicator,
        ),
      ),
    );
  }

  Widget _buildRightRail(SiteRecord site) {
    return _wrapWithScreenshot(
      ScreenshotRegion.rightRail,
      RightRail(
        site: site,
        projectDefaultStacks: _project.defaultStacks,
        onMetadataChanged: _handleMetadataChanged,
        inversionResult: _inversionResult,
        isInversionLoading: _inversionLoading,
        distanceUnit: _distanceUnit,
        onExportCsv: () => unawaited(_exportSite()),
        onExportSitePdf: () => unawaited(_exportSitePdf()),
        onExportAllSitesPdf: () => unawaited(_exportAllSitesPdf()),
        onExportExcel: () => unawaited(_promptExcelExport()),
      ),
    );
  }

  int _validSpacingCount(SiteRecord site) {
    var valid = 0;
    for (final spacing in site.spacings) {
      final a = spacing.orientationA.latest;
      final b = spacing.orientationB.latest;
      final hasValidA = a != null && !a.isBad && a.resistanceOhm != null;
      final hasValidB = b != null && !b.isBad && b.resistanceOhm != null;
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

enum _ExcelExportScope { site, project }

class SiteListPanel extends StatelessWidget {
  const SiteListPanel({
    super.key,
    required this.sites,
    required this.selectedSiteId,
    required this.onSelect,
    required this.onAdd,
    required this.onDuplicate,
    required this.onDelete,
    required this.validSpacingCount,
  });

  final List<SiteRecord> sites;
  final String? selectedSiteId;
  final ValueChanged<SiteRecord> onSelect;
  final Future<void> Function() onAdd;
  final void Function(SiteRecord) onDuplicate;
  final Future<void> Function(SiteRecord) onDelete;
  final int Function(SiteRecord) validSpacingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sites',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => onAdd(),
                icon: const Icon(Icons.add),
                label: const Text('Add Site'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: sites.isEmpty
              ? Center(
                  child: Text(
                    'No sites yet',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: sites.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final site = sites[index];
                    final isSelected = site.siteId == selectedSiteId;
                    return ListTile(
                      title: Text(site.displayName),
                      subtitle: Text(
                        'Valid ${validSpacingCount(site)}/${site.spacings.length} spacings',
                      ),
                      selected: isSelected,
                      onTap: () => onSelect(site),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Site actions',
                        onSelected: (value) {
                          switch (value) {
                            case 'duplicate':
                              onDuplicate(site);
                              break;
                            case 'delete':
                              onDelete(site);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            enabled: sites.length > 1,
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
