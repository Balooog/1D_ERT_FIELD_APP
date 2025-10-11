import 'dart:io';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import '../models/enums.dart';
import '../models/spacing_point.dart';
import '../services/geometry_factors.dart' as geom;

class CsvColumns {
  static const aSpacingFt = 'a_spacing_ft';
  static const aSpacingM = 'a_spacing_m';
  static const spacingLegacy = 'spacing_m';
  static const resistance = 'resistance_ohm';
  static const resistanceStd = 'resistance_std_ohm';
  static const rho = 'rho_app_ohm_m';
  static const rhoLegacy = 'rho_app';
  static const sigmaRho = 'sigma_rho_ohm_m';
  static const sigmaRhoLegacy = 'sigma_rho_app';
  static const direction = 'direction';
  static const voltage = 'voltage_v';
  static const current = 'current_a';
  static const array = 'array_type';
  static const timestamp = 'timestamp_iso';
}

class CsvIoService {
  Future<List<SpacingPoint>> readFile(File file) async {
    final raw = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n')
        .convert(raw, shouldParseNumbers: false);
    if (rows.isEmpty) return [];

    final header = rows.first.map((e) => e.toString()).toList();
    final indexMap = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      indexMap[_normalizeHeader(header[i])] = i;
    }

    final points = <SpacingPoint>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      double? aFeet = _readDouble(row, indexMap, [CsvColumns.aSpacingFt]);
      double? aMeters = _readDouble(
          row, indexMap, [CsvColumns.aSpacingM, CsvColumns.spacingLegacy]);
      double? resistance = _readDouble(row, indexMap, [CsvColumns.resistance]);
      double? resistanceStd =
          _readDouble(row, indexMap, [CsvColumns.resistanceStd]);
      double? rho =
          _readDouble(row, indexMap, [CsvColumns.rho, CsvColumns.rhoLegacy]);
      double? sigmaRho = _readDouble(
          row, indexMap, [CsvColumns.sigmaRho, CsvColumns.sigmaRhoLegacy]);
      final voltage = _readDouble(row, indexMap, [CsvColumns.voltage]);
      final current = _readDouble(row, indexMap, [CsvColumns.current]);
      final directionText = _readString(row, indexMap, [CsvColumns.direction]);
      final array = _readArray(row, indexMap, [CsvColumns.array]);
      final timestampText = _readString(row, indexMap, [CsvColumns.timestamp]);

      if (array == null) {
        continue;
      }

      aMeters ??= aFeet != null ? feetToMeters(aFeet) : null;
      aFeet ??= aMeters != null ? metersToFeet(aMeters) : null;

      if (rho == null && resistance != null && aMeters != null) {
        final k = _geometryFactorForArray(array, aMeters);
        if (k > 0) {
          rho = resistance * k;
        }
      }

      if (rho == null &&
          voltage != null &&
          current != null &&
          current != 0 &&
          aMeters != null) {
        final derivedResistance = voltage / current;
        final k = _geometryFactorForArray(array, aMeters);
        if (k > 0) {
          rho = derivedResistance * k;
          resistance ??= derivedResistance;
        }
      }

      if (sigmaRho == null && resistanceStd != null && aMeters != null) {
        final k = _geometryFactorForArray(array, aMeters);
        if (k > 0) {
          sigmaRho = k * resistanceStd;
        }
      }

      DateTime? timestamp;
      if (timestampText != null) {
        timestamp = DateTime.tryParse(timestampText);
      }

      try {
        points.add(
          SpacingPoint(
            id: '${i}_${DateTime.now().millisecondsSinceEpoch}',
            arrayType: array,
            aFeet: aFeet,
            spacingMetric: aMeters,
            rhoAppOhmM: rho,
            sigmaRhoOhmM: sigmaRho,
            resistanceOhm: resistance,
            resistanceStdOhm: resistanceStd,
            direction: parseSoundingDirection(directionText),
            voltageV: voltage,
            currentA: current,
            contactR: const {},
            spDriftMv: null,
            stacks: 1,
            repeats: null,
            timestamp: timestamp ?? DateTime.now(),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return points;
  }

  Future<File> writeFile(File file, List<SpacingPoint> points) async {
    final header = [
      CsvColumns.aSpacingFt,
      CsvColumns.aSpacingM,
      CsvColumns.spacingLegacy,
      CsvColumns.rho,
      CsvColumns.sigmaRho,
      CsvColumns.direction,
      CsvColumns.voltage,
      CsvColumns.current,
      CsvColumns.resistance,
      CsvColumns.resistanceStd,
      CsvColumns.array,
      CsvColumns.timestamp,
    ];
    final data = <List<dynamic>>[header];
    for (final point in points) {
      data.add([
        point.aFeet,
        point.aMeters,
        point.spacingMetric,
        point.rhoAppOhmM,
        point.sigmaRhoOhmM,
        point.direction.csvValue,
        point.voltageV,
        point.currentA,
        point.resistanceOhm,
        point.resistanceStdOhm,
        point.arrayType.name,
        point.timestamp.toIso8601String(),
      ]);
    }
    final csv = const ListToCsvConverter().convert(data);
    await file.create(recursive: true);
    await file.writeAsString(csv);
    return file;
  }

  double? _readDouble(
      List<dynamic> row, Map<String, int> indexMap, List<String> keys) {
    for (final key in keys) {
      final index = indexMap[_normalizeHeader(key)];
      final value = _parseDouble(row, index);
      if (value != null) return value;
    }
    return null;
  }

  String? _readString(
      List<dynamic> row, Map<String, int> indexMap, List<String> keys) {
    for (final key in keys) {
      final index = indexMap[_normalizeHeader(key)];
      final value = _parseString(row, index);
      if (value != null) return value;
    }
    return null;
  }

  ArrayType? _readArray(
      List<dynamic> row, Map<String, int> indexMap, List<String> keys) {
    final text = _readString(row, indexMap, keys);
    if (text == null) return null;
    return ArrayType.values.firstWhere(
      (type) => type.name.toLowerCase() == text.toLowerCase(),
      orElse: () => ArrayType.custom,
    );
  }

  double? _parseDouble(List<dynamic> row, int? index) {
    if (index == null || index >= row.length) return null;
    final value = row[index];
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  String? _parseString(List<dynamic> row, int? index) {
    if (index == null || index >= row.length) return null;
    final value = row[index];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

String _normalizeHeader(String header) =>
    header.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

double _geometryFactorForArray(ArrayType arrayType, double spacingMeters) {
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

Future<File> getDefaultExportFile(String directory, {String? basename}) async {
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final name = basename ?? 'resicheck_export_$timestamp.csv';
  final file = File(p.join(directory, name));
  if (!await file.exists()) {
    await file.create(recursive: true);
  }
  return file;
}
