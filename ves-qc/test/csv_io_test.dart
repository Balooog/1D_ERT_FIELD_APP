import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/enums.dart';
import 'package:ves_qc/models/spacing_point.dart';
import 'package:ves_qc/services/csv_io.dart';

void main() {
  test('CSV roundtrip', () async {
    final service = CsvIoService();
    final temp = await File('${Directory.systemTemp.path}/ves_qc_test.csv').create(recursive: true);
    final points = [
      SpacingPoint(
        id: '1',
        arrayType: ArrayType.wenner,
        spacingMetric: 5,
        vp: 1,
        current: 0.5,
        contactR: const {},
        spDriftMv: null,
        stacks: 1,
        repeats: null,
        rhoApp: 100,
        sigmaRhoApp: 2,
        timestamp: DateTime.now(),
      ),
    ];
    await service.writeFile(temp, points);
    final readBack = await service.readFile(temp);
    expect(readBack, isNotEmpty);
    expect(readBack.first.rhoApp, points.first.rhoApp);
  });
}
