import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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

class _ResolvedInputs {
  const _ResolvedInputs({
    required this.aFeet,
    required this.rhoAppOhmM,
    this.sigmaRhoOhmM,
    this.voltageV,
    this.currentA,
  });

  final double aFeet;
  final double rhoAppOhmM;
  final double? sigmaRhoOhmM;
  final double? voltageV;
  final double? currentA;

  static _ResolvedInputs resolve({
    double? aFeet,
    double? spacingMeters,
    double? rhoAppOhmM,
    double? sigmaRho,
    double? resistanceOhm,
    double? resistanceStdOhm,
    double? voltageV,
    double? currentA,
  }) {
    double? resolvedFeet = aFeet;
    double? resolvedMeters = spacingMeters;

    if (resolvedFeet == null && resolvedMeters != null) {
      resolvedFeet = metersToFeet(resolvedMeters);
    }
    if (resolvedMeters == null && resolvedFeet != null) {
      resolvedMeters = feetToMeters(resolvedFeet);
    }

    double? resolvedResistance = resistanceOhm;
    if (resolvedResistance == null && voltageV != null && currentA != null && currentA != 0) {
      resolvedResistance = voltageV / currentA;
    }

    double? resolvedRho = rhoApp;
    if (resolvedRho == null && resolvedResistance != null && resolvedMeters != null) {
      resolvedRho = 2 * math.pi * resolvedMeters * resolvedResistance;
    }
    if (resolvedRho == null && resolvedResistance != null && resolvedFeet != null) {
      final meters = feetToMeters(resolvedFeet);
      resolvedRho = 2 * math.pi * meters * resolvedResistance;
      resolvedMeters ??= meters;
    }

    if (resolvedRho == null && resolvedResistance == null && voltageV != null && currentA != null && currentA != 0) {
      final resistanceFromVi = voltageV / currentA;
      if (resolvedMeters != null) {
        resolvedRho = 2 * math.pi * resolvedMeters * resistanceFromVi;
        resolvedResistance = resistanceFromVi;
      } else if (resolvedFeet != null) {
        final meters = feetToMeters(resolvedFeet);
        resolvedRho = 2 * math.pi * meters * resistanceFromVi;
        resolvedResistance = resistanceFromVi;
        resolvedMeters = meters;
      }
    }

    if (resolvedFeet == null && resolvedMeters != null) {
      resolvedFeet = metersToFeet(resolvedMeters);
    }
    if (resolvedMeters == null && resolvedFeet != null) {
      resolvedMeters = feetToMeters(resolvedFeet);
    }

    if (resolvedFeet == null || resolvedMeters == null) {
      throw ArgumentError('A-spacing could not be resolved from the provided inputs.');
    }

    if (resolvedRho == null) {
      throw ArgumentError('Apparent resistivity could not be resolved from the provided inputs.');
    }

    double? resolvedSigmaRho = sigmaRho;
    if (resolvedSigmaRho == null && resistanceStdOhm != null) {
      resolvedSigmaRho = 2 * math.pi * resolvedMeters * resistanceStdOhm;
    }

    return _ResolvedInputs(
      aFeet: resolvedFeet,
      rhoAppOhmM: resolvedRho,
      sigmaRhoOhmM: resolvedSigmaRho,
      voltageV: voltageV,
      currentA: currentA,
    );
  }
}

@immutable
class SpacingPoint {
  const SpacingPoint._({
    required this.id,
    required this.arrayType,
    required double aFeet,
    required double rhoAppOhmM,
    double? sigmaRhoOhmM,
    required this.direction,
    double? voltageV,
    double? currentA,
    required ContactResistances contactR,
    this.spDriftMv,
    required this.stacks,
    List<double>? repeats,
    required this.timestamp,
    this.excluded = false,
  })  : _aFeet = aFeet,
        _rhoAppOhmM = rhoAppOhmM,
        _sigmaRhoOhmM = sigmaRhoOhmM,
        _voltageV = voltageV,
        _currentA = currentA,
        contactR = Map.unmodifiable(contactR),
        repeats = repeats != null ? List.unmodifiable(repeats) : null;

  factory SpacingPoint({
    required String id,
    required ArrayType arrayType,
    double? aFeet,
    double? spacingMetric,
    double? rhoAppOhmM,
    double? rhoApp,
    double? sigmaRhoOhmM,
    double? sigmaRhoApp,
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
    DateTime? timestamp,
    bool excluded = false,
  }) {
    final resolved = _ResolvedInputs.resolve(
      aFeet: aFeet,
      spacingMeters: spacingMetric,
      rhoApp: rhoAppOhmM ?? rhoApp,
      sigmaRho: sigmaRhoOhmM ?? sigmaRhoApp,
      resistanceOhm: resistanceOhm,
      resistanceStdOhm: resistanceStdOhm,
      voltageV: voltageV ?? vp,
      currentA: currentA ?? current,
    );

    return SpacingPoint._(
      id: id,
      arrayType: arrayType,
      aFeet: resolved.aFeet,
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
    ContactResistances contactR = const {},
    double? spDriftMv,
    int stacks = 1,
    List<double>? repeats,
    DateTime? timestamp,
    bool excluded = false,
  }) {
    return SpacingPoint(
      id: const Uuid().v4(),
      arrayType: arrayType,
      aFeet: aFeet,
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
    );
  }

