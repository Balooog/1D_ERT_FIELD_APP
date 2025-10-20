import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/project.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/ui/project_workflow/table_panel.dart';

void main() {
  testWidgets('table panel uses compact centered layout', (tester) async {
    final site = _buildSite();
    final project = ProjectRecord.newProject(
      projectId: 'compact-proj',
      projectName: 'Compact Project',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ProviderScope(
            child: TablePanel(
              project: project,
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
              onLogTroubleshooter: (_) async {},
            ),
          ),
        ),
      ),
    );

    final dataTable = tester.widget<DataTable>(find.byType(DataTable));
    expect(dataTable.headingRowHeight, 40);
    expect(dataTable.dataRowMinHeight, 40);
    expect(dataTable.dataRowMaxHeight, 44);
    expect(dataTable.columnSpacing, 12);

    final headers = dataTable.columns
        .map((column) => column.label)
        .whereType<SizedBox>()
        .map((box) => box.child)
        .whereType<Center>()
        .map((center) => center.child)
        .whereType<Text>()
        .map((text) => text.data)
        .toList();

    expect(
      headers,
      equals(['a-spacing (ft)', 'Pins at (ft)', 'Res N–S (Ω)', 'Res W–E (Ω)']),
    );

    expect(find.byType(TextField), findsNWidgets(site.spacings.length * 2));
    expect(find.textContaining('(auto)'), findsWidgets);
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
