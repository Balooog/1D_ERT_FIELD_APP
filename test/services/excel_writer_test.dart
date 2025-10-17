import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/enums.dart';
import 'package:resicheck/models/project.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/utils/excel_writer.dart';

void main() {
  group('ThgExcelWriter', () {
    test('builds summary/data sheets for Wenner export', () {
      final site = _buildSite();
      final project = _buildProject(
        arrayType: ArrayType.wenner,
        sites: [site],
      );
      final writer = ThgExcelWriter(
        project: project,
        sites: project.sites,
        generatedAt: DateTime.utc(2024, 5, 4),
        operatorName: 'Operator X',
      );

      final bytes = writer.build();
      final excel = Excel.decodeBytes(bytes);

      expect(excel.tables.containsKey('Summary'), isTrue);
      expect(excel.tables.containsKey('Data'), isTrue);
      expect(excel.tables.containsKey('Notes'), isTrue);

      final summary = excel['Summary'];
      expect(_stringValue(summary, 0, 0), 'Project');
      expect(_stringValue(summary, 1, 0), 'Example Project');
      expect(_stringValue(summary, 1, 1), equals(site.displayName));
      expect(_stringValue(summary, 1, 4), 'Wenner');
      expect(_stringValue(summary, 1, 5), 'ft / Ω·m');

      final data = excel['Data'];
      expect(_stringValue(data, 0, 3), 'a_ft');
      expect(_stringValue(data, 1, 2), 'N–S');
      expect(_numericValue(data, 1, 3), closeTo(10.0, 0.0001));
      expect(_numericValue(data, 1, 4), closeTo(3.048, 0.0001));

      final rhoCell = data.cell(CellIndex.indexByColumnRow(
        columnIndex: 9,
        rowIndex: 1,
      ));
      expect(rhoCell.isFormula, isTrue);
      expect(rhoCell.value.toString(), contains('2*PI()*'));

      final sigmaCell = data.cell(CellIndex.indexByColumnRow(
        columnIndex: 10,
        rowIndex: 1,
      ));
      expect(sigmaCell.isFormula, isTrue);
      expect(sigmaCell.value.toString(), contains('/100)'));
    });

    test('uses Schlumberger geometry columns and formulas', () {
      final site = _buildSite();
      final project = _buildProject(
        arrayType: ArrayType.schlumberger,
        sites: [site],
      );
      final writer = ThgExcelWriter(
        project: project,
        sites: project.sites,
        generatedAt: DateTime.utc(2024, 6, 1),
      );

      final bytes = writer.build();
      final excel = Excel.decodeBytes(bytes);
      final data = excel['Data'];

      expect(_stringValue(data, 0, 5), 'MN/2_ft');
      expect(_numericValue(data, 1, 5), isNotNull);
      expect(_numericValue(data, 1, 6), isNotNull);

      final rhoCell = data.cell(CellIndex.indexByColumnRow(
        columnIndex: 9,
        rowIndex: 1,
      ));
      expect(rhoCell.isFormula, isTrue);
      expect(
        rhoCell.value.toString(),
        equals('=IF(OR(H2="", G2=""),"",PI()*(((E2)^2)-((G2)^2))/(G2*2)*H2)'),
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
  final value = cell.value;
  if (value == null) {
    return null;
  }
  return value.toString();
}

double? _numericValue(Sheet sheet, int row, int column) {
  final cell = sheet.cell(
    CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
  );
  final value = cell.value;
  if (value is num) {
    return value.toDouble();
  }
  if (value == null) {
    return null;
  }
  return double.tryParse(value.toString());
}
