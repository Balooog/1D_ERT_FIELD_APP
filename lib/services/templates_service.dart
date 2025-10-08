import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/site.dart';

class GhostTemplatePoint {
  GhostTemplatePoint({
    required this.spacingFeet,
    required this.apparentResistivityOhmM,
  });

  factory GhostTemplatePoint.fromJson(Map<String, dynamic> json) {
    return GhostTemplatePoint(
      spacingFeet: (json['spacing_ft'] as num).toDouble(),
      apparentResistivityOhmM: (json['rho_ohm_m'] as num).toDouble(),
    );
  }

  final double spacingFeet;
  final double apparentResistivityOhmM;
}

class GhostTemplate {
  GhostTemplate({
    required this.id,
    required this.name,
    this.soil,
    this.moisture,
    required List<GhostTemplatePoint> points,
  }) : points = List.unmodifiable(points);

  factory GhostTemplate.fromJson(Map<String, dynamic> json) {
    return GhostTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      soil: (json['soil'] as String?) == null
          ? null
          : SoilType.values.byName(json['soil'] as String),
      moisture: (json['moisture'] as String?) == null
          ? null
          : MoistureLevel.values.byName(json['moisture'] as String),
      points: (json['points'] as List<dynamic>)
          .map((dynamic e) =>
              GhostTemplatePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final String name;
  final SoilType? soil;
  final MoistureLevel? moisture;
  final List<GhostTemplatePoint> points;

  bool matches({SoilType? soil, MoistureLevel? moisture}) {
    final soilMatches = this.soil == null || soil == null || this.soil == soil;
    final moistureMatches =
        this.moisture == null || moisture == null || this.moisture == moisture;
    return soilMatches && moistureMatches;
  }
}

class TemplatesService {
  TemplatesService({this.assetPath = 'assets/templates/ghost_curves.json'});

  final String assetPath;
  List<GhostTemplate>? _cache;

  Future<List<GhostTemplate>> loadTemplates() async {
    if (_cache != null) {
      return _cache!;
    }
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    _cache = decoded
        .map((dynamic item) => GhostTemplate.fromJson(item as Map<String, dynamic>))
        .toList();
    return _cache!;
  }
}
