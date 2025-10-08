import 'dart:convert';

import 'package:collection/collection.dart';

import 'enums.dart';
import 'site.dart';

const currentProjectSchemaVersion = '1.1.0';

class ProjectRecord {
  ProjectRecord({
    required this.projectId,
    required this.projectName,
    required this.arrayType,
    required List<double> canonicalSpacingsFeet,
    required this.defaultPowerMilliAmps,
    required this.defaultStacks,
    List<SiteRecord>? sites,
    String? schemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : canonicalSpacingsFeet = List.unmodifiable(canonicalSpacingsFeet),
        sites = List.unmodifiable(sites ?? const <SiteRecord>[]),
        schemaVersion = schemaVersion ?? currentProjectSchemaVersion,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ProjectRecord.newProject({
    required String projectId,
    required String projectName,
    ArrayType arrayType = ArrayType.wenner,
    List<double>? canonicalSpacingsFeet,
  }) {
    return ProjectRecord(
      projectId: projectId,
      projectName: projectName,
      arrayType: arrayType,
      canonicalSpacingsFeet: canonicalSpacingsFeet ??
          const [2.5, 5, 10, 20, 40, 60],
      defaultPowerMilliAmps: 0.5,
      defaultStacks: 4,
    );
  }

  factory ProjectRecord.fromJson(Map<String, dynamic> json) {
    final migrated = ProjectSchemaMigration.migrate(json);
    return ProjectRecord(
      projectId: migrated['project_id'] as String,
      projectName: migrated['project_name'] as String,
      arrayType:
          ArrayType.values.byName(migrated['array_type'] as String? ?? 'wenner'),
      canonicalSpacingsFeet: (migrated['canonical_spacings_ft'] as List<dynamic>)
          .map((dynamic e) => (e as num).toDouble())
          .toList(),
      defaultPowerMilliAmps:
          (migrated['default_power_ma'] as num?)?.toDouble() ?? 0.5,
      defaultStacks: migrated['default_stacks'] as int? ?? 4,
      sites: (migrated['sites'] as List<dynamic>? ?? const [])
          .map((dynamic e) => SiteRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      schemaVersion: migrated['schema_version'] as String?,
      createdAt: DateTime.parse(migrated['created_at'] as String),
      updatedAt: DateTime.parse(migrated['updated_at'] as String),
    );
  }

  final String projectId;
  final String projectName;
  final ArrayType arrayType;
  final List<double> canonicalSpacingsFeet;
  final double defaultPowerMilliAmps;
  final int defaultStacks;
  final List<SiteRecord> sites;
  final String schemaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectRecord copyWith({
    String? projectId,
    String? projectName,
    ArrayType? arrayType,
    List<double>? canonicalSpacingsFeet,
    double? defaultPowerMilliAmps,
    int? defaultStacks,
    List<SiteRecord>? sites,
    String? schemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectRecord(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      arrayType: arrayType ?? this.arrayType,
      canonicalSpacingsFeet:
          canonicalSpacingsFeet ?? this.canonicalSpacingsFeet,
      defaultPowerMilliAmps: defaultPowerMilliAmps ?? this.defaultPowerMilliAmps,
      defaultStacks: defaultStacks ?? this.defaultStacks,
      sites: sites ?? this.sites,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  ProjectRecord addSite(SiteRecord site) {
    final updated = [...sites, site];
    return copyWith(sites: updated);
  }

  ProjectRecord updateSite(
    String siteId,
    SiteRecord Function(SiteRecord current) updater,
  ) {
    final updated = [...sites];
    final index = updated.indexWhere((element) => element.siteId == siteId);
    if (index == -1) {
      throw ArgumentError('Site $siteId not found');
    }
    updated[index] = updater(updated[index]);
    return copyWith(sites: updated);
  }

  ProjectRecord upsertSite(SiteRecord site) {
    final updated = [...sites];
    final index = updated.indexWhere((element) => element.siteId == site.siteId);
    if (index >= 0) {
      updated[index] = site;
    } else {
      updated.add(site);
    }
    return copyWith(sites: updated);
  }

  SiteRecord? siteById(String siteId) {
    return sites.firstWhereOrNull((site) => site.siteId == siteId);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': schemaVersion,
        'project_id': projectId,
        'project_name': projectName,
        'array_type': arrayType.name,
        'canonical_spacings_ft': canonicalSpacingsFeet,
        'default_power_ma': defaultPowerMilliAmps,
        'default_stacks': defaultStacks,
        'sites': sites.map((e) => e.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectRecord &&
        projectId == other.projectId &&
        projectName == other.projectName &&
        arrayType == other.arrayType &&
        const ListEquality<double>()
            .equals(canonicalSpacingsFeet, other.canonicalSpacingsFeet) &&
        defaultPowerMilliAmps == other.defaultPowerMilliAmps &&
        defaultStacks == other.defaultStacks &&
        const ListEquality<SiteRecord>().equals(sites, other.sites);
  }

  @override
  int get hashCode => Object.hash(
        projectId,
        projectName,
        arrayType,
        const ListEquality().hash(canonicalSpacingsFeet),
        defaultPowerMilliAmps,
        defaultStacks,
        const ListEquality().hash(sites),
      );

  @override
  String toString() => jsonEncode(toJson());
}

class ProjectSchemaMigration {
  static Map<String, dynamic> migrate(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as String? ?? '1.0.0';
    if (schemaVersion == currentProjectSchemaVersion) {
      return json;
    }

    final migrated = Map<String, dynamic>.from(json);
    migrated['schema_version'] = currentProjectSchemaVersion;
    migrated['created_at'] =
        (json['created_at'] as String? ?? DateTime.now().toIso8601String());
    migrated['updated_at'] =
        (json['updated_at'] as String? ?? DateTime.now().toIso8601String());
    migrated['canonical_spacings_ft'] =
        (json['canonical_spacings_ft'] as List<dynamic>? ??
                (json['spacings_ft'] as List<dynamic>? ?? const [2.5, 5, 10]))
            .map((dynamic e) => (e as num).toDouble())
            .toList();
    migrated['default_power_ma'] =
        (json['default_power_ma'] as num?)?.toDouble() ?? 0.5;
    migrated['default_stacks'] = json['default_stacks'] as int? ?? 4;
    return migrated;
  }
}

class ProjectSummary {
  ProjectSummary({
    required this.projectId,
    required this.projectName,
    required this.lastOpened,
    required this.path,
  });

  final String projectId;
  final String projectName;
  final DateTime lastOpened;
  final String path;
}
