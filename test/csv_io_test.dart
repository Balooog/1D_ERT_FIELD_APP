import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/enums.dart';
import 'package:ves_qc/models/spacing_point.dart';
import 'package:ves_qc/services/csv_io.dart';

void main() {
  test('CSV roundtrip exports resistance-first columns', () async {
    final service = CsvIoService();
    final temp = await File('${Directory.systemTemp.path}/ves_qc_test_new.csv').create(recursive: true);
    final point = SpacingPoint(
      id: '1',
      arrayType: ArrayType.wenner,
      aFeet: 10,
      resistanceOhm: 25,
      resistanceStdOhm: 1.5,
      direction: SoundingDirection.ns,
      voltageV: 12.5,
      currentA: 0.5,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      rhoApp: 2 * math.pi * feetToMeters(10) * 25,
      sigmaRhoApp: 2 * math.pi * feetToMeters(10) * 1.5,
      timestamp: DateTime.now(),
    );
    await service.writeFile(temp, [point]);
    final csv = await temp.readAsString();
    expect(csv.contains(CsvColumns.aSpacingFt), isTrue);
    expect(csv.contains(CsvColumns.resistance), isTrue);
    final readBack = await service.readFile(temp);
    expect(readBack, hasLength(1));
    final loaded = readBack.first;
    expect(loaded.aFeet, closeTo(point.aFeet, 1e-6));
    expect(loaded.resistanceOhm, closeTo(point.resistanceOhm, 1e-6));
    expect(loaded.direction, point.direction);
  });

  test('Legacy CSV import derives resistance and preserves rho', () async {
    final csv = [
      'spacing_m,voltage_v,current_a,array_type,rho_app_ohm_m,sigma_rho_app,timestamp_iso',
      '5,1.2,0.4,wenner,100,5,2024-01-01T00:00:00Z',
    ].join('\n');
    final file = await File('${Directory.systemTemp.path}/ves_qc_legacy.csv').create(recursive: true);
    await file.writeAsString(csv);
    final points = await CsvIoService().readFile(file);
    expect(points, hasLength(1));
    final point = points.first;
    expect(point.aMeters, closeTo(5, 1e-6));
    expect(point.rhoAppOhmM, closeTo(100, 1e-6));
    expect(point.resistanceOhm, closeTo(100 / (2 * math.pi * 5), 1e-6));
    expect(point.rFromVi, closeTo(1.2 / 0.4, 1e-6));
  });
}
