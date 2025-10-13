import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/models/calc.dart';
import 'package:resicheck/models/site.dart';

void main() {
  test('tape helper values convert correctly for 2.5 ft spacing', () {
    final record = SpacingRecord.seed(spacingFeet: 2.5);
    expect(record.tapeInsideFeet, closeTo(1.25, 1e-9));
    expect(record.tapeOutsideFeet, closeTo(3.75, 1e-9));
    expect(record.tapeInsideMeters, closeTo(feetToMeters(1.25), 1e-9));
    expect(record.tapeOutsideMeters, closeTo(feetToMeters(3.75), 1e-9));
  });

  test('site location metadata persists via updateMetadata', () {
    final site = SiteRecord(siteId: 'ERT_001', displayName: 'ERT_001');
    final capturedAt = DateTime.utc(2024, 1, 15, 12, 30);
    final location = SiteLocation(
      latitude: 42.12345,
      longitude: -71.98765,
      accuracyMeters: 4.2,
      altitudeMeters: 12.0,
      capturedAt: capturedAt,
    );

    final updated = site.updateMetadata(
      location: location,
      updateLocation: true,
    );

    expect(updated.location, equals(location));

    final cleared = updated.updateMetadata(
      location: null,
      updateLocation: true,
    );

    expect(cleared.location, isNull);
  });

  test('site location round-trips to JSON', () {
    final location = SiteLocation(
      latitude: 35.0,
      longitude: -120.0,
      accuracyMeters: 3.5,
      altitudeMeters: 100.0,
      capturedAt: DateTime.utc(2024, 2, 20, 8, 45),
    );
    final site = SiteRecord(
      siteId: 'ERT_123',
      displayName: 'ERT 123',
      location: location,
    );

    final json = site.toJson();
    final roundTrip = SiteRecord.fromJson(json);

    expect(roundTrip.location, equals(location));
  });
}
