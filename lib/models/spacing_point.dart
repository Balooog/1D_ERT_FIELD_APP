import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'enums.dart';

typedef ContactResistances = Map<String, double>;

enum SoundingDirection { ns, we, other }

extension SoundingDirectionX on SoundingDirection {
  String get label {
    switch (this) {
      case SoundingDirection.ns:
        return 'N–S';
      case SoundingDirection.we:
        return 'W–E';
      case SoundingDirection.other:
        return 'Other';
    }
  }

  String get csvValue => name;
}

SoundingDirection parseSoundingDirection(String? value) {
  if (value == null) {
    return SoundingDirection.other;
  }
  final normalized = value.trim().toLowerCase();
  switch (normalized) {
    case 'ns':
    case 'n-s':
    case 'n/s':
    case 'n–s':
    case 'north south':
    case 'northsouth':
    case 'north-south':
      return SoundingDirection.ns;
    case 'we':
    case 'w-e':
    case 'w/e':
    case 'w–e':
    case 'west east':
    case 'eastwest':
    case 'east-west':
    case 'west-east':
      return SoundingDirection.we;
    default:
      return SoundingDirection.other;
  }
}

const double _metersPerFoot = 0.3048;

double feetToMeters(double feet) => feet * _metersPerFoot;

double metersToFeet(double meters) => meters / _metersPerFoot;

class _ResolvedInputs {
  const _ResolvedInputs({
    required this.aFeet,
    required this.resistanceOhm,
    this.voltageV,
    this.currentA,
  });

  final double aFeet;
  final double resistanceOhm;
  final double? voltageV;
  final double? currentA;

  static _ResolvedInputs resolve({
    double? aFeet,
    double? spacingMeters,
    double? resistanceOhm,
    double? voltageV,
    double? currentA,
    double? rhoApp,
  }) {
    double? resolvedFeet = aFeet;
    double? resolvedMeters = spacingMeters;
    if (resolvedFeet == null && resolvedMeters != null) {
      resolvedFeet = metersToFeet(resolvedMeters);
    }

    double? resolvedResistance = resistanceOhm;
    final double? voltage = voltageV;
    final double? current = currentA;

    if (resolvedResistance == null && rhoApp != null) {
      resolvedMeters ??= resolvedFeet != null ? feetToMeters(resolvedFeet) : null;
      if (resolvedMeters != null && resolvedMeters != 0) {
        resolvedResistance = rhoApp / (2 * math.pi * resolvedMeters);
      }
    }

    if (resolvedResistance == null && voltage != null && current != null && current != 0) {
      resolvedResistance = voltage / current;
    }

    if (resolvedFeet == null) {
      if (resolvedMeters != null) {
        resolvedFeet = metersToFeet(resolvedMeters);
      } else if (rhoApp != null && resolvedResistance != null && resolvedResistance != 0) {
        final derivedMeters = rhoApp / (2 * math.pi * resolvedResistance);
        resolvedMeters = derivedMeters;
        resolvedFeet = metersToFeet(derivedMeters);
      }
    }

    resolvedMeters ??= resolvedFeet != null ? feetToMeters(resolvedFeet) : null;

    if (resolvedFeet == null) {
      throw ArgumentError('A-spacing could not be resolved from the provided inputs.');
    }
    if (resolvedResistance == null) {
      throw ArgumentError('Resistance (Ω) could not be resolved from the provided inputs.');
    }

    return _ResolvedInputs(
      aFeet: resolvedFeet,
      resistanceOhm: resolvedResistance,
      voltageV: voltage,
      currentA: current,
    );
  }
}

@immutable
class SpacingPoint {
  const SpacingPoint._({
    required this.id,
    required this.arrayType,
    required double aFeet,
    required double resistanceOhm,
    double? resistanceStdOhm,
    required this.direction,
    double? voltageV,
    double? currentA,
    required ContactResistances contactR,
    this.spDriftMv,
    required this.stacks,
    List<double>? repeats,
    double? sigmaRhoLegacy,
    required this.timestamp,
    this.excluded = false,
  })  : _aFeet = aFeet,
        _resistanceOhm = resistanceOhm,
        _resistanceStdOhm = resistanceStdOhm,
        _voltageV = voltageV,
        _currentA = currentA,
        contactR = Map.unmodifiable(contactR),
        repeats = repeats != null ? List.unmodifiable(repeats) : null,
        _sigmaRhoLegacy = sigmaRhoLegacy;

