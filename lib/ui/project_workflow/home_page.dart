import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/project.dart';
import '../../services/storage_service.dart';
import '../import/import_sheet.dart';
import 'project_shell.dart';

class ProjectWorkflowHomePage extends StatefulWidget {
  ProjectWorkflowHomePage({
    super.key,
    ProjectStorageService? storage,
  }) : storage = storage ?? ProjectStorageService();

  final ProjectStorageService storage;

  @override
  State<ProjectWorkflowHomePage> createState() =>
      _ProjectWorkflowHomePageState();
}

class _ProjectWorkflowHomePageState extends State<ProjectWorkflowHomePage> {
  late Future<List<ProjectSummary>> _recentFuture;

  ProjectStorageService get _storage => widget.storage;

  @override
  void initState() {
    super.initState();
    _recentFuture = _loadProjects();
  }

  Future<void> _refresh() async {
    setState(() {
      _recentFuture = _loadProjects();
    });
  }

  Future<List<ProjectSummary>> _loadProjects() async {
    await _storage.ensureSampleProject();
    return _storage.recentProjects();
  }

  Future<void> _startImport() async {
    final name = await _promptImportProjectName();
    if (name == null) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final tempProject = ProjectRecord.newProject(
      projectId: 'import-${DateTime.now().millisecondsSinceEpoch}',
      projectName: trimmed,
    );
    final outcome = await showModalBottomSheet<ImportSheetOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ImportSheet(project: tempProject),
    );
    if (!mounted) return;
    if (outcome == null) {
      return;
    }
    final created = await _storage.createProject(trimmed);
    final directory = await _storage.projectDirectory(created);
    final updated = created.upsertSite(outcome.site);
    await _storage.saveProject(updated, directoryOverride: directory);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectShell(
        initialProject: updated,
        storageService: _storage,
        projectDirectory: directory,
      ),
    ));
    await _refresh();
  }

  Future<String?> _promptImportProjectName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                return;
              }
              Navigator.of(context).pop(value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            unawaited(_startImport()),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('ResiCheck Projects'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh projects list',
                onPressed: _refresh,
              ),
            ],
          ),
          body: FutureBuilder<List<ProjectSummary>>(
            future: _recentFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _LoadingProjects(
                  onImport: () => unawaited(_startImport()),
                  onNewProject: _showCreateDialog,
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Failed to load projects: ${snapshot.error}'),
                );
              }
              final projects = snapshot.data ?? const [];
              if (projects.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.folder_open, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          'No projects found. Import existing data (Ctrl+I) or create a new project.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        _QuickActions(
                          onImport: () => unawaited(_startImport()),
                          onNewProject: _showCreateDialog,
                          alignment: WrapAlignment.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: projects.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _QuickActions(
                      onImport: () => unawaited(_startImport()),
                      onNewProject: _showCreateDialog,
                    );
                  }
                  final summary = projects[index - 1];
                  return Column(
                    children: [
                      if (index == 1) const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.workspaces_outline),
                        title: Text(summary.projectName),
                        subtitle: Text(
                          'Last opened: ${summary.lastOpened.toLocal()}',
                        ),
                        onTap: () => _openProject(summary),
                      ),
                      const Divider(height: 1),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openProject(ProjectSummary summary) async {
    final record = await _storage.loadProjectFromPath(summary.path);
    if (!mounted) return;
    if (record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to open project ${summary.projectName}')),
      );
      return;
    }
    final directory = Directory(summary.path);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectShell(
        initialProject: record,
        storageService: _storage,
        projectDirectory: directory,
      ),
    ));
    await _refresh();
  }

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();
    final spacingsController = TextEditingController(text: '2.5,5,10,20,40,60');
    final result = await showDialog<_NewProjectResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Project name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: spacingsController,
              decoration: const InputDecoration(
                labelText: 'a-spacings (ft)',
                helperText: 'Comma separated, per project defaults',
              ),
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
              final name = controller.text.trim();
              if (name.isEmpty) {
                return;
              }
              final spacings = spacingsController.text
                  .split(',')
                  .map((value) => double.tryParse(value.trim()))
                  .whereType<double>()
                  .toList();
              Navigator.of(context)
                  .pop(_NewProjectResult(name: name, spacings: spacings));
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result == null) {
      return;
    }
    final project = await _storage.createProject(
      result.name,
      canonicalSpacingsFeet: result.spacings.isEmpty ? null : result.spacings,
    );
    final directory = await _storage.projectDirectory(project);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectShell(
        initialProject: project,
        storageService: _storage,
        projectDirectory: directory,
      ),
    ));
    await _refresh();
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onImport,
    required this.onNewProject,
    this.alignment = WrapAlignment.start,
  });

  final VoidCallback onImport;
  final VoidCallback onNewProject;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: alignment,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Import from file'),
            onPressed: onImport,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New Project'),
            onPressed: onNewProject,
          ),
        ],
      ),
    );
  }
}

class _LoadingProjects extends StatelessWidget {
  const _LoadingProjects({
    required this.onImport,
    required this.onNewProject,
  });

  final VoidCallback onImport;
  final VoidCallback onNewProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading projects…',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _QuickActions(
            onImport: onImport,
            onNewProject: onNewProject,
            alignment: WrapAlignment.center,
          ),
        ],
      ),
    );
  }
}

class _NewProjectResult {
  _NewProjectResult({required this.name, required this.spacings});

  final String name;
  final List<double> spacings;
}
