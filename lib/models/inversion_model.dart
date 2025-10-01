import 'package:flutter/foundation.dart';

@immutable
class Layer {
  const Layer({required this.thicknessM, required this.rhoOhmM});

  final double? thicknessM;
  final double rhoOhmM;

  Layer copyWith({double? thicknessM, double? rhoOhmM}) {
    return Layer(
      thicknessM: thicknessM ?? this.thicknessM,
      rhoOhmM: rhoOhmM ?? this.rhoOhmM,
    );
  }

  Map<String, dynamic> toJson() => {
        'thicknessM': thicknessM,
        'rhoOhmM': rhoOhmM,
      };

  factory Layer.fromJson(Map<String, dynamic> json) => Layer(
        thicknessM: (json['thicknessM'] as num?)?.toDouble(),
        rhoOhmM: (json['rhoOhmM'] as num).toDouble(),
      );
}

@immutable
class InversionModel {
  const InversionModel({
    required this.layers,
    required this.rmsPct,
    required this.chiSq,
    required this.predictedRho,
    required this.oneSigmaBand,
  });

  final List<Layer> layers;
  final double rmsPct;
  final double chiSq;
  final List<double> predictedRho;
  final List<double> oneSigmaBand;

  Map<String, dynamic> toJson() => {
        'layers': layers.map((l) => l.toJson()).toList(),
        'rmsPct': rmsPct,
        'chiSq': chiSq,
        'predictedRho': predictedRho,
        'oneSigmaBand': oneSigmaBand,
      };

  factory InversionModel.fromJson(Map<String, dynamic> json) => InversionModel(
        layers:
            (json['layers'] as List).map((e) => Layer.fromJson(e as Map<String, dynamic>)).toList(),
        rmsPct: (json['rmsPct'] as num).toDouble(),
        chiSq: (json['chiSq'] as num).toDouble(),
        predictedRho:
            (json['predictedRho'] as List).map((e) => (e as num).toDouble()).toList(),
        oneSigmaBand:
            (json['oneSigmaBand'] as List).map((e) => (e as num).toDouble()).toList(),
      );

  static const empty = InversionModel(
    layers: [],
    rmsPct: 0,
    chiSq: 0,
    predictedRho: [],
    oneSigmaBand: [],
  );
}
