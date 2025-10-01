import 'dart:math' as math;

enum GeometryArray { wenner, schlumberger }

double geometryFactor({
  required GeometryArray array,
  required double spacing,
  double? mn,
}) {
  switch (array) {
    case GeometryArray.wenner:
      return 2 * math.pi * spacing;
    case GeometryArray.schlumberger:
      if (mn == null || mn <= 0) {
        throw ArgumentError('MN/2 spacing required for Schlumberger geometry.');
      }
      final abOver2 = spacing;
      final mnOver2 = mn / 2;
      final numerator = math.pow(abOver2, 2) - math.pow(mnOver2, 2);
      return math.pi * numerator / (mnOver2 * 2);
  }
}

Map<String, double> rhoAppFromReadings({
  required GeometryArray array,
  required double spacing,
  required double voltage,
  required double current,
  double? mn,
}) {
  final k = geometryFactor(array: array, spacing: spacing, mn: mn);
  final rho = k * voltage / current;
  return {'k': k, 'rho': rho};
}
