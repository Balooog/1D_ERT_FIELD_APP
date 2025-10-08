import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/direction_reading.dart';
import '../lib/models/site.dart';
import '../lib/ui/project_workflow/table_panel.dart';

void main() {
  testWidgets('table panel uses compact centered layout', (tester) async {
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

    final dataTable = tester.widget<DataTable>(find.byType(DataTable));
    expect(dataTable.headingRowHeight, 40);
    expect(dataTable.dataRowMinHeight, 40);
    expect(dataTable.dataRowMaxHeight, 44);
    expect(dataTable.columnSpacing, 16);

    for (final column in dataTable.columns) {
      expect(column.label, isA<Center>());
    }

    for (final row in dataTable.rows) {
      for (final cell in row.cells) {
        expect(cell.child, isA<Align>());
        final align = cell.child as Align;
        expect(align.alignment, Alignment.center);
      }
    }
  });
}

SiteRecord _buildSite() {
  DirectionReadingHistory history(OrientationKind orientation) {
    return DirectionReadingHistory(
      orientation: orientation,
      label: orientation == OrientationKind.a ? 'N–S' : 'W–E',
      samples: [
        DirectionReadingSample(
          timestamp: DateTime(2024, 1, 1),
          resistanceOhm: 10,
          standardDeviationPercent: 3,
        ),
      ],
    );
  }

  SpacingRecord record(double spacing) {
    return SpacingRecord(
      spacingFeet: spacing,
      orientationA: history(OrientationKind.a),
      orientationB: history(OrientationKind.b),
    );
  }

  return SiteRecord(
    siteId: 'compact-site',
    displayName: 'Compact Site',
    spacings: [record(10), record(20)],
  );
}
