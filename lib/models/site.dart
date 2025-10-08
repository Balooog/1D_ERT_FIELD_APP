import 'package:collection/collection.dart';

import 'calc.dart';
import 'direction_reading.dart';

enum SoilType {
  unknown,
  clay,
  sandy,
  gravelly,
  mixed,
}

extension SoilTypeLabel on SoilType {
  String get label {
    switch (this) {
      case SoilType.unknown:
        return 'Unknown';
      case SoilType.clay:
        return 'Clay / Clayey';
      case SoilType.sandy:
        return 'Sand / Sandy';
      case SoilType.gravelly:
        return 'Gravel / Coarse';
      case SoilType.mixed:
        return 'Mixed';
    }
  }
}

enum MoistureLevel { dry, normal, wet }

extension MoistureLevelLabel on MoistureLevel {
  String get label {
    switch (this) {
      case MoistureLevel.dry:
        return 'Dry';
      case MoistureLevel.normal:
        return 'Normal';
      case MoistureLevel.wet:
        return 'Wet';
    }
  }
}

class SpacingRecord {
  SpacingRecord({
    required this.spacingFeet,
    required DirectionReadingHistory orientationA,
    required DirectionReadingHistory orientationB,
    this.interpretation,
  })  : orientationA = orientationA,
        orientationB = orientationB;

  factory SpacingRecord.seed({
    required double spacingFeet,
    String? orientationALabel,
    String? orientationBLabel,
  }) {
    return SpacingRecord(
      spacingFeet: spacingFeet,
      orientationA: DirectionReadingHistory(
        orientation: OrientationKind.a,
        label: orientationALabel ?? OrientationKind.a.defaultLabel,
      ),
      orientationB: DirectionReadingHistory(
        orientation: OrientationKind.b,
        label: orientationBLabel ?? OrientationKind.b.defaultLabel,
      ),
      interpretation: null,
    );
  }

  factory SpacingRecord.fromJson(Map<String, dynamic> json) {
    return SpacingRecord(
      spacingFeet: (json['spacing_ft'] as num).toDouble(),
      orientationA: DirectionReadingHistory.fromJson(
        json['orientation_a'] as Map<String, dynamic>,
      ),
      orientationB: DirectionReadingHistory.fromJson(
        json['orientation_b'] as Map<String, dynamic>,
      ),
      interpretation: json['interpretation'] as String?,
    );
  }

  final double spacingFeet;
  final DirectionReadingHistory orientationA;
  final DirectionReadingHistory orientationB;
  final String? interpretation;

  double get tapeInsideFeet => spacingFeet / 2;

  double get tapeOutsideFeet => spacingFeet * 1.5;

  double get tapeInsideMeters => feetToMeters(tapeInsideFeet);

  double get tapeOutsideMeters => feetToMeters(tapeOutsideFeet);

  DirectionReadingHistory historyFor(OrientationKind orientation) {
    switch (orientation) {
      case OrientationKind.a:
        return orientationA;
      case OrientationKind.b:
        return orientationB;
    }
  }

  SpacingRecord updateHistory(
    OrientationKind orientation,
    DirectionReadingHistory history,
  ) {
    switch (orientation) {
      case OrientationKind.a:
        return copyWith(orientationA: history);
      case OrientationKind.b:
        return copyWith(orientationB: history);
    }
  }

  SpacingRecord renameOrientation(
    OrientationKind orientation,
    String label,
  ) {
    switch (orientation) {
      case OrientationKind.a:
        return copyWith(
          orientationA: orientationA.copyWith(label: label),
        );
      case OrientationKind.b:
        return copyWith(
          orientationB: orientationB.copyWith(label: label),
        );
    }
  }

