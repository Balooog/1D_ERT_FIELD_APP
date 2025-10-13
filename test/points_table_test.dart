import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/ui/project_workflow/table_panel.dart';

void main() {
  group('TablePanel focus traversal', () {
    testWidgets('tab order follows N–S long→short then W–E short→long',
        (tester) async {
      final site = _buildSite();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ProviderScope(
              child: TablePanel(
                site: site,
                projectDefaultStacks: 4,
                showOutliers: true,
                onResistanceChanged: (_, __, ___, ____) {},
                onSdChanged: (_, __, ___) {},
                onInterpretationChanged: (_, __) {},
                onToggleBad: (_, __, ___) {},
                onMetadataChanged: ({
                  power,
                  stacks,
                  soil,
                  moisture,
                  groundTemperatureF,
                  location,
                  updateLocation,
                }) {},
                onShowHistory: (_, __) async {},
                onFocusChanged: (_, __) {},
              ),
            ),
          ),
        ),
      );

      final dynamic state = tester.state(find.byType(TablePanel));
      final List<FocusNode> order =
          List<FocusNode>.from(state.tabOrderForTest as List);
      final labels = order.map((node) => node.debugLabel ?? '').toList();

      expect(
        labels,
        equals([
          'a-resistance-40.0',
          'a-resistance-20.0',
          'a-resistance-10.0',
          'b-resistance-10.0',
          'b-resistance-20.0',
          'b-resistance-40.0',
        ]),
      );
    });
  });

  group('SD formatter', () {
    test('accepts 0–99.9 pattern', () {
      final regExp = RegExp(TablePanel.sdPromptPattern);
      final valid = ['0', '5', '12', '99', '7.5', '12.3', ''];
      for (final value in valid) {
        expect(regExp.hasMatch(value), isTrue,
            reason: 'expected "$value" to be allowed');
      }

      final invalid = ['100', '12.34', '123', '1.23', 'abc'];
      for (final value in invalid) {
        expect(regExp.hasMatch(value), isFalse,
            reason: 'expected "$value" to be rejected');
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
