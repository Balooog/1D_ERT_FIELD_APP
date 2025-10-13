import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/services/location_service.dart';

void main() {
  group('LocationService', () {
    test('returns success when probe resolves', () async {
      final reading = LocationReading(latitude: 10, longitude: 20);
      final service = LocationService(
        probe: (_) async => reading,
      );

      final result = await service.tryGetCurrentLocation();

      expect(result.status, LocationStatus.success);
      expect(result.reading, equals(reading));
      expect(result.hasFix, isTrue);
    });

    test('maps LocationException from probe into failure result', () async {
      final service = LocationService(
        probe: (_) async {
          throw const LocationException(
            LocationStatus.permissionDenied,
            message: 'No permission',
          );
        },
      );

      final result = await service.tryGetCurrentLocation();

      expect(result.status, LocationStatus.permissionDenied);
      expect(result.reading, isNull);
      expect(result.message, 'No permission');
    });

    test('uses failure mapper for unexpected errors', () async {
      final service = LocationService(
        probe: (_) async {
          throw StateError('missing gps');
        },
        failureMapper: (error) {
          if (error is StateError) {
            return const LocationException(
              LocationStatus.unavailable,
              message: 'GPS adapter unavailable',
            );
          }
          return null;
        },
      );

      final result = await service.tryGetCurrentLocation();

      expect(result.status, LocationStatus.unavailable);
      expect(result.message, 'GPS adapter unavailable');
    });

    test('falls back to error status when mapper returns null', () async {
      final service = LocationService(
        probe: (_) async => throw ArgumentError('bad config'),
      );

      final result = await service.tryGetCurrentLocation();

      expect(result.status, LocationStatus.error);
      expect(result.reading, isNull);
      expect(result.message, 'Unexpected error while resolving location.');
    });

    test('treats timeout as timeout status', () async {
      final service = LocationService(
        probe: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return LocationReading(latitude: 0, longitude: 0);
        },
      );

      final result = await service.tryGetCurrentLocation(
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.status, LocationStatus.timeout);
      expect(result.message, isNull);
    });
  });
}
