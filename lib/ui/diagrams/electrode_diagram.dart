import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ElectrodeDiagramPainter extends CustomPainter {
  ElectrodeDiagramPainter({
    required this.aFt,
    required this.pinInFt,
    required this.pinOutFt,
    this.stroke = 2.0,
  });

  final double aFt;
  final double pinInFt;
  final double pinOutFt;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final baselineY = height * 0.7;

    final maxAbs = [
      pinOutFt.abs(),
      pinInFt.abs(),
      aFt.abs(),
    ].reduce((a, b) => a > b ? a : b);
    final domain = (maxAbs <= 0 ? 1.0 : maxAbs) * 1.1;

    double x(double feet) {
      return ui.lerpDouble(
            0,
            width,
            (feet + domain) / (2 * domain),
          ) ??
          0;
    }

    final groundPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = stroke;
    final currentPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = stroke;

    canvas.drawLine(
        Offset(0, baselineY), Offset(width, baselineY), groundPaint);

    void drawPeg(double feet, {required Color color}) {
      final xp = x(feet);
      final pegPaint = Paint()
        ..color = color
        ..strokeWidth = stroke;
      const pegHeight = 16.0;
      canvas.drawLine(
        Offset(xp, baselineY - pegHeight),
        Offset(xp, baselineY + 10),
        pegPaint,
      );
      canvas.drawCircle(Offset(xp, baselineY - pegHeight), 4, pegPaint);
    }

    drawPeg(-pinOutFt, color: Colors.redAccent);
    drawPeg(-pinInFt, color: Colors.black87);
    drawPeg(pinInFt, color: Colors.black87);
    drawPeg(pinOutFt, color: Colors.redAccent);

    final loopY = baselineY - 28;
    final loopPath = Path()
      ..moveTo(x(-pinOutFt), loopY)
      ..lineTo(x(-pinInFt), loopY)
      ..lineTo(x(pinInFt), loopY)
      ..lineTo(x(pinOutFt), loopY);
    canvas.drawPath(loopPath, currentPaint);

    final labelPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    void drawLabel(String text, double feet) {
      labelPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.black87,
        ),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(
          x(feet) - labelPainter.width / 2,
          baselineY + 14,
        ),
      );
    }

    drawLabel('−${pinOutFt.toStringAsFixed(0)}', -pinOutFt);
    drawLabel('−${pinInFt.toStringAsFixed(0)}', -pinInFt);
    drawLabel(pinInFt.toStringAsFixed(0), pinInFt);
    drawLabel(pinOutFt.toStringAsFixed(0), pinOutFt);

    final titlePainter = TextPainter(
      text: TextSpan(
        text: 'Wenner, a = ${aFt.toStringAsFixed(2)} ft',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titlePainter.paint(canvas, const Offset(8, 8));
  }

  @override
  bool shouldRepaint(covariant ElectrodeDiagramPainter oldDelegate) {
    return oldDelegate.aFt != aFt ||
        oldDelegate.pinInFt != pinInFt ||
        oldDelegate.pinOutFt != pinOutFt ||
        oldDelegate.stroke != stroke;
  }
}
