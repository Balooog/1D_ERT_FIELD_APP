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
  sheet.appendRow(const [
    'a_spacing_ft',
    'pins_in_ft',
    'pins_out_ft',
    'res_ns_ohm',
    'res_we_ohm',
    'sd_ns_pct',
    'sd_we_pct',
  ]);
  sheet.appendRow(const ['5', '10', '16', '230', '231', '2.5', '2.7']);
  sheet.appendRow(const ['10', '20', '26', '410', '415', '3.0', '3.1']);
  sheet.appendRow(const ['20', '30', '36', '690', '700', '3.4', '3.6']);

  final encoded = workbook.encode();
  if (encoded == null) {
    throw StateError('Failed to encode sample workbook');
  }
  return Uint8List.fromList(encoded);
}

void main() {
  final service = ImportService();

  group('ImportService', () {
    test('parses CSV and validates mapping', () async {
      final bytes = await _loadBytes('test/data/import_samples/resicheck_sample.csv');
      final session = await service.load(
        ImportSource(name: 'resicheck_sample.csv', bytes: bytes),
      );
      final mapping = service.autoMap(session.preview);
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 3);
      expect(validation.spacings.first.spacingFeet, closeTo(5, 1e-6));
    });

    test('parses tab-delimited TXT with metre units', () async {
      final bytes = await _loadBytes('test/data/import_samples/resicheck_sample.txt');
      final session = await service.load(
        ImportSource(name: 'resicheck_sample.txt', bytes: bytes),
      );
      final auto = service.autoMap(session.preview);
      final mapping = ImportMapping(
        assignments: auto.assignments,
        distanceUnit: ImportDistanceUnit.meters,
      );
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 3);
      expect(validation.spacings.first.spacingFeet, closeTo(4.92126, 1e-5));
    });

    test('parses Surfer DAT XYZ files', () async {
      final bytes = await _loadBytes('test/data/import_samples/surfer_xyz_example.dat');
      final session = await service.load(
        ImportSource(name: 'surfer_xyz_example.dat', bytes: bytes),
      );
      final mapping = ImportMapping(assignments: {
        0: ImportColumnTarget.aSpacingFeet,
        2: ImportColumnTarget.resistanceNsOhm,
      }, distanceUnit: ImportDistanceUnit.feet);
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 3);
      expect(validation.spacings.length, 3);
    });

    test('parses Excel workbooks', () async {
      final bytes = _buildSampleWorkbook();
      final session = await service.load(
        ImportSource(name: 'resicheck_sample.xlsx', bytes: bytes),
      );
      final mapping = service.autoMap(session.preview);
      final validation = service.validate(session, mapping);
      expect(validation.importedRows, 3);
      expect(validation.spacings.last.spacingFeet, closeTo(20, 1e-6));
    });
  });
}
