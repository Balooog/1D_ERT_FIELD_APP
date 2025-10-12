import 'package:flutter/material.dart';

import '../../../services/import/import_models.dart';

class ColumnMapRow extends StatelessWidget {
  const ColumnMapRow({
    super.key,
    required this.descriptor,
    required this.selected,
    required this.onChanged,
  });

  final ImportColumnDescriptor descriptor;
  final ImportColumnTarget? selected;
  final ValueChanged<ImportColumnTarget?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = descriptor.suggestedTarget;
    final isSuggested = suggestion != null && suggestion == selected;
    final samplePreview = descriptor.samples.take(3).join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Tooltip(
              message: descriptor.header,
              child: Text(
                descriptor.header,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: descriptor.samples.join('\n'),
              child: Text(
                samplePreview.isEmpty ? '—' : samplePreview,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<ImportColumnTarget?>(
              initialValue: selected,
              onChanged: onChanged,
              decoration: const InputDecoration(
                labelText: 'Map to',
              ),
              items: [
                const DropdownMenuItem<ImportColumnTarget?>(
                  value: null,
                  child: Text('Ignore'),
                ),
                ...ImportColumnTarget.values.map(
                  (target) => DropdownMenuItem<ImportColumnTarget?>(
                    value: target,
                    child: Text(target.label),
                  ),
                ),
              ],
            ),
          ),
          if (suggestion != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: Icon(
                isSuggested ? Icons.auto_awesome : Icons.lightbulb_outline,
                color: isSuggested
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}
