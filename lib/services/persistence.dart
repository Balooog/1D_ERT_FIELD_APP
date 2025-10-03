import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/project_models.dart';

typedef DirectoryProvider = Future<Directory> Function();

class PersistenceService {
  PersistenceService({DirectoryProvider? directoryProvider})
      : _directoryProvider = directoryProvider ?? _defaultDirectoryProvider;

  final DirectoryProvider _directoryProvider;

  static const String defaultProjectFileId = 'lastUsed';

  Future<Project> loadProject(String name) async {
    final file = await _resolveProjectFile(name);
    if (!await file.exists()) {
      throw ArgumentError.value(name, 'name', 'Project not found');
    }
    final contents = await file.readAsString();
    final data = jsonDecode(contents) as Map<String, dynamic>;
    return Project.fromJson(data);
  }

  Future<Project?> tryLoadDefault() async {
    final file = await _resolveProjectFile(defaultProjectFileId);
    if (!await file.exists()) {
      return null;
    }
    final contents = await file.readAsString();
    final data = jsonDecode(contents) as Map<String, dynamic>;
    return Project.fromJson(data);
  }

  Future<void> saveProject(Project project, {String? fileId}) async {
    final fileIdOrName = fileId ?? project.projectName;
    final file = await _resolveProjectFile(fileIdOrName, ensureDir: true);
    final encoder = const JsonEncoder.withIndent('  ');
    final data = encoder.convert(project.toJson());
    await file.writeAsString(data);
  }

  Future<File> _resolveProjectFile(String name, {bool ensureDir = false}) async {
    final dir = await _directoryProvider();
    if (ensureDir && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeName = name.trim().isEmpty ? 'unnamed' : name.trim();
    final filename = '$safeName.resicheck.json';
    return File(p.join(dir.path, filename));
  }

  static Future<Directory> _defaultDirectoryProvider() async {
    final base = await getApplicationSupportDirectory();
    final target = Directory(p.join(base.path, 'ResiCheckProjects'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }
}

final persistenceServiceProvider = Provider<PersistenceService>((ref) {
  return PersistenceService();
});
