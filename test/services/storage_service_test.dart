import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:resicheck/services/storage_service.dart';

void main() {
  group('ProjectStorageService', () {
    test('falls back to provided root when documents directory resolver fails',
        () async {
      final tempRoot =
          await Directory.systemTemp.createTemp('resicheck_fallback_test');
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final service = ProjectStorageService(
        documentsDirectoryResolver: () =>
            Future<Directory>.error(Exception('documents directory missing')),
        fallbackRootResolver: () => tempRoot,
        documentsDirectoryTimeout: const Duration(milliseconds: 50),
      );

      final project = await service.createProject('Sample Project');

      final rootPath = p.join(tempRoot.path, 'ResiCheckProjects');
      final projectPath = p.join(rootPath, 'Sample_Project');
      expect(await Directory(projectPath).exists(), isTrue);

      final stored = await service.loadProject(Directory(projectPath));
      expect(stored, isNotNull);
      expect(stored?.projectName, equals(project.projectName));
    });
  });
}
