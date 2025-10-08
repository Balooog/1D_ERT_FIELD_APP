import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/utils/format.dart';

void main() {
  test('formatCompactValue trims trailing zeros', () {
    expect(formatCompactValue(5), '5');
    expect(formatCompactValue(7.5), '7.5');
    expect(formatCompactValue(1.25), '1.25');
    expect(formatCompactValue(12.3333), '12.33');
  });

  test('formatOptionalCompact handles nulls', () {
    expect(formatOptionalCompact(null), isEmpty);
    expect(formatOptionalCompact(4.2), '4.2');
  });

  test('formatMetersTooltip returns two decimals', () {
    expect(formatMetersTooltip(1.234), '1.23');
    expect(formatMetersTooltip(5.0), '5.00');
  });
}