  final String id;
  final ArrayType arrayType;
  final double _aFeet;
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

  static const double rhoQaThresholdPercent = 5;

  double get aFeet => _aFeet;
  double get aMeters => feetToMeters(_aFeet);
  double get spacingMetric => aMeters;
  double get rhoAppOhmM => _rhoAppOhmM;
  double get rhoApp => rhoAppOhmM;
  double? get sigmaRhoOhmM => _sigmaRhoOhmM;
  double? get sigmaRhoApp => sigmaRhoOhmM;
  double get resistanceOhm => rhoAppOhmM / (2 * math.pi * aMeters);
  double? get resistanceStdOhm =>
      sigmaRhoOhmM != null ? sigmaRhoOhmM! / (2 * math.pi * aMeters) : null;
  double? get voltageV => _voltageV;
  double? get currentA => _currentA;
  double get vp => _voltageV ?? (currentA != null ? resistanceOhm * currentA! : 0);
  double get current => _currentA ?? (_voltageV != null && resistanceOhm != 0 ? _voltageV! / resistanceOhm : 0);

  double? get rhoFromVi {
    if (_voltageV == null || _currentA == null || _currentA == 0) {
      return null;
    }
    return 2 * math.pi * aMeters * (_voltageV! / _currentA!);
  }

  double? get resistanceFromVi {
    if (_voltageV == null || _currentA == null || _currentA == 0) {
      return null;
    }
    return _voltageV! / _currentA!;
  }

  double? get rFromVi => resistanceFromVi;

  double? get rhoDiffPercent =>
      rhoFromVi == null || rhoAppOhmM == 0 ? null : ((rhoFromVi! - rhoAppOhmM).abs() / rhoAppOhmM) * 100;

  double? get resistanceDiffPercent => rhoDiffPercent;

  bool get hasRhoQaWarning =>
      rhoDiffPercent != null && rhoDiffPercent! > rhoQaThresholdPercent;

  bool get hasResistanceQaWarning => hasRhoQaWarning;

  double? get contactRMax =>
      contactR.values.isEmpty ? null : contactR.values.reduce((a, b) => a > b ? a : b);

  SpacingPoint copyWith({
    ArrayType? arrayType,
    double? aFeet,
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
  }) {
    return SpacingPoint._(
      id: id,
      arrayType: arrayType ?? this.arrayType,
      aFeet: aFeet ?? this.aFeet,
      rhoAppOhmM: rhoAppOhmM ?? this.rhoAppOhmM,
      sigmaRhoOhmM: sigmaRhoOhmM ?? this.sigmaRhoOhmM,
      direction: direction ?? this.direction,
      voltageV: voltageV ?? _voltageV,
      currentA: currentA ?? _currentA,
      contactR: contactR != null ? Map.unmodifiable(contactR) : this.contactR,
      spDriftMv: spDriftMv ?? this.spDriftMv,
      stacks: stacks ?? this.stacks,
      repeats: repeats != null ? List.unmodifiable(repeats) : this.repeats,
      timestamp: timestamp ?? this.timestamp,
      excluded: excluded ?? this.excluded,
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
      rhoApp: (json['rhoAppOhmM'] as num?)?.toDouble() ?? (json['rhoApp'] as num?)?.toDouble(),
      sigmaRhoOhmM: (json['sigmaRhoOhmM'] as num?)?.toDouble() ?? (json['sigmaRhoApp'] as num?)?.toDouble(),
      resistanceOhm: (json['resistanceOhm'] as num?)?.toDouble(),
      resistanceStdOhm: (json['resistanceStdOhm'] as num?)?.toDouble(),
      direction: parseSoundingDirection(json['direction'] as String?),
      voltageV: (json['voltageV'] as num?)?.toDouble(),
      currentA: (json['currentA'] as num?)?.toDouble(),
      contactR: Map.unmodifiable((json['contactR'] as Map?)?.map(
            (key, value) => MapEntry(key as String, (value as num).toDouble()),
          ) ??
          {}),
      spDriftMv: (json['spDriftMv'] as num?)?.toDouble(),
      stacks: json['stacks'] as int? ?? 1,
      repeats: (json['repeats'] as List?)?.map((e) => (e as num).toDouble()).toList(),
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
          rhoAppOhmM == other.rhoAppOhmM &&
          sigmaRhoOhmM == other.sigmaRhoOhmM &&
          direction == other.direction &&
          voltageV == other.voltageV &&
          currentA == other.currentA &&
          spDriftMv == other.spDriftMv &&
          stacks == other.stacks &&
          timestamp == other.timestamp &&
          excluded == other.excluded;

  @override
  int get hashCode => Object.hash(
        id,
        arrayType,
        aFeet,
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
      );
}
