import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/project.dart';
import '../models/site.dart';
import '../services/inversion.dart';
import '../utils/distance_unit.dart';
import '../utils/units.dart' as units;

class InversionFigureRenderer {
  static Future<Uint8List> render({
    required ProjectRecord project,
    required SiteRecord site,
    required TwoLayerInversionResult result,
    required DistanceUnit distanceUnit,
    int width = 1600,
    int height = 900,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    _drawBackground(canvas, width, height);
    _drawTitles(canvas, width, height);

    final chartRect = ui.Rect.fromLTWH(
      110,
      120,
      width * 0.58,
      height * 0.6,
    );
    _drawMeasuredVsModeledChart(
      canvas: canvas,
      rect: chartRect,
      result: result,
    );

    final modelRect = ui.Rect.fromLTWH(
      chartRect.right + 120,
      chartRect.top,
      width * 0.16,
      chartRect.height,
    );
    _drawLayeredModel(
      canvas: canvas,
      rect: modelRect,
      result: result,
      distanceUnit: distanceUnit,
    );

    _drawFooter(
      canvas: canvas,
      width: width,
      height: height,
      project: project,
      site: site,
      result: result,
      distanceUnit: distanceUnit,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static void _drawBackground(ui.Canvas canvas, int width, int height) {
    final background = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      background,
    );
    final border = ui.Paint()
      ..color = const ui.Color(0xFFB0B0B0)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      ui.Rect.fromLTWH(20, 20, width - 40.0, height - 40.0),
      border,
    );
  }

  static void _drawTitles(ui.Canvas canvas, int width, int height) {
    _paintText(
      canvas,
      text: 'Measured and Modeled Data',
      at: ui.Offset(width * 0.35, 60),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
    );
    _paintText(
      canvas,
      text: 'Layered Resistivity Model',
      at: ui.Offset(width * 0.77, 60),
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static void _drawMeasuredVsModeledChart({
    required ui.Canvas canvas,
    required ui.Rect rect,
    required TwoLayerInversionResult result,
  }) {
    final spacingValues = result.spacingFeet
        .map((e) => e.toDouble())
        .where((value) => value.isFinite && value > 0)
        .toList();
    if (spacingValues.isEmpty) {
      spacingValues.addAll([1, 10]);
    }
    final rhoSamples = <double>[];
    for (final value in result.observedRho) {
      if (value.isFinite && value > 0) {
        rhoSamples.add(value.toDouble());
      }
    }
    for (final value in result.predictedRho) {
      if (value.isFinite && value > 0) {
        rhoSamples.add(value.toDouble());
      }
    }
    if (rhoSamples.isEmpty) {
      rhoSamples.addAll([10, 100]);
    }

    double minSpacing = spacingValues.reduce(math.min);
    double maxSpacing = spacingValues.reduce(math.max);
    if (minSpacing == maxSpacing) {
      minSpacing /= 2;
      maxSpacing *= 2;
    }
    final logXMin = (math.log(minSpacing) / math.ln10).floorToDouble();
    final logXMax = (math.log(maxSpacing) / math.ln10).ceilToDouble();

    double minRho = rhoSamples.reduce(math.min);
    double maxRho = rhoSamples.reduce(math.max);
    minRho = math.max(minRho * 0.8, 0.1);
    maxRho = math.max(maxRho * 1.2, minRho * 1.1);
    final logYMin = (math.log(minRho) / math.ln10).floorToDouble();
    final logYMax = (math.log(maxRho) / math.ln10).ceilToDouble();

    double mapX(double spacing) {
      final logValue = math.log(spacing) / math.ln10;
      return rect.left +
          ((logValue - logXMin) / (logXMax - logXMin)) * rect.width;
    }

    double mapY(double rho) {
      final logValue = math.log(rho) / math.ln10;
      return rect.bottom -
          ((logValue - logYMin) / (logYMax - logYMin)) * rect.height;
    }

    final axisPaint = ui.Paint()
      ..color = const ui.Color(0xFF707070)
      ..strokeWidth = 2;
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, axisPaint);
    canvas.drawLine(rect.bottomLeft, rect.topLeft, axisPaint);

    final gridPaint = ui.Paint()
      ..color = const ui.Color(0xFFE0E0E0)
      ..strokeWidth = 1;
    for (var power = logXMin; power <= logXMax; power += 1) {
      final spacing = math.pow(10, power).toDouble();
      final x = mapX(spacing);
      canvas.drawLine(
          ui.Offset(x, rect.top), ui.Offset(x, rect.bottom), gridPaint);
      _paintText(
        canvas,
        text: spacing.toStringAsFixed(0),
        at: ui.Offset(x - 16, rect.bottom + 12),
        style: const TextStyle(fontSize: 12),
      );
      for (var sub = 2; sub < 10; sub += 1) {
        final minor = spacing * sub;
        if (minor >= math.pow(10, power + 1)) continue;
        final mx = mapX(minor);
        canvas.drawLine(
          ui.Offset(mx, rect.top),
          ui.Offset(mx, rect.bottom),
          gridPaint..color = const ui.Color(0xFFF1F1F1),
        );
      }
      gridPaint.color = const ui.Color(0xFFE0E0E0);
    }
    for (var power = logYMin; power <= logYMax; power += 1) {
      final rho = math.pow(10, power).toDouble();
      final y = mapY(rho);
      canvas.drawLine(
          ui.Offset(rect.left, y), ui.Offset(rect.right, y), gridPaint);
      _paintText(
        canvas,
        text: rho >= 1000 ? rho.toStringAsFixed(0) : rho.toStringAsFixed(0),
        at: ui.Offset(rect.left - 62, y - 8),
        style: const TextStyle(fontSize: 12),
      );
      for (var sub = 2; sub < 10; sub += 1) {
        final minor = rho * sub;
        if (minor >= math.pow(10, power + 1)) continue;
        final my = mapY(minor);
        canvas.drawLine(
          ui.Offset(rect.left, my),
          ui.Offset(rect.right, my),
          gridPaint..color = const ui.Color(0xFFF4F4F4),
        );
      }
      gridPaint.color = const ui.Color(0xFFE0E0E0);
    }

    _paintText(
      canvas,
      text: 'Wenner Array, A-Spacing (ft)',
      at: ui.Offset(rect.left + rect.width * 0.32, rect.bottom + 42),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    );
    canvas.save();
    canvas.translate(rect.left - 90, rect.top + rect.height / 2);
    canvas.rotate(-math.pi / 2);
    _paintText(
      canvas,
      text: 'Apparent Resistivity (Ohm-m)',
      at: const ui.Offset(0, 0),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    );
    canvas.restore();

    final predictedPairs = <ui.Offset>[];
    for (var i = 0;
        i < result.predictedRho.length && i < result.spacingFeet.length;
        i++) {
      final spacing = result.spacingFeet[i].toDouble();
      final rho = result.predictedRho[i].toDouble();
      if (spacing <= 0 || rho <= 0) continue;
      predictedPairs.add(ui.Offset(mapX(spacing), mapY(rho)));
    }
    predictedPairs.sort((a, b) => a.dx.compareTo(b.dx));
    final predictedPaint = ui.Paint()
      ..color = const ui.Color(0xFFD6433A)
      ..strokeWidth = 3
      ..style = ui.PaintingStyle.stroke;
    if (predictedPairs.length >= 2) {
      final path = ui.Path()
        ..moveTo(predictedPairs.first.dx, predictedPairs.first.dy);
      for (var i = 1; i < predictedPairs.length; i++) {
        path.lineTo(predictedPairs[i].dx, predictedPairs[i].dy);
      }
      canvas.drawPath(path, predictedPaint);
    }

    final measuredPaint = ui.Paint()
      ..color = const ui.Color(0xFFD6433A)
      ..style = ui.PaintingStyle.fill;
    final measuredOutline = ui.Paint()
      ..color = const ui.Color(0xFF1A1A1A)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0;
        i < result.observedRho.length && i < result.spacingFeet.length;
        i++) {
      final spacing = result.spacingFeet[i].toDouble();
      final rho = result.observedRho[i].toDouble();
      if (spacing <= 0 || rho <= 0) continue;
      final center = ui.Offset(mapX(spacing), mapY(rho));
      canvas.drawCircle(center, 6, measuredPaint);
      canvas.drawCircle(center, 6, measuredOutline);
    }

    final transitionSpacing = math.pow(10, (logXMin + logXMax) / 2).toDouble();
    final stepPaint = ui.Paint()
      ..color = const ui.Color(0xFF1966C2)
      ..strokeWidth = 3
      ..style = ui.PaintingStyle.stroke;
    final rho1Y = mapY(result.rho1);
    final rho2Y = mapY(result.rho2);
    final path = ui.Path()
      ..moveTo(mapX(minSpacing), rho1Y)
      ..lineTo(mapX(transitionSpacing), rho1Y)
      ..lineTo(mapX(transitionSpacing), rho2Y)
      ..lineTo(mapX(maxSpacing), rho2Y);
    canvas.drawPath(path, stepPaint);
  }

  static void _drawLayeredModel({
    required ui.Canvas canvas,
    required ui.Rect rect,
    required TwoLayerInversionResult result,
    required DistanceUnit distanceUnit,
  }) {
    final totalDepthMeters = math.max(result.maxDepthMeters, 0.1);
    final totalDepth = distanceUnit == DistanceUnit.feet
        ? units.metersToFeet(totalDepthMeters)
        : totalDepthMeters;

    double mapDepth(double depthValue) {
      return rect.top + (depthValue / totalDepth) * rect.height;
    }

    final layers = <_LayerSpan>[];
    final firstThicknessMeters = result.thicknessM ??
        (result.layerDepths.isNotEmpty
            ? result.layerDepths.first
            : totalDepthMeters / 2);
    final firstThickness = distanceUnit == DistanceUnit.feet
        ? units.metersToFeet(firstThicknessMeters)
        : firstThicknessMeters;
    final firstEnd = math.min(firstThickness, totalDepth);
    layers.add(
      _LayerSpan(
        start: 0,
        end: firstEnd,
        resistivity: result.rho1,
      ),
    );

    final secondEnd = totalDepth;
    layers.add(
      _LayerSpan(
        start: firstEnd,
        end: secondEnd,
        resistivity: result.rho2,
      ),
    );

    if (result.halfSpaceRho != null) {
      layers.last = _LayerSpan(
        start: firstEnd,
        end: math.min(secondEnd, totalDepth),
        resistivity: result.rho2,
      );
      layers.add(
        _LayerSpan(
          start: math.min(secondEnd, totalDepth),
          end: totalDepth,
          resistivity: result.halfSpaceRho!,
        ),
      );
    }

    final framePaint = ui.Paint()
      ..color = const ui.Color(0xFF1A1A1A)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, framePaint);

    for (final layer in layers) {
      final top = mapDepth(layer.start);
      final bottom = mapDepth(layer.end);
      final color = layer.resistivity >= result.rho2
          ? const ui.Color(0xFFD64545)
          : const ui.Color(0xFF1966C2);
      final fill = ui.Paint()..color = color.withValues(alpha: 0.85);
      canvas.drawRect(
        ui.Rect.fromLTRB(rect.left + 12, top, rect.right - 40, bottom),
        fill,
      );
      canvas.drawRect(
        ui.Rect.fromLTRB(rect.left + 12, top, rect.right - 40, bottom),
        framePaint..strokeWidth = 1.2,
      );

      _paintText(
        canvas,
        text: _formatResistivityLabel(layer.resistivity),
        at: ui.Offset(rect.right - 30, (top + bottom) / 2 - 12),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );
    }

    _paintText(
      canvas,
      text: 'Depth (${distanceUnit == DistanceUnit.feet ? 'ft' : 'm'})',
      at: ui.Offset(rect.left + rect.width / 2 - 42, rect.bottom + 36),
      style: const TextStyle(fontSize: 14),
    );
    canvas.save();
    canvas.translate(rect.right + 44, rect.top + rect.height / 2);
    canvas.rotate(-math.pi / 2);
    _paintText(
      canvas,
      text: 'Ohm-m',
      at: const ui.Offset(0, 0),
      style: const TextStyle(fontSize: 14),
    );
    canvas.restore();

    _paintText(
      canvas,
      text: '0',
      at: ui.Offset(rect.left - 30, mapDepth(0) - 14),
      style: const TextStyle(fontSize: 12),
    );
    _paintText(
      canvas,
      text: totalDepth.toStringAsFixed(2),
      at: ui.Offset(rect.left - 60, mapDepth(totalDepth) - 10),
      style: const TextStyle(fontSize: 12),
    );
  }