  factory SpacingPoint({
    required String id,
    required ArrayType arrayType,
    double? aFeet,
    double? spacingMetric,
    double? resistanceOhm,
    double? resistanceStdOhm,
    SoundingDirection direction = SoundingDirection.other,
    double? voltageV,
    double? currentA,
    double? vp,
    double? current,
    ContactResistances contactR = const {},
    double? spDriftMv,
    int stacks = 1,
    List<double>? repeats,
    double? rhoApp,
    double? sigmaRhoApp,
    DateTime? timestamp,
    bool excluded = false,
  }) {
    final resolved = _ResolvedInputs.resolve(
      aFeet: aFeet,
      spacingMeters: spacingMetric,
      resistanceOhm: resistanceOhm,
      voltageV: voltageV ?? vp,
      currentA: currentA ?? current,
      rhoApp: rhoApp,
    );

    return SpacingPoint._(
      id: id,
      arrayType: arrayType,
      aFeet: resolved.aFeet,
      resistanceOhm: resolved.resistanceOhm,
      resistanceStdOhm: resistanceStdOhm,
      direction: direction,
      voltageV: resolved.voltageV,
      currentA: resolved.currentA,
      contactR: contactR,
      spDriftMv: spDriftMv,
      stacks: stacks,
      repeats: repeats,
      sigmaRhoLegacy: sigmaRhoApp,
      timestamp: timestamp ?? DateTime.now(),
      excluded: excluded,
    );
  }

  factory SpacingPoint.newPoint({
    required ArrayType arrayType,
    required double aFeet,
    required double resistanceOhm,
    double? resistanceStdOhm,
    SoundingDirection direction = SoundingDirection.other,
    double? voltageV,
    double? currentA,
    ContactResistances contactR = const {},
    double? spDriftMv,
    int stacks = 1,
    List<double>? repeats,
    double? sigmaRhoApp,
    DateTime? timestamp,
    bool excluded = false,
  }) {
    return SpacingPoint(
      id: const Uuid().v4(),
      arrayType: arrayType,
      aFeet: aFeet,
      resistanceOhm: resistanceOhm,
      resistanceStdOhm: resistanceStdOhm,
      direction: direction,
      voltageV: voltageV,
      currentA: currentA,
      contactR: contactR,
      spDriftMv: spDriftMv,
      stacks: stacks,
      repeats: repeats,
      rhoApp: null,
      sigmaRhoApp: sigmaRhoApp,
      timestamp: timestamp,
      excluded: excluded,
    );
  }

  final String id;
  final ArrayType arrayType;
  final double _aFeet;
  final double _resistanceOhm;
  final double? _resistanceStdOhm;
  final SoundingDirection direction;
  final double? _voltageV;
  final double? _currentA;
  final ContactResistances contactR;
  final double? spDriftMv;
  final int stacks;
  final List<double>? repeats;
  final double? _sigmaRhoLegacy;
  final DateTime timestamp;
  final bool excluded;

  static const double resistanceQaThresholdPercent = 5;

  double get aFeet => _aFeet;
  double get aMeters => feetToMeters(_aFeet);
  double get spacingMetric => aMeters;
  double get resistanceOhm => _resistanceOhm;
  double? get resistanceStdOhm => _resistanceStdOhm;
  double get rhoAppOhmM => 2 * math.pi * aMeters * resistanceOhm;
  double get rhoApp => rhoAppOhmM;
  double? get sigmaRhoApp => _resistanceStdOhm != null
      ? 2 * math.pi * aMeters * _resistanceStdOhm!
      : _sigmaRhoLegacy;
  double? get sigmaRhoAppFromResistance =>
      _resistanceStdOhm != null ? 2 * math.pi * aMeters * _resistanceStdOhm! : null;
  double? get voltageV => _voltageV;
  double? get currentA => _currentA;
  double get vp => _voltageV ?? (currentA != null ? resistanceOhm * currentA! : 0);
  double get current => _currentA ?? (_voltageV != null && resistanceOhm != 0 ? _voltageV! / resistanceOhm : 0);

  double? get rFromVi =>
      (_voltageV != null && _currentA != null && _currentA != 0) ? _voltageV! / _currentA! : null;

  double? get resistanceDiffPercent => rFromVi == null || resistanceOhm == 0
      ? null
      : ((rFromVi! - resistanceOhm).abs() / resistanceOhm) * 100;

  bool get hasResistanceQaWarning =>
      resistanceDiffPercent != null && resistanceDiffPercent! > resistanceQaThresholdPercent;

  double? get contactRMax =>
      contactR.values.isEmpty ? null : contactR.values.reduce((a, b) => a > b ? a : b);

