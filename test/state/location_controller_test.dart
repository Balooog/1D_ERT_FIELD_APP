import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/services/location_service.dart';
import 'package:resicheck/state/providers.dart';

void main() {
  group('LocationCaptureController', () {
    test('emits loading then stores latest result', () async {
      final reading = LocationReading(latitude: 42.0, longitude: -71.0);
      final container = ProviderContainer(overrides: [
        locationServiceProvider.overrideWithValue(
          LocationService(probe: (_) async => reading),
        ),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(locationCaptureProvider.notifier);
      final request = notifier.request(timeout: const Duration(seconds: 1));

      final loadingState = container.read(locationCaptureProvider);
      expect(loadingState.isLoading, isTrue);
      expect(loadingState.latest, isNull);

      final result = await request;
      final resolvedState = container.read(locationCaptureProvider);

      expect(result.status, LocationStatus.success);
      expect(resolvedState.isLoading, isFalse);
      expect(resolvedState.latest?.reading, equals(reading));
    });

    test('reset clears latest result', () async {
      final reading = LocationReading(latitude: 1, longitude: 2);
      final container = ProviderContainer(overrides: [
        locationServiceProvider.overrideWithValue(
          LocationService(probe: (_) async => reading),
        ),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(locationCaptureProvider.notifier);
      await notifier.request();
      notifier.reset();

      final state = container.read(locationCaptureProvider);
      expect(state.isLoading, isFalse);
      expect(state.latest, isNull);
    });
  });
}
