import 'units.dart';

enum DistanceUnit { meters, feet }

extension DistanceUnitX on DistanceUnit {
  String get label {
    switch (this) {
      case DistanceUnit.meters:
        return 'Meters';
      case DistanceUnit.feet:
        return 'Feet';
    }
  }

  String get axisLabel {
    switch (this) {
      case DistanceUnit.meters:
        return 'a-spacing (m)';
      case DistanceUnit.feet:
        return 'a-spacing (ft)';
    }
  }

  double fromMeters(double meters) {
    switch (this) {
      case DistanceUnit.meters:
        return meters;
      case DistanceUnit.feet:
        return metersToFeet(meters);
    }
  }

  String formatSpacing(double meters) {
    final value = fromMeters(meters);
    final absValue = value.abs();
    if (absValue >= 1000) {
      return value.toStringAsFixed(0);
    }
    if (absValue >= 100) {
      return value.toStringAsFixed(0);
    }
    if (absValue >= 10) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(2);
  }

  static DistanceUnit parse(String? name, {DistanceUnit fallback = DistanceUnit.meters}) {
    if (name == null) return fallback;
    return DistanceUnit.values.firstWhere(
      (unit) => unit.name == name,
      orElse: () => fallback,
    );
  }
}
