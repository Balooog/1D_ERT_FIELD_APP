import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';

import '../core/logging.dart';
import '../models/project_models.dart';
import '../services/persistence.dart';

const _stateUnset = Object();

class ProjectState {
  const ProjectState({
    this.project,
    this.activeSiteId,
    this.activeDirection = Direction.a,
    this.isSaving = false,
    this.hasUnsavedChanges = false,
    this.autosaveEnabled = true,
  });

  final Project? project;
  final String? activeSiteId;
  final Direction activeDirection;
  final bool isSaving;
  final bool hasUnsavedChanges;
  final bool autosaveEnabled;

  Site? get activeSite => project != null && activeSiteId != null
      ? project!.siteById(activeSiteId!)
      : null;

  ProjectState copyWith({
    Object? project = _stateUnset,
    Object? activeSiteId = _stateUnset,
    Direction? activeDirection,
    bool? isSaving,
    bool? hasUnsavedChanges,
    bool? autosaveEnabled,
  }) {
    return ProjectState(
      project:
          identical(project, _stateUnset) ? this.project : project as Project?,
      activeSiteId: identical(activeSiteId, _stateUnset)
          ? this.activeSiteId
          : activeSiteId as String?,
      activeDirection: activeDirection ?? this.activeDirection,
      isSaving: isSaving ?? this.isSaving,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      autosaveEnabled: autosaveEnabled ?? this.autosaveEnabled,
    );
  }
}

class ProjectController extends StateNotifier<ProjectState> {
  ProjectController(this._persistence) : super(const ProjectState());

  final PersistenceService _persistence;
  Timer? _autosaveTimer;

  Future<void> ensureProjectLoaded() async {
    if (state.project != null) {
      return;
    }
    try {
      final project = await _persistence.tryLoadDefault();
      if (project == null) {
        LOG.w(
            'ProjectController', 'No default project available during hydrate');
        return;
      }
      LOG.i('ProjectController',
          'Loaded default project "${project.projectName}"');
      _setProject(project, markSaved: true);
    } catch (error, stackTrace) {
      LOG.e('ProjectController', 'Failed to load default project', error,
          stackTrace);
      rethrow;
    }
  }

  Future<void> ensureSitesIndexed() async {
    final project = state.project;
    if (project == null) {
      return;
    }
    final activeSiteId = state.activeSiteId;
    if (activeSiteId != null && project.siteById(activeSiteId) != null) {
      return;
    }
    final fallbackSiteId =
        project.sites.isNotEmpty ? project.sites.first.siteId : null;
    if (fallbackSiteId == null) {
      LOG.w('ProjectController', 'Hydrate requested but project has no sites.');
      return;
    }
    state = state.copyWith(activeSiteId: fallbackSiteId);
    LOG.i('ProjectController', 'Defaulted active site to $fallbackSiteId');
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  void setAutosaveEnabled(bool value) {
    if (state.autosaveEnabled == value) return;
    state = state.copyWith(autosaveEnabled: value);
    if (!value) {
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
    } else if (state.hasUnsavedChanges) {
      _scheduleAutosave();
    }
  }

  Future<void> loadProject(String projectName) async {
    final project = await _persistence.loadProject(projectName);
    _setProject(project, markSaved: true);
  }

  Future<bool> loadDefaultIfAvailable() async {
    final project = await _persistence.tryLoadDefault();
    if (project == null) {
      return false;
    }
    _setProject(project, markSaved: true);
    return true;
  }

  Future<void> saveProject({String? asName, String? fileId}) async {
    final project = state.project;
    if (project == null) return;
    final projectToSave =
        asName != null ? project.copyWith(projectName: asName) : project;
    state = state.copyWith(isSaving: true);
    try {
      await _persistence.saveProject(projectToSave, fileId: fileId);
      _setProject(projectToSave, markSaved: true);
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }

  void setProject(Project project) {
    _setProject(project, markSaved: false);
  }

  void setActiveSite(String siteId) {
    final project = state.project;
    if (project == null) return;
    if (project.siteById(siteId) == null) {
      throw ArgumentError.value(siteId, 'siteId', 'Site not found');
    }
    state = state.copyWith(activeSiteId: siteId);
  }

  void setActiveDirection(Direction direction) {
    state = state.copyWith(activeDirection: direction);
  }

  void updateReading(Direction direction, int spacingIndex, double? rho) {
    _modifyActiveSite(
        direction, spacingIndex, (point) => point.copyWith(rho: rho));
  }

  void markBad(Direction direction, int spacingIndex, {bool excluded = true}) {
    _modifyActiveSite(
        direction, spacingIndex, (point) => point.copyWith(excluded: excluded));
  }

  void setNote(Direction direction, int spacingIndex, String note) {
    _modifyActiveSite(
        direction, spacingIndex, (point) => point.copyWith(note: note));
  }

  void _modifyActiveSite(
    Direction direction,
    int spacingIndex,
    SpacingPoint Function(SpacingPoint) updater,
  ) {
    final project = state.project;
    final activeSiteId = state.activeSiteId;
    if (project == null || activeSiteId == null) {
      throw StateError('No active project/site set');
    }

    final siteIndex = project.sites.indexWhere((s) => s.siteId == activeSiteId);
    if (siteIndex == -1) {
      throw StateError('Active site not found in project');
    }

    final site = project.sites[siteIndex];
    final readings = site.readingsFor(direction);
    if (spacingIndex < 0 || spacingIndex >= readings.points.length) {
      throw RangeError.index(spacingIndex, readings.points, 'spacingIndex');
    }

    final updatedPoints = List<SpacingPoint>.from(readings.points);
    updatedPoints[spacingIndex] = updater(updatedPoints[spacingIndex]);

    final updatedReadings =
        readings.copyWith(points: List.unmodifiable(updatedPoints));
    final updatedSite = site.updateReadings(direction, updatedReadings);

    final updatedSites = List<Site>.from(project.sites);
    updatedSites[siteIndex] = updatedSite;

    final updatedProject =
        project.copyWith(sites: List.unmodifiable(updatedSites));
    _setProject(updatedProject, markSaved: false);
  }

  void _setProject(Project project, {required bool markSaved}) {
    final firstSiteId =
        project.sites.isNotEmpty ? project.sites.first.siteId : null;
    final currentActive = state.activeSiteId;
    final resolvedActive =
        currentActive != null && project.siteById(currentActive) != null
            ? currentActive
            : firstSiteId;
    state = state.copyWith(
      project: project,
      activeSiteId: resolvedActive,
      hasUnsavedChanges: markSaved ? false : true,
    );
    if (!markSaved) {
      _scheduleAutosave();
    }
  }

  void _scheduleAutosave() {
    if (!state.autosaveEnabled) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 1), () {
      if (!state.hasUnsavedChanges) return;
      unawaited(saveProject());
    });
  }
}

final projectControllerProvider =
    StateNotifierProvider<ProjectController, ProjectState>((ref) {
  final persistence = ref.watch(persistenceServiceProvider);
  return ProjectController(persistence);
});
