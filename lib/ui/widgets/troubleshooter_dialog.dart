import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/troubleshoot_ohmega.dart';

Future<void> showTroubleshooterDialog({
  required BuildContext context,
  required OhmegaIssue issue,
  required Future<void> Function(String note) onLogFixAttempt,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final noteController = TextEditingController();
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('${issue.code} — ${issue.title}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Likely cause:\n${issue.likely}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Recommended actions:',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ...issue.actions.map(
                    (action) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(action)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes about the fix (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Source: ${issue.source}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () async {
                  final timestamp =
                      DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
                  final note = noteController.text.trim();
                  final entry = note.isEmpty
                      ? '[$timestamp] Troubleshooter: ${issue.code} — ${issue.title}'
                      : '[$timestamp] Troubleshooter: ${issue.code} — $note';
                  await onLogFixAttempt(entry);
                  if (!dialogContext.mounted) {
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Fix attempt logged')),
                  );
                },
                child: const Text('Log Fix Attempt'),
              ),
            ],
          );
        },
      );
    },
  );
}
