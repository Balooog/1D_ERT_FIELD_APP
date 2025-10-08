import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/direction_reading.dart';
import '../lib/models/site.dart';
import '../lib/ui/project_workflow/table_panel.dart';

void main() {
  group('TablePanel focus traversal', () {
    testWidgets('tab order follows N–S long→short then W–E short→long', (tester) async {
      final site = _buildSite();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: TablePanel(
              site: site,
              projectDefaultStacks: 4,
              showOutliers: true,
              onResistanceChanged: (_, __, ___, ____) {},
              onSdChanged: (_, __, ___) {},
              onInterpretationChanged: (_, __) {},
              onToggleBad: (_, __, ___) {},
              onMetadataChanged: ({power, stacks, soil, moisture}) {},
              onShowHistory: (_, __) async {},
              onFocusChanged: (_, __) {},
            ),
          ),
        ),
      );

      final dynamic state = tester.state(find.byType(TablePanel));
      final Map<dynamic, dynamic> tabOrder = state._tabOrder as Map<dynamic, dynamic>;
      final startKey = tabOrder.keys.firstWhere(
        (dynamic key) =>
            key.orientation == OrientationKind.a &&
            key.type.toString().endsWith('resistance') &&
            (key.spacingFeet as double) == 40.0,
      );

      final ordered = <Map<String, dynamic>>[];
      dynamic current = startKey;
      while (current != null) {
        ordered.add({
          'orientation': current.orientation,
          'type': current.type.toString().split('.').last,
          'spacing': (current.spacingFeet as double).toStringAsFixed(1),
        });
        current = tabOrder[current];
      }

      expect(
        ordered.take(6).map((entry) => '${entry['orientation']}-${entry['type']}-${entry['spacing']}'),
        equals([
          'OrientationKind.a-resistance-40.0',
          'OrientationKind.a-sd-40.0',
          'OrientationKind.a-resistance-20.0',
          'OrientationKind.a-sd-20.0',
          'OrientationKind.a-resistance-10.0',
          'OrientationKind.a-sd-10.0',
        ]),
      );

      expect(
        ordered.skip(6).take(6).map((entry) => '${entry['orientation']}-${entry['type']}-${entry['spacing']}'),
        equals([
          'OrientationKind.b-resistance-10.0',
          'OrientationKind.b-sd-10.0',
          'OrientationKind.b-resistance-20.0',
          'OrientationKind.b-sd-20.0',
          'OrientationKind.b-resistance-40.0',
          'OrientationKind.b-sd-40.0',
        ]),
      );
    });
  });

  group('SD formatter', () {
    test('accepts 0–99.9 pattern', () {
      final regExp = RegExp(r'^[0-9]{0,2}(\.[0-9])?$');
      final valid = ['0', '5', '12', '99', '7.5', '12.3', ''];
      for (final value in valid) {
        expect(regExp.hasMatch(value), isTrue, reason: 'expected "$value" to be allowed');
      }

      final invalid = ['100', '12.34', '123', '1.23', 'abc'];
      for (final value in invalid) {
        expect(regExp.hasMatch(value), isFalse, reason: 'expected "$value" to be rejected');
      }
    });
  });
}

SiteRecord _buildSite() {
  DirectionReadingHistory readings(String label, List<double> resistances) {
    return DirectionReadingHistory(
      orientation: label == 'N–S' ? OrientationKind.a : OrientationKind.b,
      label: label,
      samples: [
        for (final value in resistances)
          DirectionReadingSample(
            timestamp: DateTime(2024, 1, value.toInt() + 1),
            resistanceOhm: value,
            standardDeviationPercent: 3,
          ),
      ],
    );
  }

  SpacingRecord spacing(double feet) {
    return SpacingRecord(
      spacingFeet: feet,
      orientationA: readings('N–S', [feet + 1]),
      orientationB: readings('W–E', [feet + 2]),
    );
  }

  return SiteRecord(
    siteId: 'site-1',
    displayName: 'Site 1',
    spacings: [spacing(10), spacing(20), spacing(40)],
  );
}
