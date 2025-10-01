import 'package:flutter/material.dart';

import '../../state/providers.dart';

class TelemetryPanel extends StatelessWidget {
  const TelemetryPanel({super.key, required this.state});

  final TelemetryState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Expanded(child: _TelemetryCard(title: 'Current (A)', samples: state.current)),
          const SizedBox(width: 8),
          Expanded(child: _TelemetryCard(title: 'Potential (V)', samples: state.voltage)),
          const SizedBox(width: 8),
          Expanded(child: _TelemetryCard(title: 'SP Drift (mV)', samples: state.spDrift)),
        ],
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({required this.title, required this.samples});

  final String title;
  final List<TelemetrySample> samples;

  @override
  Widget build(BuildContext context) {
    final latest = samples.isEmpty ? '—' : samples.last.value.toStringAsFixed(2);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(latest, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              height: 32,
              child: CustomPaint(
                painter: _SparklinePainter(samples.map((e) => e.value).toList()),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      final paint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
      return;
    }
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs() < 1e-6 ? 1.0 : (maxVal - minVal);
    final step = size.width / (values.length - 1).clamp(1, double.infinity);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = step * i;
      final normalized = (values[i] - minVal) / range;
      final y = size.height - normalized * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
