import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/geometry_factors.dart' as geom;
import '../utils/units.dart';
export '../utils/units.dart' show feetToMeters, metersToFeet;
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

double _geometryFactorFor(ArrayType arrayType, double spacingMeters) {
  if (spacingMeters <= 0) {
    return 0;
  }
  switch (arrayType) {
    case ArrayType.wenner:
      return geom.geometryFactor(
        array: geom.GeometryArray.wenner,
        spacing: spacingMeters,
      );
    case ArrayType.schlumberger:
      final mn = spacingMeters / 3;
      return geom.geometryFactor(
        array: geom.GeometryArray.schlumberger,
        spacing: spacingMeters,
        mn: mn,
      );
    case ArrayType.dipoleDipole:
    case ArrayType.poleDipole:
    case ArrayType.custom:
      return 2 * math.pi * spacingMeters;
  }
}

class _ResolvedInputs {
  const _ResolvedInputs({
    required this.aFeet,
    required this.spacingMeters,
    required this.rhoAppOhmM,
    this.sigmaRhoOhmM,
    this.voltageV,
    this.currentA,
  });

  final double aFeet;
  final double spacingMeters;
  final double rhoAppOhmM;
  final double? sigmaRhoOhmM;
  final double? voltageV;
  final double? currentA;

  static _ResolvedInputs resolve({
    required double aFeet,
    required double spacingMeters,
    required double rhoAppOhmM,
    double? sigmaRhoOhmM,
    double? resistanceOhm,
    double? resistanceStdOhm,
    double? voltageV,
    double? currentA,
  }) {
    final double normalizedMeters = spacingMeters;
    final double normalizedFeet = aFeet;

    double? resolvedResistance = resistanceOhm;
    if (resolvedResistance == null && voltageV != null && currentA != null && currentA != 0) {
      resolvedResistance = voltageV / currentA;
    }

    double? resolvedSigmaRho = sigmaRhoOhmM;
    if (resolvedSigmaRho == null && resistanceStdOhm != null) {
      resolvedSigmaRho = 2 * math.pi * normalizedMeters * resistanceStdOhm;
    }

    return _ResolvedInputs(
      aFeet: normalizedFeet,
      spacingMeters: normalizedMeters,
      rhoAppOhmM: rhoAppOhmM,
      sigmaRhoOhmM: resolvedSigmaRho,
      voltageV: voltageV,
      currentA: currentA,
    );
  }
}

@immutable
class SpacingPoint {
  SpacingPoint._({
    required this.id,
    required this.arrayType,
    required double aFeet,
    required double spacingMeters,
    required double rhoAppOhmM,
    double? sigmaRhoOhmM,
    required this.direction,
    double? voltageV,
    double? currentA,
    Map<String, double>? contactR,
    this.spDriftMv,
    required this.stacks,
    List<double>? repeats,
    required this.timestamp,
    this.excluded = false,
    this.notes,
  })  : _aFeet = aFeet,
        _spacingMeters = spacingMeters,
        _rhoAppOhmM = rhoAppOhmM,
        _sigmaRhoOhmM = sigmaRhoOhmM,
        _voltageV = voltageV,
        _currentA = currentA,
        contactR = contactR == null ? const {} : Map.unmodifiable(contactR),
        repeats = repeats == null ? null : List.unmodifiable(repeats);