  SpacingRecord copyWith({
    double? spacingFeet,
    DirectionReadingHistory? orientationA,
    DirectionReadingHistory? orientationB,
    Object? interpretation = _unset,
  }) {
    return SpacingRecord(
      spacingFeet: spacingFeet ?? this.spacingFeet,
      orientationA: orientationA ?? this.orientationA,
      orientationB: orientationB ?? this.orientationB,
      interpretation: identical(interpretation, _unset)
          ? this.interpretation
          : interpretation as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'spacing_ft': spacingFeet,
        'orientation_a': orientationA.toJson(),
        'orientation_b': orientationB.toJson(),
        'interpretation': interpretation,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SpacingRecord &&
        spacingFeet == other.spacingFeet &&
        orientationA == other.orientationA &&
        orientationB == other.orientationB &&
        interpretation == other.interpretation;
  }

  @override
  int get hashCode =>
      Object.hash(spacingFeet, orientationA, orientationB, interpretation);

  static const String interpretationGood = 'Good consistency.';
  static const String interpretationMinor = 'Minor variability.';
  static const String interpretationHigh = '⚠ High SD; retest advised.';

  static const Set<String> interpretationPresets = {
    interpretationGood,
    interpretationMinor,
    interpretationHigh,
  };

  String? computeAutoInterpretation() {
    final sdValues = <double>[];
    final aSd = orientationA.latest?.standardDeviationPercent;
    final bSd = orientationB.latest?.standardDeviationPercent;
    if (aSd != null) {
      sdValues.add(aSd);
    }
    if (bSd != null) {
      sdValues.add(bSd);
    }
    if (sdValues.isEmpty) {
      return null;
    }
    final worst = sdValues.reduce((value, element) =>
        value >= element ? value : element);
    if (worst <= 5) {
      return interpretationGood;
    }
    if (worst <= 15) {
      return interpretationMinor;
    }
    return interpretationHigh;
  }

  bool get hasManualInterpretation =>
      interpretation != null && !interpretationPresets.contains(interpretation);

  SpacingRecord applyAutoInterpretation() {
    final auto = computeAutoInterpretation();
    if (auto == null) {
      return this;
    }
    if (interpretation == null || !hasManualInterpretation) {
      return copyWith(interpretation: auto);
    }
    return this;
  }

  static const _unset = Object();
}

class SiteRecord {
  SiteRecord({
    required this.siteId,
    required this.displayName,
    this.powerMilliAmps = 0.5,
    this.stacks = 4,
    this.soil = SoilType.unknown,
    this.moisture = MoistureLevel.normal,
    List<SpacingRecord>? spacings,
  }) : spacings = List.unmodifiable(spacings ?? const <SpacingRecord>[]);

  factory SiteRecord.fromJson(Map<String, dynamic> json) {
    return SiteRecord(
      siteId: json['site_id'] as String,
      displayName: json['display_name'] as String? ?? json['site_id'] as String,
      powerMilliAmps: (json['power_ma'] as num?)?.toDouble() ?? 0.5,
      stacks: json['stacks'] as int? ?? 4,
      soil: SoilType.values.byName(json['soil'] as String? ?? 'unknown'),
      moisture: MoistureLevel.values
          .byName(json['moisture'] as String? ?? MoistureLevel.normal.name),
      spacings: (json['spacings'] as List<dynamic>? ?? const [])
          .map((dynamic e) =>
              SpacingRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String siteId;
  final String displayName;
  final double powerMilliAmps;
  final int stacks;
  final SoilType soil;
  final MoistureLevel moisture;
  final List<SpacingRecord> spacings;

  SpacingRecord? spacing(double spacingFeet) {
    return spacings
        .firstWhereOrNull((element) => element.spacingFeet == spacingFeet);
  }

  SiteRecord upsertSpacing(SpacingRecord record) {
    final updated = [...spacings];
    final index = updated.indexWhere(
      (element) => element.spacingFeet == record.spacingFeet,
    );
    if (index >= 0) {
      updated[index] = record;
    } else {
      updated.add(record);
      updated.sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
    }
    return copyWith(spacings: updated);
  }

  SiteRecord updateSpacing(
    double spacingFeet,
    SpacingRecord Function(SpacingRecord current) updater,
  ) {
    final existing = spacing(spacingFeet);
    final updatedRecord = updater(
      existing ??
          SpacingRecord.seed(
            spacingFeet: spacingFeet,
          ),
    );
    return upsertSpacing(updatedRecord);
  }

  SiteRecord updateMetadata({
    String? displayName,
    double? powerMilliAmps,
    int? stacks,
    SoilType? soil,
    MoistureLevel? moisture,
  }) {
    return SiteRecord(
      siteId: siteId,
      displayName: displayName ?? this.displayName,
      powerMilliAmps: powerMilliAmps ?? this.powerMilliAmps,
      stacks: stacks ?? this.stacks,
      soil: soil ?? this.soil,
      moisture: moisture ?? this.moisture,
      spacings: spacings,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'site_id': siteId,
        'display_name': displayName,
        'power_ma': powerMilliAmps,
        'stacks': stacks,
        'soil': soil.name,
        'moisture': moisture.name,
        'spacings': spacings.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SiteRecord &&
        siteId == other.siteId &&
        displayName == other.displayName &&
        powerMilliAmps == other.powerMilliAmps &&
        stacks == other.stacks &&
        soil == other.soil &&
        moisture == other.moisture &&
        const ListEquality<SpacingRecord>().equals(spacings, other.spacings);
  }

  @override
  int get hashCode => Object.hash(
        siteId,
        displayName,
        powerMilliAmps,
        stacks,
        soil,
        moisture,
        const ListEquality().hash(spacings),
      );

  SiteRecord copyWith({
    String? siteId,
    String? displayName,
    double? powerMilliAmps,
    int? stacks,
    SoilType? soil,
    MoistureLevel? moisture,
    List<SpacingRecord>? spacings,
  }) {
    return SiteRecord(
      siteId: siteId ?? this.siteId,
      displayName: displayName ?? this.displayName,
      powerMilliAmps: powerMilliAmps ?? this.powerMilliAmps,
      stacks: stacks ?? this.stacks,
      soil: soil ?? this.soil,
      moisture: moisture ?? this.moisture,
      spacings: spacings ?? this.spacings,
    );
  }
}
