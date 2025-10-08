import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/direction_reading.dart';
import '../lib/models/project.dart';
import '../lib/models/site.dart';
import '../lib/ui/project_workflow/plots_panel.dart';

void main() {
  testWidgets('plots panel uses Okabe–Ito palette and markers', (tester) async {
    final project = _buildProject();
    final site = project.sites.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PlotsPanel(
            project: project,
            selectedSite: site,
            showOutliers: true,
            lockAxes: false,
            showAllSites: false,
          ),
        ),
      ),
    );

    final lineChart = tester.widget<LineChart>(find.byType(LineChart));
    final data = lineChart.data as LineChartData;
    expect(data.lineBarsData.length, greaterThanOrEqualTo(3));

    final northSeries = data.lineBarsData[0];
    final eastSeries = data.lineBarsData[1];
    final averageSeries = data.lineBarsData[2];

    expect(northSeries.color, const Color(0xFF0072B2));
    expect(eastSeries.color, const Color(0xFFD55E00));
    expect(averageSeries.color, const Color(0xFF595959));
    expect(averageSeries.dashArray, equals(const [6, 6]));

    final circlePainter = northSeries.dotData.getDotPainter!(
      northSeries.spots.first,
      0,
      northSeries,
      0,
    );
    final squarePainter = eastSeries.dotData.getDotPainter!(
      eastSeries.spots.first,
      0,
      eastSeries,
      0,
    );
    expect(circlePainter, isA<FlDotCirclePainter>());
    expect(squarePainter, isA<FlDotSquarePainter>());

    expect(find.text('N–S'), findsOneWidget);
    expect(find.text('W–E'), findsOneWidget);
    expect(find.text('Average'), findsOneWidget);
  });
}

ProjectRecord _buildProject() {
  DirectionReadingHistory history(String label, List<double> resistances) {
    return DirectionReadingHistory(
      orientation: label == 'N–S' ? OrientationKind.a : OrientationKind.b,
      label: label,
      samples: [
        for (final value in resistances)
          DirectionReadingSample(
            timestamp: DateTime(2024, 1, resistances.indexOf(value) + 1),
            resistanceOhm: value,
          ),
      ],
    );
  }

  SpacingRecord spacing(double feet, double base) {
    return SpacingRecord(
      spacingFeet: feet,
      orientationA: history('N–S', [base]),
      orientationB: history('W–E', [base * 1.2]),
    );
  }

  final site = SiteRecord(
    siteId: 'site-plot',
    displayName: 'Plot Site',
    spacings: [spacing(5, 10), spacing(10, 12), spacing(20, 16)],
  );

  return ProjectRecord(
    projectId: 'proj',
    projectName: 'Proj',
    arrayType: ArrayType.wenner,
    canonicalSpacingsFeet: const [5, 10, 20],
    defaultPowerMilliAmps: 0.5,
    defaultStacks: 4,
    sites: [site],
  );
}
