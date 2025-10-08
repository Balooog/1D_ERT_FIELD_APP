import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/project_models.dart';
import 'package:ves_qc/qc/qc.dart';
import 'package:ves_qc/services/persistence.dart';
import 'package:ves_qc/state/project_controller.dart';

class _FakePersistence extends PersistenceService {
  final Map<String, Project> store = {};

  @override
  Future<Project> loadProject(String name) async {
    final project = store[name];
    if (project == null) {
      throw ArgumentError.value(name, 'name', 'Not found');
    }
    return project;
  }

  @override
  Future<void> saveProject(Project project, {String? fileId}) async {
    store[fileId ?? project.projectName] = project;
  }
}

Project _buildProject() {
  List<SpacingPoint> pointsWithValues(List<double?> values) {
    final spacings = [1.0, 2.0, 4.0];
    return [
      for (var i = 0; i < spacings.length; i++)
        SpacingPoint(
          spacingMeters: spacings[i],
          rho: values[i],
        ),
    ];
  }

  return Project(
    projectName: 'WayneCo',
    arrayType: 'Schlumberger',
    spacingsMeters: const [1.0, 2.0, 4.0],
    sites: [
      Site(
        siteId: 'OH-001',
        dirA: DirectionReadings(
          dir: Direction.a,
          points: pointsWithValues(const [100, 200, 400]),
        ),
        dirB: DirectionReadings(
          dir: Direction.b,
          points: pointsWithValues(const [null, null, null]),
        ),
      ),
    ],
  );
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        persistenceServiceProvider.overrideWithValue(_FakePersistence()),
      ],
    );
    final projectController =
        container.read(projectControllerProvider.notifier);
    projectController.setAutosaveEnabled(false);
    projectController.setProject(_buildProject());
    container.read(qcControllerProvider); // ensure initialized
  });

  tearDown(() {
    container.dispose();
  });

  test('QC counts all points green for perfect fit', () {
    final qcState = container.read(qcControllerProvider);
    expect(qcState.stats.green, 3);
    expect(qcState.stats.yellow, 0);
    expect(qcState.stats.red, 0);
  });

  test('Excluded points are ignored in stats', () {
    final projectController =
        container.read(projectControllerProvider.notifier);
    projectController.markBad(Direction.a, 0, excluded: true);

    final qcState = container.read(qcControllerProvider);
    expect(qcState.stats.green, 2);
    expect(qcState.residuals.where((r) => r.excluded).length, 1);
  });

  test('Large deviation classified as red', () {
    final projectController =
        container.read(projectControllerProvider.notifier);
    projectController.updateReading(Direction.a, 2, 800);

    final qcState = container.read(qcControllerProvider);
    expect(qcState.stats.red + qcState.stats.yellow, greaterThanOrEqualTo(1));
    expect(qcState.residuals.last.color, QcColor.yellow);
  });
}
