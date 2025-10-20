import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/enums.dart';
import 'package:resicheck/models/project.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/services/export_excel_updated.dart';

void main() {
  group('UpdatedExcelWriter', () {
    test('builds summary/data sheets for Wenner export', () {
      final site = _buildSite();
      final project = _buildProject(
        arrayType: ArrayType.wenner,
        sites: [site],
      );
      final writer = UpdatedExcelWriter(
        project: project,
        sites: project.sites,
        generatedAt: DateTime.utc(2024, 5, 4),
        operatorName: 'Operator X',
        includeGps: true,
      );

      final bytes = writer.build();
      final excel = Excel.decodeBytes(bytes);

      final summary = excel['Summary'];
      expect(_stringValue(summary, 2, 0), 'Project');
      expect(_stringValue(summary, 2, 1), 'Example Project');
      expect(_stringValue(summary, 3, 1), site.displayName);
      expect(_stringValue(summary, 6, 1), 'Wenner');
      expect(_stringValue(summary, 7, 1), 'ft / Ω·m');

      final data = excel['Data'];
      expect(_stringValue(data, 0, 0), 'Row');
      expect(_stringValue(data, 0, 2), 'a_ft');
      expect(_numericValue(data, 1, 1), closeTo(3.048, 0.0001));
      expect(_numericValue(data, 1, 2), closeTo(10.0, 0.0001));
      expect(_stringValue(data, 1, 9), 'ns');
      expect(_stringValue(data, 1, 10), '2024-01-01T00:00:00.000Z');

      final rhoCell =
          data.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1));
      expect(rhoCell.value, isA<FormulaCellValue>());
      expect(rhoCell.value.toString(), contains('2*PI()*B2*E2'));

      final sigmaCell =
          data.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 1));
      expect(sigmaCell.value, isA<FormulaCellValue>());
      expect(sigmaCell.value.toString(), contains('4.500'));
    });

    test('uses Schlumberger geometry columns and formulas', () {
      final site = _buildSite();
      final project = _buildProject(
        arrayType: ArrayType.schlumberger,
        sites: [site],
      );
      final writer = UpdatedExcelWriter(
        project: project,
        sites: project.sites,
        generatedAt: DateTime.utc(2024, 6, 1),
        includeGps: true,
      );

      final bytes = writer.build();
      final excel = Excel.decodeBytes(bytes);
      final data = excel['Data'];

      expect(_stringValue(data, 0, 3), 'L_m (Schlumb)');
      expect(_numericValue(data, 1, 1), closeTo(0.508, 0.0001));
      expect(_numericValue(data, 1, 3), closeTo(3.048, 0.0001));

      final rhoCell =
          data.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1));
      expect(
        rhoCell.value.toString(),
        contains('PI()*(((D2^2)-(B2^2))/(2*B2))*E2'),
      );
    });
  });
}

ProjectRecord _buildProject({
  required ArrayType arrayType,
  required List<SiteRecord> sites,
}) {
  return ProjectRecord(
    projectId: 'proj-1',
    projectName: 'Example Project',
    arrayType: arrayType,
    canonicalSpacingsFeet: const [10, 20],
    defaultPowerMilliAmps: 0.5,
    defaultStacks: 4,
    sites: sites,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 2),
  );
}

SiteRecord _buildSite() {
  final spacing = SpacingRecord(
    spacingFeet: 10,
    orientationA: DirectionReadingHistory(
      orientation: OrientationKind.a,
      label: 'N–S',
      samples: [
        DirectionReadingSample(
          timestamp: DateTime.utc(2024, 1, 1),
          resistanceOhm: 12.3,
          standardDeviationPercent: 4.5,
          note: 'Solid contact',
          isBad: false,
        ),
      ],
    ),
    orientationB: DirectionReadingHistory(
      orientation: OrientationKind.b,
      label: 'W–E',
      samples: [
        DirectionReadingSample(
          timestamp: DateTime.utc(2024, 1, 1, 0, 2),
          resistanceOhm: 11.8,
          standardDeviationPercent: 5.0,
          note: '',
          isBad: false,
        ),
      ],
    ),
  );

  return SiteRecord(
    siteId: 'ERT-1',
    displayName: 'ERT-1',
    spacings: [spacing],
    location: SiteLocation(latitude: 34.1234, longitude: -96.9876),
  );
}

String? _stringValue(Sheet sheet, int row, int column) {
  final cell = sheet.cell(
    CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
  );
  return _cellAsString(cell.value);
}

double? _numericValue(Sheet sheet, int row, int column) {
  final cell = sheet.cell(
    CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
  );
  final value = cell.value;
  if (value is IntCellValue) {
    return value.value.toDouble();
  }
  if (value is DoubleCellValue) {
    return value.value;
  }
  if (value is TextCellValue) {
    return double.tryParse(value.value.toString());
  }
  return double.tryParse(_cellAsString(value) ?? '');
}

String? _cellAsString(CellValue? value) {
  if (value == null) {
    return null;
  }
  if (value is TextCellValue) {
    return value.value.toString();
  }
  if (value is IntCellValue) {
    return value.value.toString();
  }
  if (value is DoubleCellValue) {
    return value.value.toString();
  }
  if (value is FormulaCellValue) {
    return value.formula;
  }
  if (value is BoolCellValue) {
    return value.value.toString();
  }
  if (value is DateCellValue) {
    return value.toString();
  }
  if (value is DateTimeCellValue) {
    return value.toString();
  }
  return value.toString();
}
