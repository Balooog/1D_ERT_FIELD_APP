import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/spacing_point.dart';
import '../../state/providers.dart';

class PointDetailsSheet extends ConsumerWidget {
  const PointDetailsSheet({super.key, required this.point});

  final SpacingPoint point;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excluded = point.excluded;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spacing: ${point.spacingMetric.toStringAsFixed(2)} m'),
          Text('ρa: ${point.rhoApp.toStringAsFixed(2)} Ωm'),
          Text('Current: ${point.current.toStringAsFixed(2)} A'),
          Text('Voltage: ${point.vp.toStringAsFixed(3)} V'),
          Text('Stacks: ${point.stacks}'),
          Text('SP drift: ${point.spDriftMv?.toStringAsFixed(2) ?? '—'} mV'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Exclude from fit'),
              const Spacer(),
              Switch(
                value: excluded,
                onChanged: (value) {
                  ref.read(spacingPointsProvider.notifier).updatePoint(point.id, (current) =>
                      current.copyWith(excluded: value));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
