import 'package:flutter/material.dart';

import '../layout/sizing.dart';

const bool kShowLayoutGuides = false;

class BaselineOverlay extends StatelessWidget {
  const BaselineOverlay({
    super.key,
    this.lines = const <double>[0, kRowH],
  });

  final List<double> lines;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _BaselinePainter(lines),
      ),
    );
  }
}

class _BaselinePainter extends CustomPainter {
  _BaselinePainter(this.lines);

  final List<double> lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x66FF00FF)
      ..strokeWidth = 1;
    for (final y in lines) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_BaselinePainter oldDelegate) =>
      oldDelegate.lines != lines;
}
