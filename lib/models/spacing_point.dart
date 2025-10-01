import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'enums.dart';

typedef ContactResistances = Map<String, double>;

@immutable
class SpacingPoint {
  const SpacingPoint({
    required this.id,
    required this.arrayType,
    required this.spacingMetric,
    required this.vp,
    required this.current,
    required this.contactR,
    required this.spDriftMv,
    required this.stacks,
    required this.repeats,
    required this.rhoApp,
    required this.sigmaRhoApp,
    required this.timestamp,
    this.excluded = false,
  });

  factory SpacingPoint.newPoint({
    required ArrayType arrayType,
    required double spacingMetric,
    required double vp,
    required double current,
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
      spacingMetric: spacingMetric,
      vp: vp,
      current: current,
      contactR: Map.unmodifiable(contactR),
      spDriftMv: spDriftMv,
      stacks: stacks,
      repeats: repeats != null ? List.unmodifiable(repeats) : null,
      rhoApp: 0,
      sigmaRhoApp: sigmaRhoApp,
      timestamp: timestamp ?? DateTime.now(),
      excluded: excluded,
    );
  }

  final String id;
  final ArrayType arrayType;
  final double spacingMetric;
  final double vp;
  final double current;
  final ContactResistances contactR;
  final double? spDriftMv;
  final int stacks;
  final List<double>? repeats;
  final double rhoApp;
  final double? sigmaRhoApp;
  final DateTime timestamp;
  final bool excluded;

  double? get contactRMax =>
      contactR.values.isEmpty ? null : contactR.values.reduce((a, b) => a > b ? a : b);

  SpacingPoint copyWith({
    ArrayType? arrayType,
    double? spacingMetric,
    double? vp,
    double? current,
    ContactResistances? contactR,
    double? spDriftMv,
    int? stacks,
    List<double>? repeats,
    double? rhoApp,
    double? sigmaRhoApp,
    DateTime? timestamp,
    bool? excluded,
  }) {
    return SpacingPoint(
      id: id,
      arrayType: arrayType ?? this.arrayType,
      spacingMetric: spacingMetric ?? this.spacingMetric,
      vp: vp ?? this.vp,
      current: current ?? this.current,
      contactR: contactR ?? this.contactR,
      spDriftMv: spDriftMv ?? this.spDriftMv,
      stacks: stacks ?? this.stacks,
      repeats: repeats ?? this.repeats,
      rhoApp: rhoApp ?? this.rhoApp,
      sigmaRhoApp: sigmaRhoApp ?? this.sigmaRhoApp,
      timestamp: timestamp ?? this.timestamp,
      excluded: excluded ?? this.excluded,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'arrayType': arrayType.name,
        'spacingMetric': spacingMetric,
        'vp': vp,
        'current': current,
        'contactR': contactR,
        'spDriftMv': spDriftMv,
        'stacks': stacks,
        'repeats': repeats,
        'rhoApp': rhoApp,
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
      spacingMetric: (json['spacingMetric'] as num).toDouble(),
      vp: (json['vp'] as num).toDouble(),
      current: (json['current'] as num).toDouble(),
      contactR: Map.unmodifiable((json['contactR'] as Map?)?.map(
            (key, value) => MapEntry(key as String, (value as num).toDouble()),
          ) ??
          {}),
      spDriftMv: (json['spDriftMv'] as num?)?.toDouble(),
      stacks: json['stacks'] as int? ?? 1,
      repeats: (json['repeats'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      rhoApp: (json['rhoApp'] as num).toDouble(),
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
          spacingMetric == other.spacingMetric &&
          vp == other.vp &&
          current == other.current &&
          spDriftMv == other.spDriftMv &&
          stacks == other.stacks &&
          rhoApp == other.rhoApp &&
          sigmaRhoApp == other.sigmaRhoApp &&
          timestamp == other.timestamp &&
          excluded == other.excluded;

  @override
  int get hashCode => Object.hash(
        id,
        arrayType,
        spacingMetric,
        vp,
        current,
        const DeepCollectionEquality().hash(contactR),
        spDriftMv,
        stacks,
        const ListEquality<double>().hash(repeats),
        rhoApp,
        sigmaRhoApp,
        timestamp,
        excluded,
      );
}
