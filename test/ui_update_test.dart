import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/ui/project_workflow/plots_panel.dart';

void main() {
  test('marking reading bad removes it from plot when outliers hidden', () {
    final site = SiteRecord(
      siteId: 'SiteA',
      displayName: 'Site A',
      spacings: [
        SpacingRecord(
          spacingFeet: 20,
          orientationA: DirectionReadingHistory(
            orientation: OrientationKind.a,
            label: 'N–S',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 100,
                isBad: true,
              ),
            ],
          ),
          orientationB: DirectionReadingHistory(
            orientation: OrientationKind.b,
            label: 'W–E',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 95,
                isBad: false,
              ),
            ],
          ),
        ),
      ],
    );
    final hidden = buildSeriesForSite(site, showOutliers: false);
    expect(hidden.aSeries, isEmpty);
    expect(hidden.bSeries.length, 1);
    final shown = buildSeriesForSite(site, showOutliers: true);
    expect(shown.aSeries.length, 1);
  });

  test('hide outliers keeps unflagged high resistance readings visible', () {
    final site = SiteRecord(
      siteId: 'SiteB',
      displayName: 'Site B',
      spacings: [
        SpacingRecord(
          spacingFeet: 10,
          orientationA: DirectionReadingHistory(
            orientation: OrientationKind.a,
            label: 'N–S',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 250000,
                isBad: false,
              ),
            ],
          ),
          orientationB: DirectionReadingHistory(
            orientation: OrientationKind.b,
            label: 'W–E',
            samples: [
              DirectionReadingSample(
                timestamp: DateTime.now(),
                resistanceOhm: 240000,
                isBad: false,
              ),
            ],
          ),
        ),
      ],
    );

    final hidden = buildSeriesForSite(site, showOutliers: false);
    expect(hidden.aSeries, isNotEmpty);
    expect(hidden.bSeries, isNotEmpty);
  });
}
