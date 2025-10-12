import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/inversion_model.dart';
import '../models/spacing_point.dart';
import '../services/inversion.dart';
import '../services/mock_stream.dart';
import '../services/qc_rules.dart';

final mockStreamProvider =
    Provider<MockStreamService>((ref) => MockStreamService());

class SpacingPointsNotifier extends StateNotifier<List<SpacingPoint>> {
  SpacingPointsNotifier() : super(const []);

  void setPoints(List<SpacingPoint> points) {
    state = List.unmodifiable(points);
  }

  void addPoint(SpacingPoint point) {
    state = [...state, point];
  }

  void updatePoint(String id, SpacingPoint Function(SpacingPoint) updater) {
    state = [
      for (final point in state)
        if (point.id == id) updater(point) else point,
    ];
  }

  void removePoint(String id) {
    state = [
      for (final point in state)
        if (point.id != id) point,
    ];
  }

  void clear() => state = const [];
}

final spacingPointsProvider =
    StateNotifierProvider<SpacingPointsNotifier, List<SpacingPoint>>(
        (ref) => SpacingPointsNotifier());

final inversionServiceProvider =
    Provider<LiteInversionService>((ref) => LiteInversionService());

final inversionProvider = Provider<InversionModel>((ref) {
  final points = ref.watch(spacingPointsProvider);
  if (points.isEmpty) return InversionModel.empty;
  final model = ref.read(inversionServiceProvider).invert(points);
  return model;
});

final qaSummaryProvider = Provider<QaSummary>((ref) {
  final points = ref.watch(spacingPointsProvider);
  final inversion = ref.watch(inversionProvider);
  if (points.isEmpty || inversion.predictedRho.isEmpty) {
    return const QaSummary(
      green: 0,
      yellow: 0,
      red: 0,
      rms: 0,
      chiSq: 0,
      lastSpDrift: null,
      worstContact: null,
    );
  }
  final residuals = <double>[];
  for (var i = 0; i < points.length; i++) {
    final fit = i < inversion.predictedRho.length
        ? inversion.predictedRho[i]
        : inversion.predictedRho.last;
    residuals.add(
        points[i].rhoAppOhmM == 0 ? 0 : (points[i].rhoAppOhmM - fit) / fit);
  }
  return summarizeQa(points, residuals, inversion.predictedRho);
});

class TelemetrySample {
  TelemetrySample(this.timestamp, this.value);
  final DateTime timestamp;
  final double value;
}

class TelemetryState {
  TelemetryState({
    required this.current,
    required this.voltage,
    required this.spDrift,
  });

  final List<TelemetrySample> current;
  final List<TelemetrySample> voltage;
  final List<TelemetrySample> spDrift;
}

class TelemetryNotifier extends StateNotifier<TelemetryState> {
  TelemetryNotifier()
      : super(TelemetryState(current: [], voltage: [], spDrift: []));

  void addSample(
      {required double current, required double voltage, double? spDrift}) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 30));

    List<TelemetrySample> updateList(
        List<TelemetrySample> samples, double value) {
      final updated = [...samples, TelemetrySample(now, value)]
        ..removeWhere((sample) => sample.timestamp.isBefore(cutoff));
      return updated;
    }

    List<TelemetrySample> trimOnly(List<TelemetrySample> samples) {
      return [...samples]
        ..removeWhere((sample) => sample.timestamp.isBefore(cutoff));
    }

    state = TelemetryState(
      current: updateList(state.current, current),
      voltage: updateList(state.voltage, voltage),
      spDrift: spDrift != null
          ? updateList(state.spDrift, spDrift)
          : trimOnly(state.spDrift),
    );
  }
}

final telemetryProvider =
    StateNotifierProvider<TelemetryNotifier, TelemetryState>((ref) {
  return TelemetryNotifier();
});

class SimulationController extends StateNotifier<bool> {
  SimulationController(this.ref) : super(false);

  final Ref ref;

  void toggle() {
    if (state) {
      stop();
    } else {
      start();
    }
  }

  void start() {
    if (state) return;
    final stream = ref.read(mockStreamProvider);
    const options = SimulationOptions();
    stream.start(options, (point) {
      ref.read(spacingPointsProvider.notifier).addPoint(point);
      ref.read(telemetryProvider.notifier).addSample(
            current: point.current,
            voltage: point.vp,
            spDrift: point.spDriftMv,
          );
    });
    state = true;
  }

  void stop() {
    if (!state) return;
    final stream = ref.read(mockStreamProvider);
    stream.stop();
    state = false;
  }
}

final simulationControllerProvider =
    StateNotifierProvider<SimulationController, bool>((ref) {
  final controller = SimulationController(ref);
  ref.onDispose(() => controller.stop());
  return controller;
});
