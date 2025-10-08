import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/direction_reading.dart';
import '../lib/models/site.dart';
import '../lib/ui/project_workflow/depth_profile_tab.dart';

void main() {
  testWidgets('depth cue table clamps to 160px with scroll', (tester) async {
    final site = _buildSite();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: DepthProfileTab(site: site),
        ),
      ),
    );

    expect(find.byType(DataTable), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 160,
      ),
      findsOneWidget,
    );
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.textContaining('Depth cue:'), findsOneWidget);
    expect(find.text('ρa (Ω·m)'), findsOneWidget);
  });
}

SiteRecord _buildSite() {
  DirectionReadingHistory history(OrientationKind orientation, double resistance) {
    return DirectionReadingHistory(
      orientation: orientation,
      label: orientation == OrientationKind.a ? 'N–S' : 'W–E',
      samples: [
        DirectionReadingSample(
          timestamp: DateTime(2024, 1, 1),
          resistanceOhm: resistance,
          standardDeviationPercent: 2,
        ),
      ],
    );
  }

  final spacings = <SpacingRecord>[];
  for (var i = 0; i < 10; i++) {
    final spacing = 5.0 + i * 5.0;
    spacings.add(
      SpacingRecord(
        spacingFeet: spacing,
        orientationA: history(OrientationKind.a, 10 + i.toDouble()),
        orientationB: history(OrientationKind.b, 12 + i.toDouble()),
      ),
    );
  }

  return SiteRecord(
    siteId: 'depth-site',
    displayName: 'Depth Site',
    spacings: spacings,
  );
}
