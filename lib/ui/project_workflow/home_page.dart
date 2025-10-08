import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/project.dart';
import '../../services/storage_service.dart';
import 'project_shell.dart';

class ProjectWorkflowHomePage extends StatefulWidget {
  const ProjectWorkflowHomePage({super.key});

  @override
  State<ProjectWorkflowHomePage> createState() => _ProjectWorkflowHomePageState();
}

class _ProjectWorkflowHomePageState extends State<ProjectWorkflowHomePage> {
  final ProjectStorageService _storage = ProjectStorageService();
  late Future<List<ProjectSummary>> _recentFuture;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
      body: FutureBuilder<List<ProjectSummary>>(
        future: _recentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
                      'No projects found. Create a new project to start logging field data.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Create project'),
                      onPressed: _showCreateDialog,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: projects.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final summary = projects[index];
              return ListTile(
                leading: const Icon(Icons.workspaces_outline),
                title: Text(summary.projectName),
                subtitle: Text('Last opened: ${summary.lastOpened.toLocal()}'),
                onTap: () => _openProject(summary),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openProject(ProjectSummary summary) async {
    final record = await _storage.loadProjectFromPath(summary.path);
    if (!mounted) return;
    if (record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project ${summary.projectName}')),
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

class _NewProjectResult {
  _NewProjectResult({required this.name, required this.spacings});

  final String name;
  final List<double> spacings;
}
