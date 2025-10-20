import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/project.dart';
import '../../models/site.dart';
import '../../services/export_service.dart';

enum ExcelExportScope { site, project }

class ExportSheetResult {
  const ExportSheetResult({
    required this.scope,
    required this.style,
    required this.includeGps,
    required this.openWhenDone,
  });

  final ExcelExportScope scope;
  final ExcelStyle style;
  final bool includeGps;
  final bool openWhenDone;
}

class ExportSheet extends StatefulWidget {
  const ExportSheet({
    super.key,
    required this.project,
    required this.selectedSite,
  });

  final ProjectRecord project;
  final SiteRecord? selectedSite;

  static Future<ExportSheetResult?> show({
    required BuildContext context,
    required ProjectRecord project,
    required SiteRecord? selectedSite,
  }) {
    return showModalBottomSheet<ExportSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ExportSheet(
        project: project,
        selectedSite: selectedSite,
      ),
    );
  }

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  static const _styleKey = 'export.style';
  static const _gpsKey = 'export.includeGps';
  static const _openKey = 'export.openFile';

  ExcelExportScope _scope = ExcelExportScope.project;
  ExcelStyle _style = ExcelStyle.updated;
  bool _includeGps = false;
  bool _openWhenDone = false;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _scope = widget.selectedSite != null
        ? ExcelExportScope.site
        : ExcelExportScope.project;
    unawaited(_restorePreferences());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = widget.project;
    final site = widget.selectedSite;
    final siteEnabled = site != null;
    final exportDisabled =
        (_scope == ExcelExportScope.site && !siteEnabled) || _loadingPrefs;
    final traditionalEnabled = _scope == ExcelExportScope.site;

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Export Excel'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                Text(
                  'Scope',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                RadioGroup<ExcelExportScope>(
                  groupValue: _scope,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    _handleScopeChanged(value);
                  },
                  child: Column(
                    children: [
                      RadioListTile<ExcelExportScope>(
                        value: ExcelExportScope.site,
                        enabled: siteEnabled,
                        title: const Text('Selected site'),
                        subtitle: Text(
                          siteEnabled
                              ? site.displayName
                              : 'Select a site to enable this option',
                        ),
                      ),
                      RadioListTile<ExcelExportScope>(
                        value: ExcelExportScope.project,
                        title: const Text('All project sites'),
                        subtitle: Text(
                          '${project.sites.length} site(s) in this project',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Table styling',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                RadioGroup<ExcelStyle>(
                  groupValue: _style,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    if (!traditionalEnabled &&
                        value == ExcelStyle.traditional) {
                      return;
                    }
                    _handleStyleChanged(value);
                  },
                  child: Column(
                    children: [
                      const RadioListTile<ExcelStyle>(
                        value: ExcelStyle.updated,
                        title: Text('Updated (Modern)'),
                      ),
                      RadioListTile<ExcelStyle>(
                        value: ExcelStyle.traditional,
                        enabled: traditionalEnabled,
                        title: const Text('Traditional'),
                        subtitle: traditionalEnabled
                            ? const Text('Single-sheet, TABLE 1 layout')
                            : const Text(
                                'Available only when exporting a single site'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include GPS if available'),
                  value: _includeGps,
                  onChanged: _handleIncludeGpsChanged,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Open file when done'),
                  value: _openWhenDone,
                  onChanged: _handleOpenWhenDoneChanged,
                ),
              ],
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: FilledButton(
                onPressed: exportDisabled ? null : _handleExport,
                child: const Text('Export Excel'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleScopeChanged(ExcelExportScope? scope) {
    if (scope == null) {
      return;
    }
    setState(() {
      _scope = scope;
      if (_scope == ExcelExportScope.project &&
          _style == ExcelStyle.traditional) {
        _style = ExcelStyle.updated;
      }
    });
  }

  void _handleStyleChanged(ExcelStyle? style) {
    if (style == null) {
      return;
    }
    setState(() {
      _style = style;
    });
  }

  void _handleIncludeGpsChanged(bool? value) {
    setState(() {
      _includeGps = value ?? false;
    });
  }

  void _handleOpenWhenDoneChanged(bool? value) {
    setState(() {
      _openWhenDone = value ?? false;
    });
  }

  Future<void> _handleExport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_styleKey, _style.name);
    await prefs.setBool(_gpsKey, _includeGps);
    await prefs.setBool(_openKey, _openWhenDone);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      ExportSheetResult(
        scope: _scope,
        style: _style,
        includeGps: _includeGps,
        openWhenDone: _openWhenDone,
      ),
    );
  }

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedStyle = prefs.getString(_styleKey);
      final includeGps = prefs.getBool(_gpsKey);
      final openWhenDone = prefs.getBool(_openKey);
      setState(() {
        _style = ExcelStyle.values.firstWhere(
          (value) => value.name == storedStyle,
          orElse: () => ExcelStyle.updated,
        );
        _includeGps = includeGps ?? false;
        _openWhenDone = openWhenDone ?? false;
        if (_scope == ExcelExportScope.project &&
            _style == ExcelStyle.traditional) {
          _style = ExcelStyle.updated;
        }
        _loadingPrefs = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _style = ExcelStyle.updated;
        _includeGps = false;
        _openWhenDone = false;
        _loadingPrefs = false;
      });
    }
  }
}