  factory SpacingPoint({
    required String id,
    required ArrayType arrayType,
    double? aFeet,
    double? spacingMetric,
    double? rhoAppOhmM,
    double? sigmaRhoOhmM,
    double? resistanceOhm,
    double? resistanceStdOhm,
    SoundingDirection direction = SoundingDirection.other,
    double? voltageV,
    double? currentA,
    double? vp,
    double? current,
    Map<String, double>? contactR,
    double? spDriftMv,
    int stacks = 1,
    List<double>? repeats,
    DateTime? timestamp,
    bool excluded = false,
    String? notes,
  }) {
    final combinedVoltage = voltageV ?? vp;
    final combinedCurrent = currentA ?? current;

    double? resolvedFeet = aFeet;
    double? resolvedMeters = spacingMetric;

    if (resolvedFeet == null && resolvedMeters != null) {
      resolvedFeet = metersToFeet(resolvedMeters);
    }
    if (resolvedMeters == null && resolvedFeet != null) {
      resolvedMeters = feetToMeters(resolvedFeet);
    }

    double? resolvedResistance = resistanceOhm;
    if (resolvedResistance == null && combinedVoltage != null && combinedCurrent != null && combinedCurrent != 0) {
      resolvedResistance = combinedVoltage / combinedCurrent;
    }

    double? resolvedRho = rhoAppOhmM;
    double? spacingForRho = resolvedMeters ?? (resolvedFeet != null ? feetToMeters(resolvedFeet) : null);
    double? geometryFactor =
        spacingForRho != null && spacingForRho > 0 ? _geometryFactorFor(arrayType, spacingForRho) : null;
    if (resolvedRho == null && resolvedResistance != null && geometryFactor != null && geometryFactor > 0) {
      resolvedRho = resolvedResistance * geometryFactor;
      resolvedMeters ??= spacingForRho;
      if (resolvedFeet == null && spacingForRho != null) {
        resolvedFeet = metersToFeet(spacingForRho);
      }
    }

    if (resolvedRho == null &&
        resolvedResistance == null &&
        combinedVoltage != null &&
        combinedCurrent != null &&
        combinedCurrent != 0 &&
        geometryFactor != null &&
        geometryFactor > 0) {
      final resistanceFromVi = combinedVoltage / combinedCurrent;
      if (spacingForRho != null) {
        resolvedRho = resistanceFromVi * geometryFactor;
        resolvedResistance = resistanceFromVi;
      }
    }

    if (resolvedFeet == null && resolvedMeters != null) {
      resolvedFeet = metersToFeet(resolvedMeters);
    }
    if (resolvedMeters == null && resolvedFeet != null) {
      resolvedMeters = feetToMeters(resolvedFeet);
    }

    spacingForRho = resolvedMeters ?? (resolvedFeet != null ? feetToMeters(resolvedFeet) : null);
    geometryFactor =
        spacingForRho != null && spacingForRho > 0 ? _geometryFactorFor(arrayType, spacingForRho) : geometryFactor;

    if (resolvedFeet == null && resolvedMeters == null && resolvedRho != null && resolvedResistance != null && resolvedResistance != 0) {
      final derivedMeters = resolvedRho / (2 * math.pi * resolvedResistance);
      resolvedMeters = derivedMeters;
      resolvedFeet = metersToFeet(derivedMeters);
      spacingForRho = derivedMeters;
      geometryFactor = _geometryFactorFor(arrayType, derivedMeters);
    }

    if (resolvedFeet == null || resolvedMeters == null) {
      throw ArgumentError('A-spacing could not be resolved from the provided inputs.');
    }

    geometryFactor ??= _geometryFactorFor(arrayType, resolvedMeters);

    resolvedRho ??=
        resolvedResistance != null && geometryFactor != null && geometryFactor > 0 ? resolvedResistance * geometryFactor : null;

    if (resolvedRho == null) {
      throw ArgumentError('Apparent resistivity could not be resolved from the provided inputs.');
    }

    double? resolvedSigmaRho = sigmaRhoOhmM;
    if (resolvedSigmaRho == null && resistanceStdOhm != null && geometryFactor != null && geometryFactor > 0) {
      resolvedSigmaRho = geometryFactor * resistanceStdOhm;
    }

    final resolved = _ResolvedInputs.resolve(
      aFeet: resolvedFeet!,
      spacingMeters: resolvedMeters!,
      rhoAppOhmM: resolvedRho!,
      sigmaRhoOhmM: resolvedSigmaRho,
      resistanceOhm: resolvedResistance,
      resistanceStdOhm: resistanceStdOhm,
      voltageV: combinedVoltage,
      currentA: combinedCurrent,
    );

    return SpacingPoint._(
      id: id,
      arrayType: arrayType,
      aFeet: resolved.aFeet,
      spacingMeters: resolved.spacingMeters,
      rhoAppOhmM: resolved.rhoAppOhmM,
      sigmaRhoOhmM: resolved.sigmaRhoOhmM,
      direction: direction,
      voltageV: resolved.voltageV,
      currentA: resolved.currentA,
      contactR: contactR,
      spDriftMv: spDriftMv,
      stacks: stacks,
      repeats: repeats,
      timestamp: timestamp ?? DateTime.now(),
      excluded: excluded,
      notes: notes,
    );
  }

