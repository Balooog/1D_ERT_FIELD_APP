import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/services/import/import_models.dart';
import 'package:resicheck/services/import/import_service.dart';

Future<Uint8List> _loadBytes(String relativePath) async {
  final file = File(relativePath);
  return file.readAsBytes();
}

Uint8List _buildSampleWorkbook() {
  final workbook = Excel.createExcel();
  final sheet = workbook['Sheet1'];
  sheet.appendRow(_textRow(['Unit=feet']));
  sheet.appendRow(_textRow([
    'a_spacing_ft',
    'pins_in_ft',
    'pins_out_ft',
    'res_ns_ohm',
    'res_we_ohm',
    'sd_ns_pct',
    'sd_we_pct',
  ]));
  sheet.appendRow(_textRow(['5', '10', '16', '230', '231', '2.5', '2.7']));
  sheet.appendRow(_textRow(['10', '20', '26', '410', '415', '3.0', '3.1']));
  sheet.appendRow(_textRow(['20', '30', '36', '690', '700', '3.4', '3.6']));

  final encoded = workbook.encode();
  if (encoded == null) {
    throw StateError('Failed to encode sample workbook');
  }
  return Uint8List.fromList(encoded);
}

List<CellValue?> _textRow(List<String> values) {
  return values.map((value) => TextCellValue(value)).toList();
}

void main() {
  final service = ImportService();

  group('ImportService', () {
    test('parses Wenner CSV and detects meters', () async {
      final bytes = await _loadBytes('test/data/import_samples/Wenner1D.csv');
      final session = await service.load(
        ImportSource(name: 'Wenner1D.csv', bytes: bytes),
      );
      expect(session.preview.unitDetection.unit, ImportDistanceUnit.meters);
      expect(
        session.preview.unitDetection.reason?.toLowerCase(),
        contains('header'),
      );
      final mapping = service.autoMap(session.preview);
      expect(mapping.assignments.length, 6);
      expect(mapping.assignments.values, contains(ImportColumnTarget.units));
      expect(mapping.distanceUnit, ImportDistanceUnit.meters);
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 5);
      expect(validation.spacings.first.spacingFeet, closeTo(16.404, 0.01));
    });

    test('parses Schlumberger CSV and keeps feet units', () async {
      final bytes = await _loadBytes('test/data/import_samples/Schlum1D.csv');
      final session = await service.load(
        ImportSource(name: 'Schlum1D.csv', bytes: bytes),
      );
      expect(session.preview.unitDetection.unit, ImportDistanceUnit.feet);
      expect(
        session.preview.unitDetection.reason?.toLowerCase(),
        anyOf(contains('filename'), contains('directive')),
      );
      final mapping = service.autoMap(session.preview);
      expect(mapping.distanceUnit, ImportDistanceUnit.feet);
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 5);
      expect(validation.spacings.first.spacingFeet, closeTo(10, 1e-6));
    });

    test('parses Surfer DAT with metadata rows', () async {
      final bytes = await _loadBytes('test/data/import_samples/Wenner1D.dat');
      final session = await service.load(
        ImportSource(name: 'Wenner1D.dat', bytes: bytes),
      );
      expect(session.preview.columnCount, 3);
      expect(session.preview.unitDetection.unit, ImportDistanceUnit.meters);
      final mapping = ImportMapping(assignments: {
        0: ImportColumnTarget.aSpacingFeet,
        2: ImportColumnTarget.resistanceNsOhm,
      }, distanceUnit: ImportDistanceUnit.meters);
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 5);
      expect(validation.spacings.length, 5);
    });

    test('parses Excel workbooks with unit directives', () async {
      final bytes = _buildSampleWorkbook();
      final session = await service.load(
        ImportSource(name: 'import_sample.xlsx', bytes: bytes),
      );
      final mapping = service.autoMap(session.preview);
      expect(session.preview.unitDetection.unit, ImportDistanceUnit.feet);
      expect(mapping.distanceUnit, ImportDistanceUnit.feet);
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 3);
      expect(validation.spacings.last.spacingFeet, closeTo(20, 1e-6));
    });
  });
}
