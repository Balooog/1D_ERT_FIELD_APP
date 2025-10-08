import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/models/direction_reading.dart';
import 'package:ves_qc/models/enums.dart';
import 'package:ves_qc/models/project.dart';
import 'package:ves_qc/models/site.dart';
import 'package:ves_qc/services/templates_service.dart';
import 'package:ves_qc/ui/project_workflow/plots_panel.dart';

void main() {
  testWidgets('ghost and template series render in ascending spacing order', (tester) async {
    final spacing = SpacingRecord(
      spacingFeet: 10,
      orientationA: DirectionReadingHistory(
        orientation: OrientationKind.a,
        label: 'Dir A',
        samples: [
          DirectionReadingSample(
            timestamp: DateTime(2024, 1, 1),
            resistanceOhm: 45,
          ),
        ],
      ),
      orientationB: DirectionReadingHistory(
        orientation: OrientationKind.b,
        label: 'Dir B',
      ),
    );

    final site = SiteRecord(
      siteId: 'SITE-1',
      displayName: 'Site 1',
      spacings: [spacing],
    );

    final project = ProjectRecord(
      projectId: 'proj-1',
      projectName: 'Test Project',
      arrayType: ArrayType.wenner,
      canonicalSpacingsFeet: const [5, 10, 15],
      defaultPowerMilliAmps: 0.5,
      defaultStacks: 4,
      sites: [site],
    );

    final averageGhost = [
      GhostSeriesPoint(spacingFt: 30, rho: 100),
      GhostSeriesPoint(spacingFt: 10, rho: 200),
      GhostSeriesPoint(spacingFt: 20, rho: 150),
    ];

    final template = GhostTemplate(
      id: 'temp',
      name: 'Template',
      points: [
        GhostTemplatePoint(spacingFeet: 25, apparentResistivityOhmM: 80),
        GhostTemplatePoint(spacingFeet: 5, apparentResistivityOhmM: 120),
        GhostTemplatePoint(spacingFeet: 15, apparentResistivityOhmM: 90),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlotsPanel(
          project: project,
          selectedSite: site,
          showOutliers: true,
          lockAxes: false,
          showAllSites: false,
          template: template,
          averageGhost: averageGhost,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lineChart = tester.widget<LineChart>(find.byType(LineChart));
    final bars = lineChart.data.lineBarsData;

    final ghostBar = bars.firstWhere(
      (bar) =>
          bar.dashArray != null && bar.dashArray!.length == 2 && bar.dashArray!.first == 6,
    );
    final templateBar = bars.firstWhere(
      (bar) =>
          bar.dashArray != null && bar.dashArray!.length == 2 && bar.dashArray!.first == 4,
    );

    final ghostXs = ghostBar.spots.map((spot) => spot.x).toList();
    final sortedGhostXs = [...ghostXs]..sort();
    final templateXs = templateBar.spots.map((spot) => spot.x).toList();
    final sortedTemplateXs = [...templateXs]..sort();

    expect(ghostXs, equals(sortedGhostXs));
    expect(templateXs, equals(sortedTemplateXs));
    expect(ghostBar.spots.length, averageGhost.length);
    expect(templateBar.spots.length, template.points.length);
  });
}
