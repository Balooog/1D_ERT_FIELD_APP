import 'package:flutter/material.dart';

import '../../services/troubleshoot_ohmega.dart';
import 'troubleshooter_dialog.dart';

Future<void> showTroubleshooterBanner({
  required BuildContext context,
  required OhmegaIssue issue,
  required Future<void> Function(String note) onLogFixAttempt,
}) async {
  Color bannerColor;
  switch (issue.code) {
    case 'CURRENT ERROR':
    case 'GAIN ERROR':
      bannerColor = Colors.redAccent;
      break;
    case 'BATTERY LOW':
      bannerColor = Colors.amber;
      break;
    default:
      bannerColor = Colors.orange;
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentMaterialBanner();

  final banner = MaterialBanner(
    backgroundColor: bannerColor.withValues(alpha: 0.12),
    content: Text('${issue.code}: ${issue.title} — ${issue.likely}'),
    leading: Icon(Icons.construction, color: bannerColor),
    actions: [
      TextButton(
        onPressed: () async {
          messenger.hideCurrentMaterialBanner();
          await showTroubleshooterDialog(
            context: context,
            issue: issue,
            onLogFixAttempt: onLogFixAttempt,
          );
        },
        child: const Text('View fixes'),
      ),
      TextButton(
        onPressed: messenger.hideCurrentMaterialBanner,
        child: const Text('Dismiss'),
      ),
    ],
  );

  messenger.showMaterialBanner(banner);
}
