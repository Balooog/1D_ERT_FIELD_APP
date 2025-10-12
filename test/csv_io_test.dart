import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/project_models.dart' show ArrayType;
import 'package:resicheck/models/spacing_point.dart';
import 'package:resicheck/services/csv_io.dart';

void main() {
  test('CSV roundtrip preserves feet, rho, sigma, and direction', () async {
    final service = CsvIoService();
    final temp =
        await File('${Directory.systemTemp.path}/resicheck_roundtrip.csv')
            .create(recursive: true);
    final point = SpacingPoint(
      id: '1',
      arrayType: ArrayType.wenner,
      aFeet: 10,
      rhoAppOhmM: 2 * math.pi * feetToMeters(10) * 25,
      sigmaRhoOhmM: 2 * math.pi * feetToMeters(10) * 1.5,
      direction: SoundingDirection.ns,
      voltageV: 12.5,
      currentA: 0.5,
      contactR: const {},
      spDriftMv: null,
      stacks: 1,
      repeats: null,
      timestamp: DateTime.now(),
    );
    await service.writeFile(temp, [point]);
    final csv = await temp.readAsString();
    expect(csv.contains(CsvColumns.aSpacingFt), isTrue);
    expect(csv.contains(CsvColumns.rho), isTrue);
    expect(csv.contains(CsvColumns.sigmaRho), isTrue);

    final readBack = await service.readFile(temp);
    expect(readBack, hasLength(1));
    final loaded = readBack.first;
    expect(loaded.aFeet, closeTo(point.aFeet, 1e-6));
    expect(loaded.rhoAppOhmM, closeTo(point.rhoAppOhmM, 1e-6));
    expect(loaded.sigmaRhoOhmM, closeTo(point.sigmaRhoOhmM!, 1e-6));
    expect(loaded.direction, point.direction);
  });

  test('Legacy CSV import derives missing rho and feet from spacing_m and V/I',
      () async {
    final csv = [
      'spacing_m,voltage_v,current_a,array_type,timestamp_iso',
      '5,1.2,0.4,wenner,2024-01-01T00:00:00Z',
    ].join('\n');
    final file = await File('${Directory.systemTemp.path}/resicheck_legacy.csv')
        .create(recursive: true);
    await file.writeAsString(csv);
    final points = await CsvIoService().readFile(file);
    expect(points, hasLength(1));
    final point = points.first;
    expect(point.aMeters, closeTo(5, 1e-6));
    expect(point.aFeet, closeTo(metersToFeet(5), 1e-6));
    const derivedRho = 2 * math.pi * 5 * (1.2 / 0.4);
    expect(point.rhoAppOhmM, closeTo(derivedRho, 1e-6));
    expect(point.rhoFromVi, closeTo(derivedRho, 1e-6));
  });

  test('Direction enum round-trips through CSV', () async {
    final service = CsvIoService();
    final temp =
        await File('${Directory.systemTemp.path}/resicheck_direction.csv')
            .create(recursive: true);
    final points = [
      SpacingPoint(
        id: 'ns',
        arrayType: ArrayType.wenner,
        aFeet: 6,
        rhoAppOhmM: 80,
        direction: SoundingDirection.ns,
        contactR: const {},
        spDriftMv: null,
        stacks: 1,
        repeats: null,
        timestamp: DateTime.now(),
      ),
      SpacingPoint(
        id: 'we',
        arrayType: ArrayType.wenner,
        aFeet: 8,
        rhoAppOhmM: 120,
        direction: SoundingDirection.we,
        contactR: const {},
        spDriftMv: null,
        stacks: 1,
        repeats: null,
        timestamp: DateTime.now(),
      ),
    ];
    await service.writeFile(temp, points);
    final readBack = await service.readFile(temp);
    expect(readBack.map((p) => p.direction).toList(),
        points.map((p) => p.direction).toList());
  });
}