  factory SpacingPoint.newPoint({
    required ArrayType arrayType,
    required double aFeet,
    required double rhoAppOhmM,
    double? sigmaRhoOhmM,
    SoundingDirection direction = SoundingDirection.other,
    double? voltageV,
    double? currentA,
    Map<String, double>? contactR,
    double? spDriftMv,
    int stacks = 1,
    List<double>? repeats,
    DateTime? timestamp,
    bool excluded = false,
    double? spacingMeters,
    String? notes,
  }) {
    return SpacingPoint(
      id: const Uuid().v4(),
      arrayType: arrayType,
      aFeet: aFeet,
      spacingMetric: spacingMeters ?? feetToMeters(aFeet),
      rhoAppOhmM: rhoAppOhmM,
      sigmaRhoOhmM: sigmaRhoOhmM,
      direction: direction,
      voltageV: voltageV,
      currentA: currentA,
      contactR: contactR,
      spDriftMv: spDriftMv,
      stacks: stacks,
      repeats: repeats,
      timestamp: timestamp,
      excluded: excluded,
      notes: notes,
    );
  }

  final String id;
  final ArrayType arrayType;
  final double _aFeet;
  final double _spacingMeters;
  final double _rhoAppOhmM;
  final double? _sigmaRhoOhmM;
  final SoundingDirection direction;
  final double? _voltageV;
  final double? _currentA;
  final ContactResistances contactR;
  final double? spDriftMv;
  final int stacks;
  final List<double>? repeats;
  final DateTime timestamp;
  final bool excluded;
  final String? notes;

  static const double rhoQaThresholdPercent = 5;

  double get aFeet => _aFeet;
  double get spacingMeters => _spacingMeters;
  double get aMeters => spacingMeters;
  double get spacingMetric => spacingMeters;
  double get rhoAppOhmM => _rhoAppOhmM;
  double get rhoApp => rhoAppOhmM;
  double? get sigmaRhoOhmM => _sigmaRhoOhmM;
  double? get sigmaRhoApp => sigmaRhoOhmM;
  double get geometryFactor => _geometryFactorFor(arrayType, spacingMeters);
  double get resistanceOhm => geometryFactor == 0 ? 0 : rhoAppOhmM / geometryFactor;
  double? get resistanceStdOhm {
    final sigma = sigmaRhoOhmM;
    return sigma != null && geometryFactor != 0 ? sigma / geometryFactor : null;
  }
  double? get voltageV => _voltageV;
  double? get currentA => _currentA;
  double get vp {
    final voltage = _voltageV;
    if (voltage != null) {
      return voltage;
    }
    final current = currentA;
    return current != null ? resistanceOhm * current : 0;
  }

  double get current {
    final current = _currentA;
    if (current != null) {
      return current;
    }
    final voltage = _voltageV;
    if (voltage != null && resistanceOhm != 0) {
      return voltage / resistanceOhm;
    }
    return 0;
  }

  double? get rhoFromVi {
    final voltage = _voltageV;
    final current = _currentA;
    if (voltage == null || current == null || current == 0) {
      return null;
    }
    return geometryFactor * (voltage / current);
  }

  double? get resistanceFromVi {
    final voltage = _voltageV;
    final current = _currentA;
    if (voltage == null || current == null || current == 0) {
      return null;
    }
    return voltage / current;
  }

  double? get rFromVi => resistanceFromVi;

  double? get rhoDiffPercent {
    final viRho = rhoFromVi;
    if (viRho == null || rhoAppOhmM == 0) {
      return null;
    }
    return ((viRho - rhoAppOhmM).abs() / rhoAppOhmM) * 100;
  }

  double? get resistanceDiffPercent => rhoDiffPercent;

  bool get hasRhoQaWarning {
    final diff = rhoDiffPercent;
    return diff != null && diff > rhoQaThresholdPercent;
  }

  bool get hasResistanceQaWarning => hasRhoQaWarning;

  double? get contactRMax =>
      contactR.values.isEmpty ? null : contactR.values.reduce((a, b) => a > b ? a : b);

