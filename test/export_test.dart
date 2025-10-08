import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/direction_reading.dart';
import 'package:ves_qc/models/project.dart';
import 'package:ves_qc/models/site.dart';
import 'package:ves_qc/services/export_service.dart';
import 'package:ves_qc/services/storage_service.dart';

void main() {
  test('CSV exporter writes ordered spacings', () async {
    final tempDir = await Directory.systemTemp.createTemp('resicheck_test');
    final storage = ProjectStorageService(overrideRoot: tempDir);
    final project = ProjectRecord.newProject(
      projectId: 'p1',
      projectName: 'Export Test',
      canonicalSpacingsFeet: const [2.5, 5, 10],
    );
    final site = SiteRecord(
      siteId: 'SiteA',
      displayName: 'Site A',
      spacings: [
        SpacingRecord(
          spacingFeet: 10,
          orientationA: DirectionReadingHistory(
            orientation: OrientationKind.a,
            label: 'N–S',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 50,
              ),
            ],
          ),
          orientationB: DirectionReadingHistory(
            orientation: OrientationKind.b,
            label: 'W–E',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 55,
              ),
            ],
          ),
        ),
        SpacingRecord(
          spacingFeet: 5,
          orientationA: DirectionReadingHistory(
            orientation: OrientationKind.a,
            label: 'N–S',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 45,
              ),
            ],
          ),
          orientationB: DirectionReadingHistory(
            orientation: OrientationKind.b,
            label: 'W–E',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 44,
              ),
            ],
          ),
        ),
      ],
    );
    final storageProject = await storage.saveProject(project);
    final exportService = ExportService(storage);
    final csvFile = await exportService.exportFieldCsv(storageProject, site);
    final lines = await csvFile.readAsLines();
    expect(lines.length, greaterThan(1));
    final spacings = lines
        .skip(1)
        .where((line) => line.isNotEmpty)
        .map((line) => double.parse(line.split(',')[2]))
        .toList();
    final sortedSpacings = [...spacings]..sort();
    expect(spacings, sortedSpacings);
    final datFile = await exportService.exportSurferDat(storageProject, site);
    final datLines = await datFile.readAsLines();
    final datSpacings = datLines
        .skip(4)
        .where((line) => line.isNotEmpty)
        .map((line) => double.parse(line.split(',').first))
        .toList();
    final sortedDatSpacings = [...datSpacings]..sort();
    expect(datSpacings, sortedDatSpacings);
  });
}
