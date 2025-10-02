import 'dart:async';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/enums.dart';
import '../models/spacing_point.dart';
import 'geometry_factors.dart';

class SimulationOptions {
  const SimulationOptions({
    this.interval = const Duration(seconds: 1),
    this.arrayType = ArrayType.wenner,
    this.startSpacing = 1,
    this.spacingMultiplier = 1.2,
    this.current = 0.5,
    this.baseRho = 50,
  });

  final Duration interval;
  final ArrayType arrayType;
  final double startSpacing;
  final double spacingMultiplier;
  final double current;
  final double baseRho;
}

typedef SimulationListener = void Function(SpacingPoint point);

class MockStreamService {
  MockStreamService();

  Timer? _timer;
  double _spacing = 0;
  final _uuid = const Uuid();

  void start(SimulationOptions options, SimulationListener listener) {
    stop();
    _spacing = options.startSpacing;
    final rng = math.Random();
    _timer = Timer.periodic(options.interval, (timer) {
      final perturb = 1 + (rng.nextDouble() - 0.5) * 0.1;
      final rhoTrue = options.baseRho * (1 + 0.2 * math.sin(_spacing / 5));
      final k = geometryFactor(
        array: options.arrayType == ArrayType.wenner
            ? GeometryArray.wenner
            : GeometryArray.schlumberger,
        spacing: _spacing,
        mn: options.arrayType == ArrayType.schlumberger ? _spacing / 3 : null,
      );
      final rhoApp = rhoTrue * perturb;
      final voltage = rhoApp * options.current / k;
      final contactR = {
        'c1': 200 + rng.nextDouble() * 100,
        'c2': 200 + rng.nextDouble() * 150,
        'p1': 300 + rng.nextDouble() * 200,
        'p2': 300 + rng.nextDouble() * 200,
      };
      if (rng.nextDouble() < 0.05) {
        contactR['p1'] = 6000 + rng.nextDouble() * 2000;
      }
      final spDrift = rng.nextDouble() < 0.1 ? (rng.nextDouble() * 12 - 6) : (rng.nextDouble() * 2 - 1);
      final sigma = rhoApp * (0.02 + rng.nextDouble() * 0.03);
      final repeats = List.generate(
        3,
        (_) => rhoApp + rng.nextGaussian() * sigma,
      );
      final resistance = voltage / options.current;
      final sigmaR = sigma / (2 * math.pi * _spacing);
      final point = SpacingPoint(
        id: _uuid.v4(),
        arrayType: options.arrayType,
        aFeet: metersToFeet(_spacing),
        spacingMetric: _spacing,
        resistanceOhm: resistance,
        resistanceStdOhm: sigmaR,
        direction: SoundingDirection.other,
        voltageV: voltage,
        currentA: options.current,
        contactR: contactR,
        spDriftMv: spDrift,
        stacks: 3,
        repeats: repeats,
        rhoApp: rhoApp,
        sigmaRhoApp: sigma,
        timestamp: DateTime.now(),
      );
      listener(point);
      _spacing *= options.spacingMultiplier;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

extension _RandomGaussian on math.Random {
  double nextGaussian() {
    final u1 = nextDouble().clamp(1e-10, 1.0);
    final u2 = nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
