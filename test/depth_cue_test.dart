import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/calc.dart';
import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/ui/project_workflow/depth_profile_tab.dart';

void main() {
  testWidgets('depth table uses 0.5·a and averages valid resistivity', (tester) async {
    final site = _buildSite();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DepthProfileTab(site: site),
        ),
      ),
    );

    final tables = tester.widgetList<DataTable>(find.byType(DataTable)).toList();
    expect(tables, isNotEmpty);
    final dataTable = tables.first;
    expect(dataTable.rows, hasLength(3));

    final expectedRows = [
      _ExpectedRow(spacing: 10, resistances: [3, 4]),
      _ExpectedRow(spacing: 20, resistances: [5]),
      _ExpectedRow(spacing: 40, resistances: [8, 12]),
    ];

    for (var i = 0; i < expectedRows.length; i++) {
      final dataRow = dataTable.rows[i];
      final expected = expectedRows[i];
      final depthCell = dataRow.cells[0].child as Center;
      final depthText = (depthCell.child as Text).data;
      expect(depthText, _formatNumber(expected.spacing * 0.5));

      final rhoCell = dataRow.cells[1].child as Center;
      final rhoText = (rhoCell.child as Text).data;
      expect(rhoText, _formatNumber(expected.averageRho()));
    }
  });
}

class _ExpectedRow {
  _ExpectedRow({required this.spacing, required this.resistances});

  final double spacing;
  final List<double> resistances;

  double averageRho() {
    final averageResistance = resistances.reduce((a, b) => a + b) / resistances.length;
    return rhoAWenner(spacing, averageResistance);
  }
}

SiteRecord _buildSite() {
  DirectionReadingHistory history(
    OrientationKind orientation,
    List<double> resistances, {
    List<double> bad = const [],
  }) {
    return DirectionReadingHistory(
      orientation: orientation,
      label: orientation == OrientationKind.a ? 'N–S' : 'W–E',
      samples: [
        for (final value in resistances)
          DirectionReadingSample(
            timestamp: DateTime(2024, 1, value.toInt() + 1),
            resistanceOhm: value,
            standardDeviationPercent: 3,
          ),
        for (final value in bad)
          DirectionReadingSample(
            timestamp: DateTime(2024, 1, 20 + value.toInt()),
            resistanceOhm: value,
            standardDeviationPercent: 3,
            isBad: true,
          ),
      ],
    );
  }

  SpacingRecord record({required double spacing, required List<double> a, List<double> b = const [], List<double> badB = const []}) {
    return SpacingRecord(
      spacingFeet: spacing,
      orientationA: history(OrientationKind.a, a),
      orientationB: history(OrientationKind.b, b, bad: badB),
    );
  }

  return SiteRecord(
    siteId: 'site-depth',
    displayName: 'Depth Site',
    spacings: [
      record(spacing: 10, a: [3], b: [4]),
      record(spacing: 20, a: [5], b: const [], badB: [7]),
      record(spacing: 40, a: [8], b: [12]),
    ],
  );
}

String _formatNumber(double value) {
  var text = value.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
  }
  return text;
}
