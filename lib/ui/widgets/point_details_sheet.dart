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
    final diffPercent = point.rhoDiffPercent;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A-Spacing: ${point.aFeet.toStringAsFixed(2)} ft (${point.aMeters.toStringAsFixed(2)} m)',
          ),
          Text('ρa: ${point.rhoAppOhmM.toStringAsFixed(2)} Ω·m'),
          if (point.sigmaRhoOhmM != null)
            Text('σρ: ${point.sigmaRhoOhmM!.toStringAsFixed(2)} Ω·m'),
          Text('R (derived): ${point.resistanceOhm.toStringAsFixed(2)} Ω'),
          if (point.resistanceStdOhm != null)
            Text(
                'σR (derived): ${point.resistanceStdOhm!.toStringAsFixed(2)} Ω'),
          Text('Direction: ${point.direction.label}'),
          if (point.voltageV != null)
            Text('Voltage: ${point.voltageV!.toStringAsFixed(3)} V'),
          if (point.currentA != null)
            Text('Current: ${point.currentA!.toStringAsFixed(3)} A'),
          if (point.notes != null && point.notes!.isNotEmpty)
            Text('Notes: ${point.notes}'),
          if (point.rhoFromVi != null)
            Text('ρ (from V/I): ${point.rhoFromVi!.toStringAsFixed(2)} Ω·m'),
          if (diffPercent != null)
            Row(
              children: [
                Icon(
                  point.hasRhoQaWarning
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline,
                  color: point.hasRhoQaWarning
                      ? Colors.orange
                      : Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text('Δρ vs V/I: ${diffPercent.toStringAsFixed(1)}%'),
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
                  ref.read(spacingPointsProvider.notifier).updatePoint(
                      point.id, (current) => current.copyWith(excluded: value));
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
