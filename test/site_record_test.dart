import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/calc.dart';
import 'package:ves_qc/models/site.dart';

void main() {
  test('tape helper values convert correctly for 2.5 ft spacing', () {
    final record = SpacingRecord.seed(spacingFeet: 2.5);
    expect(record.tapeInsideFeet, closeTo(1.25, 1e-9));
    expect(record.tapeOutsideFeet, closeTo(3.75, 1e-9));
    expect(record.tapeInsideMeters, closeTo(feetToMeters(1.25), 1e-9));
    expect(record.tapeOutsideMeters, closeTo(feetToMeters(3.75), 1e-9));
  });
}