  SpacingPoint copyWith({
    ArrayType? arrayType,
    double? aFeet,
    double? resistanceOhm,
    double? resistanceStdOhm,
    SoundingDirection? direction,
    double? voltageV,
    double? currentA,
    ContactResistances? contactR,
    double? spDriftMv,
    int? stacks,
    List<double>? repeats,
    double? sigmaRhoApp,
    DateTime? timestamp,
    bool? excluded,
  }) {
    return SpacingPoint._(
      id: id,
      arrayType: arrayType ?? this.arrayType,
      aFeet: aFeet ?? this.aFeet,
      resistanceOhm: resistanceOhm ?? this.resistanceOhm,
      resistanceStdOhm: resistanceStdOhm ?? this.resistanceStdOhm,
      direction: direction ?? this.direction,
      voltageV: voltageV ?? _voltageV,
      currentA: currentA ?? _currentA,
      contactR: contactR != null ? Map.unmodifiable(contactR) : this.contactR,
      spDriftMv: spDriftMv ?? this.spDriftMv,
      stacks: stacks ?? this.stacks,
      repeats: repeats != null ? List.unmodifiable(repeats) : this.repeats,
      sigmaRhoLegacy: sigmaRhoApp ?? _sigmaRhoLegacy,
      timestamp: timestamp ?? this.timestamp,
      excluded: excluded ?? this.excluded,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'arrayType': arrayType.name,
        'aFeet': aFeet,
        'spacingMetric': spacingMetric,
        'resistanceOhm': resistanceOhm,
        'resistanceStdOhm': resistanceStdOhm,
        'direction': direction.name,
        'vp': vp,
        'voltageV': voltageV,
        'current': current,
        'currentA': currentA,
        'contactR': contactR,
        'spDriftMv': spDriftMv,
        'stacks': stacks,
        'repeats': repeats,
        'rhoApp': rhoAppOhmM,
        'rhoAppOhmM': rhoAppOhmM,
        'sigmaRhoApp': sigmaRhoApp,
        'timestamp': timestamp.toIso8601String(),
        'excluded': excluded,
      };

  factory SpacingPoint.fromJson(Map<String, dynamic> json) {
    return SpacingPoint(
      id: json['id'] as String,
      arrayType: ArrayType.values.firstWhere(
        (e) => e.name == json['arrayType'],
        orElse: () => ArrayType.custom,
      ),
      aFeet: (json['aFeet'] as num?)?.toDouble(),
      spacingMetric: (json['spacingMetric'] as num?)?.toDouble(),
      resistanceOhm: (json['resistanceOhm'] as num?)?.toDouble(),
      resistanceStdOhm: (json['resistanceStdOhm'] as num?)?.toDouble(),
      direction: parseSoundingDirection(json['direction'] as String?),
      voltageV: (json['voltageV'] as num?)?.toDouble() ?? (json['vp'] as num?)?.toDouble(),
      currentA: (json['currentA'] as num?)?.toDouble() ?? (json['current'] as num?)?.toDouble(),
      contactR: Map.unmodifiable((json['contactR'] as Map?)?.map(
            (key, value) => MapEntry(key as String, (value as num).toDouble()),
          ) ??
          {}),
      spDriftMv: (json['spDriftMv'] as num?)?.toDouble(),
      stacks: json['stacks'] as int? ?? 1,
      repeats: (json['repeats'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      rhoApp: (json['rhoAppOhmM'] as num?)?.toDouble() ?? (json['rhoApp'] as num?)?.toDouble(),
      sigmaRhoApp: (json['sigmaRhoApp'] as num?)?.toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      excluded: json['excluded'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpacingPoint &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          const DeepCollectionEquality().equals(contactR, other.contactR) &&
          const ListEquality<double>().equals(repeats, other.repeats) &&
          arrayType == other.arrayType &&
          aFeet == other.aFeet &&
          resistanceOhm == other.resistanceOhm &&
          resistanceStdOhm == other.resistanceStdOhm &&
          direction == other.direction &&
          voltageV == other.voltageV &&
          currentA == other.currentA &&
          spDriftMv == other.spDriftMv &&
          stacks == other.stacks &&
          timestamp == other.timestamp &&
          excluded == other.excluded &&
          _sigmaRhoLegacy == other._sigmaRhoLegacy;

  @override
  int get hashCode => Object.hash(
        id,
        arrayType,
        aFeet,
        resistanceOhm,
        resistanceStdOhm,
        direction,
        voltageV,
        currentA,
        const DeepCollectionEquality().hash(contactR),
        spDriftMv,
        stacks,
        const ListEquality<double>().hash(repeats),
        _sigmaRhoLegacy,
        timestamp,
        excluded,
      );
}
