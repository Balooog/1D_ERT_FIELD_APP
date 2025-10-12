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
    if (!value.isFinite) {
      return value.toString();
    }

    double? rounded;
    int fractionDigits;
    if (absValue >= 1000) {
      fractionDigits = 0;
    } else if (absValue >= 100) {
      fractionDigits = 0;
    } else if (absValue >= 10) {
      final nearestFive = (value / 5).round() * 5;
      if ((nearestFive - value).abs() <= 0.1) {
        rounded = nearestFive.toDouble();
        fractionDigits = 0;
      } else {
        fractionDigits = 1;
      }
    } else if (absValue >= 1) {
      fractionDigits = 1;
    } else if (absValue >= 0.1) {
      fractionDigits = 2;
    } else {
      fractionDigits = 3;
    }

    final target = rounded ?? value;
    final formatted = target.toStringAsFixed(fractionDigits);
    return _stripTrailingZeros(formatted);
  }

  static DistanceUnit parse(String? name,
      {DistanceUnit fallback = DistanceUnit.meters}) {
    if (name == null) return fallback;
    return DistanceUnit.values.firstWhere(
      (unit) => unit.name == name,
      orElse: () => fallback,
    );
  }
}

String _stripTrailingZeros(String value) {
  if (!value.contains('.')) {
    return value;
  }
  return value.replaceFirst(RegExp(r'\.?0+$'), '');
}
