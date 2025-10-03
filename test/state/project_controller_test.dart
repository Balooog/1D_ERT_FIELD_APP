import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ves_qc/models/project_models.dart';
import 'package:ves_qc/services/persistence.dart';
import 'package:ves_qc/state/project_controller.dart';

class InMemoryPersistence extends PersistenceService {
  InMemoryPersistence() : super();

  final Map<String, Project> _store = {};

  @override
  Future<Project> loadProject(String name) async {
    final project = _store[name];
    if (project == null) {
      throw ArgumentError.value(name, 'name', 'Not found');
    }
    return project;
  }

  @override
  Future<void> saveProject(Project project, {String? fileId}) async {
    _store[fileId ?? project.projectName] = project;
  }
}

void main() {
  late InMemoryPersistence persistence;
  late ProviderContainer container;
  late ProjectController controller;

  setUp(() {
    persistence = InMemoryPersistence();
    container = ProviderContainer(overrides: [
      persistenceServiceProvider.overrideWithValue(persistence),
    ]);
    controller = container.read(projectControllerProvider.notifier);
    controller.setAutosaveEnabled(false);
  });

  tearDown(() {
    container.dispose();
  });

  Project _sampleProject() {
    final spacings = [1.0, 2.0, 5.0];
    List<SpacingPoint> buildPoints() => [
          for (final spacing in spacings)
            SpacingPoint(spacingMeters: spacing),
        ];
    return Project(
      projectName: 'WayneCo',
      arrayType: 'Schlumberger',
      spacingsMeters: spacings,
      sites: [
        Site(
          siteId: 'OH-001',
          dirA: DirectionReadings(dir: Direction.a, points: buildPoints()),
          dirB: DirectionReadings(dir: Direction.b, points: buildPoints()),
        ),
        Site(
          siteId: 'OH-002',
          dirA: DirectionReadings(dir: Direction.a, points: buildPoints()),
          dirB: DirectionReadings(dir: Direction.b, points: buildPoints()),
        ),
      ],
    );
  }

  test('updateReading mutates active site and marks dirty', () {
    controller.setProject(_sampleProject());
    controller.setActiveSite('OH-001');

    controller.updateReading(Direction.a, 0, 120);

    final state = container.read(projectControllerProvider);
    expect(state.hasUnsavedChanges, isTrue);
    final site = state.activeSite!;
    expect(site.dirA.points.first.rho, 120);
  });

  test('markBad toggles exclusion flag', () {
    controller.setProject(_sampleProject());
    controller.setActiveSite('OH-001');

    controller.markBad(Direction.b, 1, excluded: true);

    final site = container.read(projectControllerProvider).activeSite!;
    expect(site.dirB.points[1].excluded, isTrue);

    controller.markBad(Direction.b, 1, excluded: false);
    final siteAfter = container.read(projectControllerProvider).activeSite!;
    expect(siteAfter.dirB.points[1].excluded, isFalse);
  });

  test('updateReading allows clearing rho to null', () {
    controller.setProject(_sampleProject());
    controller.setActiveSite('OH-001');
    controller.updateReading(Direction.a, 0, 150);
    controller.updateReading(Direction.a, 0, null);

    final site = container.read(projectControllerProvider).activeSite!;
    expect(site.dirA.points[0].rho, isNull);
  });

  test('saveProject clears dirty flag and stores data', () async {
    controller.setProject(_sampleProject());
    controller.updateReading(Direction.a, 0, 111);

    await controller.saveProject();

    expect(container.read(projectControllerProvider).hasUnsavedChanges, isFalse);
    expect(persistence._store.containsKey('WayneCo'), isTrue);
  });

  test('loadProject replaces current project', () async {
    final project = _sampleProject();
    persistence._store['WayneCo'] = project;

    await controller.loadProject('WayneCo');

    final state = container.read(projectControllerProvider);
    expect(state.project, equals(project));
    expect(state.activeSiteId, 'OH-001');
  });

  test('setNote updates spacing note', () {
    controller.setProject(_sampleProject());
    controller.setActiveSite('OH-001');

    controller.setNote(Direction.a, 1, 'Repeat measurement');

    final site = container.read(projectControllerProvider).activeSite!;
    expect(site.dirA.points[1].note, 'Repeat measurement');
  });
}
