// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_models.dart';

SpacingPoint _$SpacingPointFromJson(Map<String, dynamic> json) => SpacingPoint(
      spacingMeters: (json['spacingMeters'] as num).toDouble(),
      rho: (json['rho'] as num?)?.toDouble(),
      excluded: json['excluded'] as bool? ?? false,
      note: json['note'] as String? ?? '',
    );

Map<String, dynamic> _$SpacingPointToJson(SpacingPoint instance) =>
    <String, dynamic>{
      'spacingMeters': instance.spacingMeters,
      'rho': instance.rho,
      'excluded': instance.excluded,
      'note': instance.note,
    };

DirectionReadings _$DirectionReadingsFromJson(Map<String, dynamic> json) =>
    DirectionReadings(
      dir: $enumDecode(_$DirectionEnumMap, json['dir']),
      points: (json['points'] as List<dynamic>)
          .map((e) => SpacingPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DirectionReadingsToJson(DirectionReadings instance) =>
    <String, dynamic>{
      'dir': _$DirectionEnumMap[instance.dir]!,
      'points': instance.points.map((e) => e.toJson()).toList(),
    };

const _$DirectionEnumMap = {
  Direction.a: 'a',
  Direction.b: 'b',
};

Site _$SiteFromJson(Map<String, dynamic> json) => Site(
      siteId: json['siteId'] as String,
      displayName: json['displayName'] as String?,
      dirA: DirectionReadings.fromJson(json['dirA'] as Map<String, dynamic>),
      dirB: DirectionReadings.fromJson(json['dirB'] as Map<String, dynamic>),
      meta: json['meta'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$SiteToJson(Site instance) => <String, dynamic>{
      'siteId': instance.siteId,
      'displayName': instance.displayName,
      'dirA': instance.dirA.toJson(),
      'dirB': instance.dirB.toJson(),
      'meta': instance.meta,
    };

Project _$ProjectFromJson(Map<String, dynamic> json) => Project(
      projectName: json['projectName'] as String,
      arrayType: json['arrayType'] as String,
      spacingsMeters: (json['spacingsMeters'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      sites: (json['sites'] as List<dynamic>)
          .map((e) => Site.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
      'projectName': instance.projectName,
      'arrayType': instance.arrayType,
      'spacingsMeters': instance.spacingsMeters,
      'sites': instance.sites.map((e) => e.toJson()).toList(),
    };

QcStats _$QcStatsFromJson(Map<String, dynamic> json) => QcStats(
      rmsPercent: (json['rmsPercent'] as num?)?.toDouble(),
      chi2: (json['chi2'] as num?)?.toDouble(),
      green: json['green'] as int? ?? 0,
      yellow: json['yellow'] as int? ?? 0,
      red: json['red'] as int? ?? 0,
    );

Map<String, dynamic> _$QcStatsToJson(QcStats instance) => <String, dynamic>{
      'rmsPercent': instance.rmsPercent,
      'chi2': instance.chi2,
      'green': instance.green,
      'yellow': instance.yellow,
      'red': instance.red,
    };
