import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import '../models/enums.dart';
import '../models/spacing_point.dart';

class CsvColumns {
  static const aSpacingFt = 'a_spacing_ft';
  static const aSpacingM = 'a_spacing_m';
  static const spacingLegacy = 'spacing_m';
  static const resistance = 'resistance_ohm';
  static const resistanceStd = 'resistance_std_ohm';
  static const direction = 'direction';
  static const voltage = 'voltage_v';
  static const current = 'current_a';
  static const array = 'array_type';
  static const mn = 'mn_over_2_m';
  static const rho = 'rho_app_ohm_m';
  static const sigma = 'sigma_rho_app';
  static const timestamp = 'timestamp_iso';
}

class CsvIoService {
  Future<List<SpacingPoint>> readFile(File file) async {
    final raw = await file.readAsString();
    final rows = const CsvToListConverter(eol: '\n').convert(raw, shouldParseNumbers: false);
    if (rows.isEmpty) return [];
    final header = rows.first.map((e) => e.toString()).toList();
    final idx = {
      for (var i = 0; i < header.length; i++) header[i]: i,
    };
    final points = <SpacingPoint>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final aFeet = _parseDouble(row, idx[CsvColumns.aSpacingFt]);
      final aMeters = _parseDouble(row, idx[CsvColumns.aSpacingM]);
      final spacingLegacy = _parseDouble(row, idx[CsvColumns.spacingLegacy]);
      final resistance = _parseDouble(row, idx[CsvColumns.resistance]);
      final resistanceStd = _parseDouble(row, idx[CsvColumns.resistanceStd]);
      final directionText = _parseString(row, idx[CsvColumns.direction]);
      final voltage = _parseDouble(row, idx[CsvColumns.voltage]);
      final current = _parseDouble(row, idx[CsvColumns.current]);
      final array = _parseArray(row, idx[CsvColumns.array]);
      final rho = _parseDouble(row, idx[CsvColumns.rho]);
      final sigma = _parseDouble(row, idx[CsvColumns.sigma]);
      final timestamp = _parseString(row, idx[CsvColumns.timestamp]);

      if (array == null) {
        continue;
      }

      try {
        points.add(SpacingPoint(
          id: '${i}_${DateTime.now().millisecondsSinceEpoch}',
          arrayType: array,
          aFeet: aFeet,
          spacingMetric: aMeters ?? spacingLegacy,
          resistanceOhm: resistance,
          resistanceStdOhm: resistanceStd,
          direction: parseSoundingDirection(directionText),
          voltageV: voltage,
          currentA: current,
          contactR: const {},
          spDriftMv: null,
          stacks: 1,
          repeats: null,
          rhoApp: rho,
          sigmaRhoApp: sigma,
          timestamp: timestamp != null ? DateTime.parse(timestamp) : DateTime.now(),
        ));
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
      CsvColumns.resistance,
      CsvColumns.resistanceStd,
      CsvColumns.direction,
      CsvColumns.voltage,
      CsvColumns.current,
      CsvColumns.array,
      CsvColumns.mn,
      CsvColumns.rho,
      CsvColumns.sigma,
      CsvColumns.timestamp,
    ];
    final data = <List<dynamic>>[header];
    for (final point in points) {
      data.add([
        point.aFeet,
        point.aMeters,
        point.spacingMetric,
        point.resistanceOhm,
        point.resistanceStdOhm,
        point.direction.csvValue,
        point.voltageV,
        point.currentA,
        point.arrayType.name,
        '',
        point.rhoAppOhmM,
        point.sigmaRhoApp,
        point.timestamp.toIso8601String(),
      ]);
    }
    final csv = const ListToCsvConverter().convert(data);
    await file.create(recursive: true);
    await file.writeAsString(csv);
    return file;
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
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  ArrayType? _parseArray(List<dynamic> row, int? index) {
    final text = _parseString(row, index);
    if (text == null) return null;
    return ArrayType.values.firstWhere(
      (type) => type.name.toLowerCase() == text.toLowerCase(),
      orElse: () => ArrayType.custom,
    );
  }
}

Future<File> getDefaultExportFile(String directory, {String? basename}) async {
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final name = basename ?? 'ves_qc_export_$timestamp.csv';
  final file = File(p.join(directory, name));
  if (!await file.exists()) {
    await file.create(recursive: true);
  }
  return file;
}
