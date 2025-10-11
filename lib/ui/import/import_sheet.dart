import 'dart:async';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/project.dart';
import '../../models/site.dart';
import '../../services/import/import_models.dart';
import '../../services/import/import_service.dart';
import 'widgets/column_map_row.dart';

class ImportSheetOutcome {
  ImportSheetOutcome.newSite(this.site)
      : mergeIntoSiteId = null,
        merge = false;

  ImportSheetOutcome.merge({required this.mergeIntoSiteId, required this.site})
      : merge = true;

  final bool merge;
  final String? mergeIntoSiteId;
  final SiteRecord site;
}

enum _ImportDestination { newSite, merge }

class ImportSheet extends StatefulWidget {
  const ImportSheet({
    super.key,
    required this.project,
    this.initialSiteId,
  });

  final ProjectRecord project;
  final String? initialSiteId;

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  final ImportService _service = ImportService();
  static const _unitPreferenceKey = 'import.lastUnits';
  ImportSession? _session;
  ImportMapping? _mapping;
  ImportValidationResult? _validation;
  bool _validating = false;
  bool _loading = false;
  String? _error;
  _ImportDestination _destination = _ImportDestination.newSite;
  late final TextEditingController _siteIdController;
  late final TextEditingController _displayNameController;
  String? _selectedMergeSiteId;
  bool _overwrite = false;
  SharedPreferences? _prefs;
  ImportDistanceUnit? _lastPreferredUnit;

  @override
  void initState() {
    super.initState();
    final defaultSiteId = widget.project.sites.isEmpty
        ? 'Site-1'
        : 'Site-${widget.project.sites.length + 1}';
    _siteIdController = TextEditingController(text: defaultSiteId);
    _displayNameController = TextEditingController(text: defaultSiteId);
    _selectedMergeSiteId = widget.initialSiteId ?? widget.project.sites.firstOrNull?.siteId;
    unawaited(_restoreUnitPreference());
  }

