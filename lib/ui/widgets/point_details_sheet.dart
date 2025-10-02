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
    final diffPercent = point.resistanceDiffPercent;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A-Spacing: ${point.aFeet.toStringAsFixed(2)} ft (${point.aMeters.toStringAsFixed(2)} m)',
          ),
          Text('Resistance R: ${point.resistanceOhm.toStringAsFixed(2)} Ω'),
          if (point.resistanceStdOhm != null)
            Text('StdDev σR: ${point.resistanceStdOhm!.toStringAsFixed(2)} Ω'),
          Text('ρa: ${point.rhoAppOhmM.toStringAsFixed(2)} Ω·m'),
          if (point.sigmaRhoApp != null)
            Text('σρ: ${point.sigmaRhoApp!.toStringAsFixed(2)} Ω·m'),
          Text('Direction: ${point.direction.label}'),
          if (point.voltageV != null)
            Text('Voltage: ${point.voltageV!.toStringAsFixed(3)} V'),
          if (point.currentA != null)
            Text('Current: ${point.currentA!.toStringAsFixed(3)} A'),
          if (point.rFromVi != null)
            Text('R (V/I): ${point.rFromVi!.toStringAsFixed(2)} Ω'),
          if (diffPercent != null)
            Row(
              children: [
                Icon(
                  point.hasResistanceQaWarning ? Icons.warning_amber_rounded : Icons.info_outline,
                  color: point.hasResistanceQaWarning
                      ? Colors.orange
                      : Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text('ΔR vs V/I: ${diffPercent.toStringAsFixed(1)}%'),
              ],
            ),
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