  static void _drawFooter({
    required ui.Canvas canvas,
    required int width,
    required int height,
    required ProjectRecord project,
    required SiteRecord site,
    required TwoLayerInversionResult result,
    required DistanceUnit distanceUnit,
  }) {
    final rmsPercent = (result.rms * 100).toStringAsFixed(2);
    _paintText(
      canvas,
      text:
          'RMS = $rmsPercent %, Layers = ${result.halfSpaceRho != null ? 3 : 2}',
      at: ui.Offset(width * 0.32, height * 0.78),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: ui.Color(0xFF333333),
      ),
    );
    final siteLabel =
        site.displayName.isNotEmpty ? site.displayName : site.siteId;
    final subtitle =
        '${project.projectName} — $siteLabel (${distanceUnit == DistanceUnit.feet ? 'ft' : 'm'})';
    _paintText(
      canvas,
      text: subtitle,
      at: ui.Offset(width * 0.32, height * 0.82),
      style: const TextStyle(fontSize: 14, color: ui.Color(0xFF444444)),
    );
    _paintText(
      canvas,
      text: 'Generated by ResiCheck',
      at: ui.Offset(width - 250, height - 80),
      style: const TextStyle(fontSize: 12, color: ui.Color(0xFF777777)),
    );
  }

  static String _formatResistivityLabel(double rho) {
    if (rho >= 1000) {
      return '${rho.toStringAsFixed(0)} Ω·m';
    }
    if (rho >= 100) {
      return '${rho.toStringAsFixed(1)} Ω·m';
    }
    return '${rho.toStringAsFixed(2)} Ω·m';
  }

  static void _paintText(
    ui.Canvas canvas, {
    required String text,
    required ui.Offset at,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }
}

class _LayerSpan {
  _LayerSpan({
    required this.start,
    required this.end,
    required this.resistivity,
  });

  final double start;
  final double end;
  final double resistivity;
}
