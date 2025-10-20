import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:geolocator/geolocator.dart' as geolocator;

/// Identifies the overall outcome of a location lookup request.
enum LocationStatus {
  success,
  permissionDenied,
  permissionsUnknown,
  servicesDisabled,
  timeout,
  unavailable,
  error,
}

/// Lightweight reading captured from a location probe.
class LocationReading {
  LocationReading({
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.accuracyMeters,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? accuracyMeters;
  final DateTime timestamp;

  LocationReading copyWith({
    double? latitude,
    double? longitude,
    double? altitudeMeters,
    double? accuracyMeters,
    DateTime? timestamp,
  }) {
    return LocationReading(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Result type describing either a captured reading or the reason it failed.
class LocationResult {
  LocationResult._({
    required this.status,
    this.reading,
    this.message,
    this.exception,
  });

  factory LocationResult.success(LocationReading reading) {
    return LocationResult._(
      status: LocationStatus.success,
      reading: reading,
    );
  }

  factory LocationResult.failure(
    LocationStatus status, {
    String? message,
    Object? exception,
  }) {
    return LocationResult._(
      status: status,
      message: message,
      exception: exception,
    );
  }

  final LocationStatus status;
  final LocationReading? reading;
  final String? message;
  final Object? exception;

  bool get hasFix => status == LocationStatus.success && reading != null;
}

typedef LocationProbe = Future<LocationReading> Function(Duration timeout);
typedef LocationFailureMapper = LocationException? Function(Object error);

/// Tiny defensive wrapper so downstream consumers do not need to juggle
/// provider-specific exceptions or permissions edge cases.
class LocationService {
  LocationService({
    LocationProbe? probe,
    LocationFailureMapper? failureMapper,
    Duration defaultTimeout = const Duration(seconds: 8),
  })  : _probe = probe,
        _failureMapper = failureMapper,
        _defaultTimeout = defaultTimeout;

  final LocationProbe? _probe;
  final LocationFailureMapper? _failureMapper;
  final Duration _defaultTimeout;

  Future<LocationResult> tryGetCurrentLocation({Duration? timeout}) async {
    final probe = _probe;
    if (probe == null) {
      return LocationResult.failure(
        LocationStatus.unavailable,
        message: 'No location provider configured.',
      );
    }

    final effectiveTimeout = timeout ?? _defaultTimeout;

    try {
      final reading = await probe(effectiveTimeout).timeout(
        effectiveTimeout,
        onTimeout: () => throw const LocationException(LocationStatus.timeout),
      );
      return LocationResult.success(reading);
    } on LocationException catch (error) {
      return LocationResult.failure(
        error.status,
        message: error.message,
      );
    } on Object catch (error, stackTrace) {
      final mapped = _failureMapper?.call(error);
      if (mapped != null) {
        return LocationResult.failure(
          mapped.status,
          message: mapped.message,
          exception: error,
        );
      }
      debugPrint('LocationService: unexpected error: $error');
      debugPrint(stackTrace.toString());
      return LocationResult.failure(
        LocationStatus.error,
        message: 'Unexpected error while resolving location.',
        exception: error,
      );
    }
  }
}

class LocationException implements Exception {
  const LocationException(this.status, {this.message});

  final LocationStatus status;
  final String? message;

  @override
  String toString() {
    final label = status.name;
    if (message == null || message!.isEmpty) {
      return 'LocationException($label)';
    }
    return 'LocationException($label, $message)';
  }
}

LocationService geolocatorLocationService({
  Duration defaultTimeout = const Duration(seconds: 8),
  geolocator.LocationAccuracy accuracy = geolocator.LocationAccuracy.medium,
}) {
  Future<LocationReading> probe(Duration timeout) async {
    final serviceEnabled =
        await geolocator.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        LocationStatus.servicesDisabled,
        message: 'Location services appear disabled on this device.',
      );
    }

    var permission = await geolocator.Geolocator.checkPermission();
    if (permission == geolocator.LocationPermission.denied) {
      permission = await geolocator.Geolocator.requestPermission();
    }
    if (permission == geolocator.LocationPermission.denied ||
        permission == geolocator.LocationPermission.deniedForever) {
      throw const LocationException(
        LocationStatus.permissionDenied,
        message:
            'Location permission denied. Enable access in system settings.',
      );
    }
    if (permission == geolocator.LocationPermission.unableToDetermine) {
      throw const LocationException(
        LocationStatus.permissionsUnknown,
        message:
            'Unable to determine location permissions; manual entry required.',
      );
    }

    final position = await geolocator.Geolocator.getCurrentPosition(
      locationSettings: geolocator.LocationSettings(
        accuracy: accuracy,
        timeLimit: timeout,
      ),
    );

    final altitude = position.altitude.isFinite ? position.altitude : null;
    final accuracyMeters =
        position.accuracy.isFinite ? position.accuracy : null;
    final timestamp = position.timestamp;

    return LocationReading(
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeMeters: altitude,
      accuracyMeters: accuracyMeters,
      timestamp: timestamp,
    );
  }

  LocationException? mapper(Object error) {
    if (error is geolocator.LocationServiceDisabledException) {
      return const LocationException(
        LocationStatus.servicesDisabled,
        message:
            'Location services unavailable. Ensure GPS hardware is enabled.',
      );
    }
    if (error is geolocator.PermissionDefinitionsNotFoundException) {
      return const LocationException(
        LocationStatus.unavailable,
        message:
            'Location permission definitions missing. Verify platform configuration.',
      );
    }
    if (error is geolocator.PermissionDeniedException) {
      return const LocationException(
        LocationStatus.permissionDenied,
        message: 'Location permission denied by platform.',
      );
    }
    if (error is TimeoutException) {
      return const LocationException(
        LocationStatus.timeout,
        message: 'Timed out waiting for a GPS fix.',
      );
    }
    if (error is PlatformException) {
      final suffix = (error.message != null && error.message!.isNotEmpty)
          ? ': ${error.message}'
          : '';
      return LocationException(
        LocationStatus.unavailable,
        message: 'Location provider is not available (${error.code}$suffix).',
      );
    }
    if (error is UnimplementedError) {
      return const LocationException(
        LocationStatus.unavailable,
        message:
            'Location provider not implemented on this platform. For WSL, connect a compatible GPS.',
      );
    }
    return null;
  }

  return LocationService(
    probe: probe,
    failureMapper: mapper,
    defaultTimeout: defaultTimeout,
  );
}
