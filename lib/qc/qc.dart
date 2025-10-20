import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/project_models.dart';
import '../state/project_controller.dart';

class QcState {
  const QcState({
    this.stats = const QcStats(),
    this.residuals = const [],
  });

  final QcStats stats;
  final List<ResidualPoint> residuals;

  QcState copyWith({QcStats? stats, List<ResidualPoint>? residuals}) {
    return QcState(
      stats: stats ?? this.stats,
      residuals: residuals ?? this.residuals,
    );
  }
}

class QcController extends StateNotifier<QcState> {
  QcController(this._ref) : super(const QcState());

  final Ref _ref;
  ProviderSubscription<ProjectState>? _subscription;

  void initialize() {
    _subscription = _ref.listen<ProjectState>(
      projectControllerProvider,
      (_, state) => _recompute(state),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _recompute(ProjectState projectState) {
    final project = projectState.project;
    final activeSite = projectState.activeSite;
    if (project == null || activeSite == null) {
      state = const QcState();
      return;
    }

    final readings = activeSite.readingsFor(projectState.activeDirection);
    final residuals = _buildResiduals(readings.points);
    final includedResiduals = residuals.where((e) => !e.excluded).toList();
    if (includedResiduals.isEmpty) {
      state = const QcState();
      return;
    }

    final rms = math.sqrt(includedResiduals
            .map((e) => math.pow(e.residualPercent, 2))
            .reduce((a, b) => a + b) /
        includedResiduals.length);

    final chi2 = includedResiduals
        .map((e) => math.pow(e.residualPercent / 5, 2))
        .reduce((a, b) => a + b)
        .toDouble();

    final stats = QcStats(
      rmsPercent: rms,
      chi2: chi2,
      green: includedResiduals.where((e) => e.color == QcColor.green).length,
      yellow: includedResiduals.where((e) => e.color == QcColor.yellow).length,
      red: includedResiduals.where((e) => e.color == QcColor.red).length,
    );

    state = QcState(stats: stats, residuals: residuals);
  }

  List<ResidualPoint> _buildResiduals(List<SpacingPoint> points) {
    if (points.isEmpty) return const [];
    final predicted = _rhoModel(points);
    final residuals = <ResidualPoint>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final rho = point.rho;
      final modelRho = predicted[i];
      if (rho == null || modelRho == null || modelRho == 0) {
        continue;
      }
      final residualPct = 100 * (rho - modelRho) / modelRho;
      final color = _classifyResidual(residualPct);
      residuals.add(ResidualPoint(
        spacing: point.spacingMeters,
        residualPercent: residualPct,
        color: color,
        excluded: point.excluded,
      ));
    }
    return residuals;
  }

  List<double?> _rhoModel(List<SpacingPoint> points) {
    final included = points
        .where((p) => p.rho != null && !p.excluded && p.spacingMeters > 0)
        .toList();
    if (included.isEmpty) {
      return List<double?>.filled(points.length, null);
    }
    if (included.length == 1) {
      final rho = included.first.rho!;
      return List<double?>.filled(points.length, rho);
    }

    double sumX = 0;
    double sumY = 0;
    double sumXX = 0;
    double sumXY = 0;
    for (final point in included) {
      final x = math.log(point.spacingMeters);
      final y = math.log(point.rho!.clamp(1e-9, double.infinity));
      sumX += x;
      sumY += y;
      sumXX += x * x;
      sumXY += x * y;
    }
    final n = included.length.toDouble();
    final denominator = (n * sumXX) - (sumX * sumX);
    final slope =
        denominator == 0 ? 0 : ((n * sumXY) - (sumX * sumY)) / denominator;
    final intercept = (sumY - slope * sumX) / n;

    return [
      for (final point in points)
        point.spacingMeters > 0
            ? math.exp(intercept + slope * math.log(point.spacingMeters))
            : null,
    ];
  }

  QcColor _classifyResidual(double residualPct) {
    final absValue = residualPct.abs();
    if (absValue < 5) {
      return QcColor.green;
    }
    if (absValue < 15) {
      return QcColor.yellow;
    }
    return QcColor.red;
  }
}

final qcControllerProvider =
    StateNotifierProvider<QcController, QcState>((ref) {
  final controller = QcController(ref);
  controller.initialize();
  return controller;
});
