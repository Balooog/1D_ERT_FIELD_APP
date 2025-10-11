import 'dart:convert';

import 'package:collection/collection.dart';

import 'calc.dart';

enum OrientationKind { a, b }

extension OrientationKindLabel on OrientationKind {
  String get defaultLabel {
    switch (this) {
      case OrientationKind.a:
        return 'Direction A';
      case OrientationKind.b:
        return 'Direction B';
    }
  }
}

class DirectionReadingSample {
  DirectionReadingSample({
    required this.timestamp,
    this.resistanceOhm,
    this.standardDeviationPercent,
    this.note = '',
    this.isBad = false,
  });

  factory DirectionReadingSample.fromJson(Map<String, dynamic> json) {
    return DirectionReadingSample(
      timestamp: DateTime.parse(json['timestamp'] as String),
      resistanceOhm: (json['resistance_ohm'] as num?)?.toDouble(),
      standardDeviationPercent: (json['sd_pct'] as num?)?.toDouble(),
      note: json['note'] as String? ?? '',
      isBad: json['is_bad'] as bool? ?? false,
    );
  }

  final DateTime timestamp;
  final double? resistanceOhm;
  final double? standardDeviationPercent;
  final bool isBad;
  final String note;

  double? apparentResistivityOhmM(double spacingFeet) {
    if (resistanceOhm == null) {
      return null;
    }
    return rhoAWenner(spacingFeet, resistanceOhm!);
  }

  DirectionReadingSample copyWith({
    DateTime? timestamp,
    Object? resistanceOhm = _unset,
    Object? standardDeviationPercent = _unset,
    bool? isBad,
    String? note,
  }) {
    return DirectionReadingSample(
      timestamp: timestamp ?? this.timestamp,
      resistanceOhm: identical(resistanceOhm, _unset)
          ? this.resistanceOhm
          : (resistanceOhm as double?),
      standardDeviationPercent: identical(standardDeviationPercent, _unset)
          ? this.standardDeviationPercent
          : (standardDeviationPercent as double?),
      isBad: isBad ?? this.isBad,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'resistance_ohm': resistanceOhm,
        'sd_pct': standardDeviationPercent,
        'note': note,
        'is_bad': isBad,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DirectionReadingSample &&
        other.timestamp == timestamp &&
        other.resistanceOhm == resistanceOhm &&
        other.standardDeviationPercent == standardDeviationPercent &&
        other.note == note &&
        other.isBad == isBad;
  }

  @override
  int get hashCode => Object.hash(
        timestamp,
        resistanceOhm,
        standardDeviationPercent,
        note,
        isBad,
      );

  static const _unset = Object();
}

class DirectionReadingHistory {
  DirectionReadingHistory({
    required this.orientation,
    required this.label,
    List<DirectionReadingSample>? samples,
  }) : samples = List.unmodifiable(samples ?? const <DirectionReadingSample>[]);

  factory DirectionReadingHistory.fromJson(Map<String, dynamic> json) {
    return DirectionReadingHistory(
      orientation: OrientationKind.values.byName(json['orientation'] as String),
      label: json['label'] as String? ??
          OrientationKind.values
              .byName(json['orientation'] as String)
              .defaultLabel,
      samples: (json['samples'] as List<dynamic>? ?? const [])
          .map((dynamic e) =>
              DirectionReadingSample.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final OrientationKind orientation;
  final String label;
  final List<DirectionReadingSample> samples;

  DirectionReadingSample? get latest =>
      samples.lastWhereOrNull((sample) {
        if (sample.isBad) {
          return false;
        }
        return sample.resistanceOhm != null;
      }) ??
      samples.lastOrNull;

  bool get hasValidSample => samples.any((sample) => !sample.isBad);

  DirectionReadingHistory addSample(DirectionReadingSample sample) {
    final updated = [...samples, sample];
    return DirectionReadingHistory(
      orientation: orientation,
      label: label,
      samples: updated,
    );
  }

  DirectionReadingHistory updateLatest(
      DirectionReadingSample Function(DirectionReadingSample current) updater) {
    if (samples.isEmpty) {
      return addSample(
          updater(DirectionReadingSample(timestamp: DateTime.now())));
    }
    final updatedSamples = [...samples];
    updatedSamples[updatedSamples.length - 1] = updater(updatedSamples.last);
    return DirectionReadingHistory(
      orientation: orientation,
      label: label,
      samples: updatedSamples,
    );
  }

  DirectionReadingHistory copyWith({
    String? label,
    List<DirectionReadingSample>? samples,
  }) {
    return DirectionReadingHistory(
      orientation: orientation,
      label: label ?? this.label,
      samples: samples ?? this.samples,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'orientation': orientation.name,
        'label': label,
        'samples': samples.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DirectionReadingHistory &&
        other.orientation == orientation &&
        other.label == label &&
        const ListEquality<DirectionReadingSample>().equals(
          other.samples,
          samples,
        );
  }

  @override
  int get hashCode =>
      Object.hash(orientation, label, const ListEquality().hash(samples));

  @override
  String toString() => jsonEncode(toJson());
}
