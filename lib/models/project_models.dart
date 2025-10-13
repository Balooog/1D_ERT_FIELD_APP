import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

export 'enums.dart' show ArrayType;

part 'project_models.g.dart';

enum Direction { a, b }

const _unset = Object();

@JsonSerializable()
class SpacingPoint {
  const SpacingPoint({
    required this.spacingMeters,
    this.rho,
    this.excluded = false,
    this.note = '',
  });

  factory SpacingPoint.fromJson(Map<String, dynamic> json) =>
      _$SpacingPointFromJson(json);

  Map<String, dynamic> toJson() => _$SpacingPointToJson(this);

  final double spacingMeters;
  final double? rho;
  final bool excluded;
  final String note;

  double? get sigma => (rho != null && rho != 0) ? 1.0 / rho! : null;

  SpacingPoint copyWith({
    double? spacingMeters,
    Object? rho = _unset,
    bool? excluded,
    String? note,
  }) {
    return SpacingPoint(
      spacingMeters: spacingMeters ?? this.spacingMeters,
      rho: identical(rho, _unset) ? this.rho : rho as double?,
      excluded: excluded ?? this.excluded,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SpacingPoint &&
        spacingMeters == other.spacingMeters &&
        rho == other.rho &&
        excluded == other.excluded &&
        note == other.note;
  }

  @override
  int get hashCode => Object.hash(spacingMeters, rho, excluded, note);
}

@JsonSerializable(explicitToJson: true)
class DirectionReadings {
  DirectionReadings({
    required this.dir,
    required List<SpacingPoint> points,
  }) : points = List.unmodifiable(points);

  factory DirectionReadings.fromJson(Map<String, dynamic> json) =>
      _$DirectionReadingsFromJson(json);

  Map<String, dynamic> toJson() => _$DirectionReadingsToJson(this);

  final Direction dir;
  final List<SpacingPoint> points;

  int get nIncluded => points.where((p) => p.rho != null && !p.excluded).length;

  Iterable<SpacingPoint> get included =>
      points.where((p) => p.rho != null && !p.excluded);

  DirectionReadings copyWith({
    Direction? dir,
    List<SpacingPoint>? points,
  }) {
    return DirectionReadings(
      dir: dir ?? this.dir,
      points: points ?? this.points,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DirectionReadings &&
        dir == other.dir &&
        const ListEquality<SpacingPoint>().equals(points, other.points);
  }

  @override
  int get hashCode => Object.hash(dir, const ListEquality().hash(points));
}

@JsonSerializable(explicitToJson: true)
class Site {
  Site({
    required this.siteId,
    this.displayName,
    required this.dirA,
    required this.dirB,
    Map<String, dynamic>? meta,
  }) : meta = meta == null ? null : Map.unmodifiable(meta);

  factory Site.fromJson(Map<String, dynamic> json) => _$SiteFromJson(json);

  Map<String, dynamic> toJson() => _$SiteToJson(this);

  final String siteId;
  final String? displayName;
  final DirectionReadings dirA;
  final DirectionReadings dirB;
  final Map<String, dynamic>? meta;

  int get nIncluded => dirA.nIncluded + dirB.nIncluded;

  Site copyWith({
    String? siteId,
    Object? displayName = _unset,
    DirectionReadings? dirA,
    DirectionReadings? dirB,
    Object? meta = _unset,
  }) {
    Map<String, dynamic>? resolveMeta() {
      if (identical(meta, _unset)) {
        return this.meta;
      }
      final resolved = meta as Map<String, dynamic>?;
      return resolved == null ? null : Map.unmodifiable(resolved);
    }

    return Site(
      siteId: siteId ?? this.siteId,
      displayName: identical(displayName, _unset)
          ? this.displayName
          : displayName as String?,
      dirA: dirA ?? this.dirA,
      dirB: dirB ?? this.dirB,
      meta: resolveMeta(),
    );
  }

  DirectionReadings readingsFor(Direction direction) {
    switch (direction) {
      case Direction.a:
        return dirA;
      case Direction.b:
        return dirB;
    }
  }

  Site updateReadings(Direction direction, DirectionReadings readings) {
    switch (direction) {
      case Direction.a:
        return copyWith(dirA: readings);
      case Direction.b:
        return copyWith(dirB: readings);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Site &&
        siteId == other.siteId &&
        displayName == other.displayName &&
        dirA == other.dirA &&
        dirB == other.dirB &&
        const DeepCollectionEquality().equals(meta, other.meta);
  }

  @override
  int get hashCode => Object.hash(
        siteId,
        displayName,
        dirA,
        dirB,
        const DeepCollectionEquality().hash(meta),
      );
}

@JsonSerializable(explicitToJson: true)
class Project {
  Project({
    required this.projectName,
    required this.arrayType,
    required List<double> spacingsMeters,
    required List<Site> sites,
  })  : spacingsMeters = List.unmodifiable(spacingsMeters),
        sites = List.unmodifiable(sites);

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  final String projectName;
  final String arrayType;
  final List<double> spacingsMeters;
  final List<Site> sites;

  Project copyWith({
    String? projectName,
    String? arrayType,
    List<double>? spacingsMeters,
    List<Site>? sites,
  }) {
    return Project(
      projectName: projectName ?? this.projectName,
      arrayType: arrayType ?? this.arrayType,
      spacingsMeters: spacingsMeters ?? this.spacingsMeters,
      sites: sites ?? this.sites,
    );
  }

  Site? siteById(String siteId) {
    for (final site in sites) {
      if (site.siteId == siteId) {
        return site;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Project &&
        projectName == other.projectName &&
        arrayType == other.arrayType &&
        const ListEquality<double>()
            .equals(spacingsMeters, other.spacingsMeters) &&
        const ListEquality<Site>().equals(sites, other.sites);
  }

  @override
  int get hashCode => Object.hash(
        projectName,
        arrayType,
        const ListEquality<double>().hash(spacingsMeters),
        const ListEquality<Site>().hash(sites),
      );
}

enum QcColor { green, yellow, red }

@JsonSerializable()
class QcStats {
  const QcStats({
    this.rmsPercent,
    this.chi2,
    this.green = 0,
    this.yellow = 0,
    this.red = 0,
  });

  factory QcStats.fromJson(Map<String, dynamic> json) =>
      _$QcStatsFromJson(json);

  Map<String, dynamic> toJson() => _$QcStatsToJson(this);

  final double? rmsPercent;
  final double? chi2;
  final int green;
  final int yellow;
  final int red;

  QcStats copyWith({
    Object? rmsPercent = _unset,
    Object? chi2 = _unset,
    int? green,
    int? yellow,
    int? red,
  }) {
    return QcStats(
      rmsPercent: identical(rmsPercent, _unset)
          ? this.rmsPercent
          : rmsPercent as double?,
      chi2: identical(chi2, _unset) ? this.chi2 : chi2 as double?,
      green: green ?? this.green,
      yellow: yellow ?? this.yellow,
      red: red ?? this.red,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is QcStats &&
        rmsPercent == other.rmsPercent &&
        chi2 == other.chi2 &&
        green == other.green &&
        yellow == other.yellow &&
        red == other.red;
  }

  @override
  int get hashCode => Object.hash(rmsPercent, chi2, green, yellow, red);
}

class ResidualPoint {
  const ResidualPoint({
    required this.spacing,
    required this.residualPercent,
    required this.color,
    required this.excluded,
  });

  final double spacing;
  final double residualPercent;
  final QcColor color;
  final bool excluded;
}