  SpacingPoint copyWith({
    ArrayType? arrayType,
    double? aFeet,
    double? spacingMeters,
    double? rhoAppOhmM,
    double? sigmaRhoOhmM,
    SoundingDirection? direction,
    double? voltageV,
    double? currentA,
    ContactResistances? contactR,
    double? spDriftMv,
    int? stacks,
    List<double>? repeats,
    DateTime? timestamp,
    bool? excluded,
    String? notes,
  }) {
    final updatedFeet = aFeet ?? this.aFeet;
    final updatedSpacing = spacingMeters ?? (aFeet != null ? feetToMeters(aFeet) : this.spacingMeters);
    return SpacingPoint._(
      id: id,
      arrayType: arrayType ?? this.arrayType,
      aFeet: updatedFeet,
      spacingMeters: updatedSpacing,
      rhoAppOhmM: rhoAppOhmM ?? this.rhoAppOhmM,
      sigmaRhoOhmM: sigmaRhoOhmM ?? this.sigmaRhoOhmM,
      direction: direction ?? this.direction,
      voltageV: voltageV ?? _voltageV,
      currentA: currentA ?? _currentA,
      contactR: contactR ?? this.contactR,
      spDriftMv: spDriftMv ?? this.spDriftMv,
      stacks: stacks ?? this.stacks,
      repeats: repeats ?? this.repeats,
      timestamp: timestamp ?? this.timestamp,
      excluded: excluded ?? this.excluded,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'arrayType': arrayType.name,
        'aFeet': aFeet,
        'spacingMetric': spacingMetric,
        'aMeters': aMeters,
        'rhoApp': rhoAppOhmM,
        'rhoAppOhmM': rhoAppOhmM,
        'sigmaRhoOhmM': sigmaRhoOhmM,
        'sigmaRhoApp': sigmaRhoOhmM,
        'resistanceOhm': resistanceOhm,
        'resistanceStdOhm': resistanceStdOhm,
        'direction': direction.name,
        'voltageV': voltageV,
        'currentA': currentA,
        'contactR': contactR,
        'spDriftMv': spDriftMv,
        'stacks': stacks,
        'repeats': repeats,
        'timestamp': timestamp.toIso8601String(),
        'excluded': excluded,
        'notes': notes,
      };

  factory SpacingPoint.fromJson(Map<String, dynamic> json) {
    return SpacingPoint(
      id: json['id'] as String,
      arrayType: ArrayType.values.firstWhere(
        (e) => e.name == json['arrayType'],
        orElse: () => ArrayType.custom,
      ),
      aFeet: (json['aFeet'] as num?)?.toDouble(),
      spacingMetric: (json['spacingMetric'] as num?)?.toDouble() ?? (json['aMeters'] as num?)?.toDouble(),
      rhoAppOhmM: (json['rhoAppOhmM'] as num?)?.toDouble() ?? (json['rhoApp'] as num?)?.toDouble(),
      sigmaRhoOhmM: (json['sigmaRhoOhmM'] as num?)?.toDouble() ?? (json['sigmaRhoApp'] as num?)?.toDouble(),
      resistanceOhm: (json['resistanceOhm'] as num?)?.toDouble(),
      resistanceStdOhm: (json['resistanceStdOhm'] as num?)?.toDouble(),
      direction: parseSoundingDirection(json['direction'] as String?),
      voltageV: (json['voltageV'] as num?)?.toDouble(),
      currentA: (json['currentA'] as num?)?.toDouble(),
      contactR: (json['contactR'] as Map?)?.map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      ),
      spDriftMv: (json['spDriftMv'] as num?)?.toDouble(),
      stacks: json['stacks'] as int? ?? 1,
      repeats: (json['repeats'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      excluded: json['excluded'] as bool? ?? false,
      notes: json['notes'] as String?,
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
          spacingMeters == other.spacingMeters &&
          rhoAppOhmM == other.rhoAppOhmM &&
          sigmaRhoOhmM == other.sigmaRhoOhmM &&
          direction == other.direction &&
          voltageV == other.voltageV &&
          currentA == other.currentA &&
          spDriftMv == other.spDriftMv &&
          stacks == other.stacks &&
          timestamp == other.timestamp &&
          excluded == other.excluded &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
        id,
        arrayType,
        aFeet,
        spacingMeters,
        rhoAppOhmM,
        sigmaRhoOhmM,
        direction,
        voltageV,
        currentA,
        const DeepCollectionEquality().hash(contactR),
        spDriftMv,
        stacks,
        const ListEquality<double>().hash(repeats),
        timestamp,
        excluded,
        notes,
      );
}