  @override
  void dispose() {
    _siteIdController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    final mapping = _mapping;
    final validation = _validation;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Import field data'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _loading ? null : _pickFile,
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file),
                        label: const Text('Choose file'),
                      ),
                      const SizedBox(width: 12),
                      if (session != null)
                        Expanded(
                          child: Text(
                            session.source.name,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        const Spacer(),
                      if (session != null) const SizedBox(width: 12),
                      if (session != null)
                        Chip(
                          label: Text(
                            '${session.preview.typeLabel} · ${session.preview.rowCount} rows',
                          ),
                        ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: session == null || mapping == null
                      ? _buildPlaceholder(context)
                      : _buildContent(session.preview, mapping, validation),
                ),
                _buildFooter(context, validation),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Center(
      child: Text(
        'Pick a CSV, TXT, DAT, or XLSX file to preview and map columns.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildContent(
    ImportPreview preview,
    ImportMapping mapping,
    ImportValidationResult? validation,
  ) {
    final inferenceBanner = _buildUnitInferenceBanner(preview, mapping);
    final conversionBanner = _buildConversionBanner(mapping);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DropdownButton<ImportDistanceUnit>(
                      value: mapping.distanceUnit,
                      onChanged: (value) {
                        if (value == null) return;
                        unawaited(_setMappingUnit(value));
                      },
                      items: [
                        for (final unit in ImportDistanceUnit.values)
                          DropdownMenuItem(
                            value: unit,
                            child: Text(unit.label),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        final session = _session;
                        if (session == null) return;
                        final auto = _service.autoMap(session.preview);
                        setState(() {
                          _mapping = auto;
                          _validation = null;
                        });
                      },
                      icon: const Icon(Icons.bolt),
                      label: const Text('Auto-map'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _mapping = ImportMapping(
                            assignments: {},
                            distanceUnit: mapping.distanceUnit,
                          );
                          _validation = null;
                        });
                      },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildUnitDetectionInfo(preview, mapping),
                if (inferenceBanner != null) ...[
                  const SizedBox(height: 8),
                  inferenceBanner,
                ],
                if (conversionBanner != null) ...[
                  const SizedBox(height: 8),
                  conversionBanner,
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: preview.columns.length,
                    itemBuilder: (context, index) {
                      final column = preview.columns[index];
                      final selected = mapping.assignments[column.index];
                      return ColumnMapRow(
                        descriptor: column,
                        selected: selected,
                        onChanged: (target) => _updateAssignment(column.index, target),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Preview', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildPreviewTable(preview),
                ),
                if (preview.issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Detected file issues', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 80,
                    child: ListView(
                      children: [
                        for (final issue in preview.issues)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.warning_amber_outlined, size: 20),
                            title: Text('Row ${issue.index}: ${issue.message}'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewTable(ImportPreview preview) {
    final columns = [
      for (final descriptor in preview.columns)
        DataColumn(
          label: Tooltip(
            message: descriptor.header,
            child: SizedBox(
              width: 120,
              child: Text(
                descriptor.header,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
    ];
    final rows = preview.previewRows
        .map(
          (row) => DataRow(
            cells: [
              for (var i = 0; i < preview.columns.length; i++)
                DataCell(
                  Tooltip(
                    message: i < row.length ? row[i] : '',
                    child: SizedBox(
                      width: 120,
                      child: Text(
                        i < row.length ? row[i] : '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        )
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        elevation: 1,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: columns, rows: rows),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ImportValidationResult? validation) {
    final theme = Theme.of(context);
    final canValidate = _session != null && _mapping != null && !_validating;
    final canImport = validation != null && validation.importedRows > 0 && !_validating;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (validation != null) ...[
            Text(
              'Imported ${validation.importedRows}/${validation.totalRows} rows · ${validation.skippedRows} skipped',
              style: theme.textTheme.bodyMedium,
            ),
            if (validation.issues.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView(
                  children: [
                    for (final issue in validation.issues.take(6))
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.info_outline, color: theme.colorScheme.tertiary),
                        title: Text('Row ${issue.rowIndex}: ${issue.message}'),
                      ),
                    if (validation.issues.length > 6)
                      Padding(
                        padding: const EdgeInsets.only(left: 40, top: 4),
                        child: Text('… and ${validation.issues.length - 6} more'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
          _buildDestinationChooser(theme),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                onPressed: canValidate ? _validate : null,
                child: _validating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Validate'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: canImport ? _completeImport : null,
                child: const Text('Import'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationChooser(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Destination', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        RadioListTile<_ImportDestination>(
          value: _ImportDestination.newSite,
          groupValue: _destination,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _destination = value);
          },
          title: const Text('Create a new site'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _siteIdController,
                decoration: const InputDecoration(labelText: 'Site ID'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        RadioListTile<_ImportDestination>(
          value: _ImportDestination.merge,
          groupValue: _destination,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _destination = value);
          },
          title: const Text('Merge into existing site'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedMergeSiteId,
                decoration: const InputDecoration(labelText: 'Target site'),
                items: [
                  for (final site in widget.project.sites)
                    DropdownMenuItem(
                      value: site.siteId,
                      child: Text(site.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _selectedMergeSiteId = value),
              ),
              CheckboxListTile(
                value: _overwrite,
                onChanged: (value) => setState(() => _overwrite = value ?? false),
                title: const Text('Overwrite existing readings for matching spacings'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _restoreUnitPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_unitPreferenceKey);
    if (!mounted) {
      _prefs = prefs;
      _lastPreferredUnit = _decodeUnit(stored);
      return;
    }
    setState(() {
      _prefs = prefs;
      _lastPreferredUnit = _decodeUnit(stored);
    });
  }

  Future<void> _persistUnitPreference(ImportDistanceUnit unit) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_unitPreferenceKey, unit.name);
    _prefs = prefs;
  }

  ImportDistanceUnit? _decodeUnit(String? raw) {
    if (raw == null) {
      return null;
    }
    for (final unit in ImportDistanceUnit.values) {
      if (unit.name == raw) {
        return unit;
      }
    }
    return null;
  }

  ImportDistanceUnit _resolveInitialUnit(
    ImportUnitDetection detection,
    ImportDistanceUnit fallback,
  ) {
    if (detection.hasGuess && !detection.ambiguous) {
      return detection.unit!;
    }
    final preferred = _lastPreferredUnit;
    if (preferred != null) {
      return preferred;
    }
    if (detection.hasGuess && detection.unit != null) {
      return detection.unit!;
    }
    return fallback;
  }

  Future<void> _setMappingUnit(ImportDistanceUnit unit) async {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    setState(() {
      _mapping = ImportMapping(
        assignments: Map.of(mapping.assignments),
        distanceUnit: unit,
      );
      _validation = null;
      _lastPreferredUnit = unit;
    });
    await _persistUnitPreference(unit);
  }

  Future<void> _promptUnitOverride() async {
    final mapping = _mapping;
    if (mapping == null) {
      return;
    }
    final selected = await showDialog<ImportDistanceUnit>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select units'),
          children: [
            for (final unit in ImportDistanceUnit.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(unit),
                child: Text(unit.label),
              ),
          ],
        );
      },
    );
    if (selected != null && selected != mapping.distanceUnit) {
      await _setMappingUnit(selected);
    }
  }

  Widget _buildUnitDetectionInfo(ImportPreview preview, ImportMapping mapping) {
    final detection = preview.unitDetection;
    final theme = Theme.of(context);
    final headline = detection.hasGuess
        ? detection.ambiguous
            ? 'Detected ${detection.unit!.label.toLowerCase()} (confidence low — confirm).'
            : 'Detected ${detection.unit!.label.toLowerCase()} automatically.'
        : 'Units not detected. Defaulted to ${mapping.distanceUnit.label.toLowerCase()}.';
    final bulletNotes = <String>[];
    if (detection.reason != null && detection.reason!.isNotEmpty) {
      bulletNotes.add(detection.reason!);
    }
    for (final note in detection.evidence) {
      if (!bulletNotes.contains(note)) {
        bulletNotes.add(note);
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                detection.ambiguous ? Icons.help_outline : Icons.straighten,
                size: 18,
                color: detection.ambiguous
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (bulletNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final note in bulletNotes)
              Padding(
                padding: const EdgeInsets.only(left: 26, bottom: 2),
                child: Text(
                  '• $note',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget? _buildUnitInferenceBanner(ImportPreview preview, ImportMapping mapping) {
    final detection = preview.unitDetection;
    if (!detection.hasGuess || detection.ambiguous) {
      return null;
    }
    if (detection.unit != mapping.distanceUnit) {
      return null;
    }
    final theme = Theme.of(context);
    final reasonLabel = _inferenceSummary(detection.reason);
    final label =
        'Units set to ${mapping.distanceUnit.label.toLowerCase()}$reasonLabel';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.straighten, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: _promptUnitOverride,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  String _inferenceSummary(String? reason) {
    if (reason == null || reason.isEmpty) {
      return ' (auto)';
    }
    final lower = reason.toLowerCase();
    if (lower.contains('header')) {
      return ' (inferred from header)';
    }
    if (lower.contains('directive')) {
      return ' (from unit directive)';
    }
    if (lower.contains('filename')) {
      return ' (from filename)';
    }
    if (lower.contains('spacing')) {
      return ' (from spacing heuristic)';
    }
    if (lower.contains('sample')) {
      return ' (based on sample text)';
    }
    return ' (auto)';
  }

  Widget? _buildConversionBanner(ImportMapping mapping) {
    if (mapping.distanceUnit != ImportDistanceUnit.meters) {
      return null;
    }
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ResiCheck stores a-spacing in feet. Meter values will be converted automatically.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _error = null;
      _session = null;
      _mapping = null;
      _validation = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: const ['csv', 'txt', 'dat', 'xlsx'],
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() {
          _loading = false;
        });
        return;
      }
      final file = result.files.first;
      if (file.bytes == null) {
        setState(() {
          _loading = false;
          _error = 'Unable to read file contents.';
        });
        return;
      }
      final source = ImportSource(name: file.name, bytes: file.bytes!);
      final session = await _service.load(source);
      if (!mounted) {
        return;
      }
      final auto = _service.autoMap(session.preview);
      final resolvedUnit = _resolveInitialUnit(session.preview.unitDetection, auto.distanceUnit);
      setState(() {
        _session = session;
        _mapping = ImportMapping(
          assignments: Map.of(auto.assignments),
          distanceUnit: resolvedUnit,
        );
        _validation = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Import failed: $error';
      });
    }
  }

  void _updateAssignment(int columnIndex, ImportColumnTarget? target) {
    final mapping = _mapping;
    if (mapping == null) return;
    final updated = Map<int, ImportColumnTarget>.from(mapping.assignments);
    if (target == null) {
      updated.remove(columnIndex);
    } else {
      updated.removeWhere((key, value) => value == target);
      updated[columnIndex] = target;
    }
    setState(() {
      _mapping = ImportMapping(assignments: updated, distanceUnit: mapping.distanceUnit);
      _validation = null;
    });
  }

  Future<void> _validate() async {
    final session = _session;
    final mapping = _mapping;
    if (session == null || mapping == null) {
      return;
    }
    setState(() {
      _validating = true;
      _validation = null;
      _error = null;
    });
    try {
      final validation = _service.validate(session, mapping);
      if (!mounted) return;
      setState(() {
        _validation = validation;
        _validating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _validating = false;
        _error = 'Validation failed: $error';
      });
    }
  }

  void _completeImport() {
    final validation = _validation;
    if (validation == null || !validation.isValid) {
      setState(() {
        _error = 'Validate the file before importing.';
      });
      return;
    }

    if (_destination == _ImportDestination.newSite) {
      final siteId = _siteIdController.text.trim();
      final displayName = _displayNameController.text.trim().isEmpty
          ? siteId
          : _displayNameController.text.trim();
      if (siteId.isEmpty) {
        setState(() => _error = 'Site ID is required for new sites.');
        return;
      }
      final site = _service.createSite(
        siteId: siteId,
        displayName: displayName,
        validation: validation,
        powerMilliAmps: widget.project.defaultPowerMilliAmps,
        stacks: widget.project.defaultStacks,
        soil: widget.project.sites.firstOrNull?.soil ?? SoilType.unknown,
        moisture: widget.project.sites.firstOrNull?.moisture ?? MoistureLevel.normal,
      );
      Navigator.of(context).pop(ImportSheetOutcome.newSite(site));
      return;
    }

    final targetId = _selectedMergeSiteId;
    if (targetId == null) {
      setState(() => _error = 'Choose a site to merge into.');
      return;
    }
    final targetSite = widget.project.siteById(targetId);
    if (targetSite == null) {
      setState(() => _error = 'Selected site not found in project.');
      return;
    }
    final merged = _service.mergeIntoSite(
      base: targetSite,
      validation: validation,
      overwrite: _overwrite,
    );
    Navigator.of(context).pop(
      ImportSheetOutcome.merge(mergeIntoSiteId: targetId, site: merged),
    );
  }
}
