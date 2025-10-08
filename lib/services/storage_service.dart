import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';

const _projectFileName = 'project.resicheck.json';
const _exportsFolderName = 'exports';
const _sitesFolderName = 'sites';
const _sampleProjectFolderName = 'Sample_Project';
const _sampleProjectAsset = 'assets/samples/sample_project.json';

class ProjectStorageService {
  ProjectStorageService({Directory? overrideRoot}) : _overrideRoot = overrideRoot;

  final Directory? _overrideRoot;
  final _uuid = const Uuid();

  Future<Directory> _ensureRoot() async {
    final overrideRoot = _overrideRoot;
    if (overrideRoot != null) {
      if (!await overrideRoot.exists()) {
        await overrideRoot.create(recursive: true);
      }
      return overrideRoot;
    }
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'ResiCheckProjects'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<ProjectRecord> createProject(String name,
      {List<double>? canonicalSpacingsFeet}) async {
    final root = await _ensureRoot();
    final projectId = _uuid.v4();
    final safeName = _safeFolderName(name);
    final dir = Directory(p.join(root.path, safeName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final project = ProjectRecord.newProject(
      projectId: projectId,
      projectName: name,
      canonicalSpacingsFeet: canonicalSpacingsFeet,
    );
    return saveProject(project, directoryOverride: dir);
  }

  Future<void> ensureSampleProject() async {
    try {
      final root = await _ensureRoot();
      final directory = Directory(p.join(root.path, _sampleProjectFolderName));
      final file = File(p.join(directory.path, _projectFileName));
      if (await file.exists()) {
        return;
      }
      final raw = await rootBundle.loadString(_sampleProjectAsset);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final record = ProjectRecord.fromJson(json);
      await saveProject(record, directoryOverride: directory);
    } catch (error, stackTrace) {
      debugPrint('Failed to seed sample project: $error');
      debugPrint(stackTrace.toString());
    }
  }

  Future<ProjectRecord?> loadProject(Directory directory) async {
    final file = File(p.join(directory.path, _projectFileName));
    if (!await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final record = ProjectRecord.fromJson(json);
    return record.copyWith(updatedAt: DateTime.now());
  }

  Future<ProjectRecord> saveProject(
    ProjectRecord project, {
    Directory? directoryOverride,
  }) async {
    final root = await _ensureRoot();
    final directory = directoryOverride ??
        Directory(p.join(root.path, _safeFolderName(project.projectName)));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final updated = project.copyWith(updatedAt: DateTime.now());
    final file = File(p.join(directory.path, _projectFileName));
    await file.writeAsString(JsonEncoder.withIndent('  ').convert(updated.toJson()));
    return updated;
  }

  Future<Directory> projectDirectory(ProjectRecord project) async {
    final root = await _ensureRoot();
    return Directory(p.join(root.path, _safeFolderName(project.projectName)));
  }

  Future<List<ProjectSummary>> recentProjects({int limit = 20}) async {
    final root = await _ensureRoot();
    if (!await root.exists()) {
      return <ProjectSummary>[];
    }
    final children = await root
        .list()
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    final summaries = <ProjectSummary>[];
    for (final dir in children) {
      final file = File(p.join(dir.path, _projectFileName));
      if (!await file.exists()) {
        continue;
      }
      try {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final project = ProjectRecord.fromJson(json);
        summaries.add(ProjectSummary(
          projectId: project.projectId,
          projectName: project.projectName,
          lastOpened: project.updatedAt,
          path: dir.path,
        ));
      } catch (_) {
        continue;
      }
    }
    summaries.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    if (summaries.length > limit) {
      return summaries.sublist(0, limit);
    }
    return summaries;
  }

  Future<File> ensureExportFile(
    ProjectRecord project,
    String fileStem,
    String extension,
  ) async {
    final root = await _ensureRoot();
    final dir = Directory(
      p.join(root.path, _safeFolderName(project.projectName), _exportsFolderName),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final timestamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    final fileName = '${fileStem}_$timestamp.$extension';
    return File(p.join(dir.path, fileName));
  }

  Future<Directory> ensureSiteDirectory(
      ProjectRecord project, String siteId) async {
    final root = await _ensureRoot();
    final dir = Directory(p.join(root.path, _safeFolderName(project.projectName),
        _sitesFolderName, siteId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<ProjectRecord?> loadProjectFromPath(String path) async {
    return loadProject(Directory(path));
  }

  Future<File> createBackup(File existing) async {
    final backup = File('${existing.path}.bak.json');
    if (await existing.exists()) {
      await existing.copy(backup.path);
    }
    return backup;
  }

  String _safeFolderName(String name) {
    final trimmed = name.trim();
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9-_]'), '_');
    return sanitized.isEmpty ? 'Project_${DateTime.now().millisecondsSinceEpoch}' : sanitized;
  }
}

class ProjectAutosaveController {
  ProjectAutosaveController({
    required this.onPersist,
    this.interval = const Duration(seconds: 10),
  });

  final Duration interval;
  final Future<void> Function(ProjectRecord project) onPersist;

  Timer? _timer;
  ProjectRecord? _pending;

  void schedule(ProjectRecord project) {
    _pending = project;
    _timer?.cancel();
    _timer = Timer(interval, () async {
      final pending = _pending;
      if (pending != null) {
        await onPersist(pending);
      }
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    final pending = _pending;
    if (pending != null) {
      await onPersist(pending);
    }
    _pending = null;
  }

  void dispose() {
    _timer?.cancel();
    _pending = null;
  }
}
