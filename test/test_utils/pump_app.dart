import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/main.dart';
import 'package:resicheck/services/storage_service.dart';

/// Boots the ResiCheck app inside a [WidgetTester] and waits until either the
/// main project list or the add-point action becomes visible. This avoids
/// relying on `pumpAndSettle`, which can hang when background timers remain
/// active during hydration.
Future<ProjectStorageService> pumpResiCheckApp(
  WidgetTester tester, {
  ProjectStorageService? storage,
  Duration settleTimeout = const Duration(seconds: 12),
  Duration pumpInterval = const Duration(milliseconds: 50),
}) async {
  Directory? tempDir;
  ProjectStorageService resolvedStorage;
  if (storage == null) {
    tempDir = Directory.systemTemp.createTempSync('resicheck_test_app');
    resolvedStorage = _TestProjectStorageService(tempDir);
  } else {
    resolvedStorage = storage;
  }

  if (tempDir != null) {
    final dir = tempDir;
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
  }

  await tester.pumpWidget(
    ProviderScope(
      child: ResiCheckApp(storage: resolvedStorage),
    ),
  );
  await tester.pump();
  await tester.pump(pumpInterval);

  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < settleTimeout) {
    if (tester.any(find.text('ResiCheck Projects')) ||
        tester.any(find.bySemanticsLabel('Add Point'))) {
      break;
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(pumpInterval);
    });
    await tester.pump();
  }

  final ready = tester.any(find.text('ResiCheck Projects')) ||
      tester.any(find.bySemanticsLabel('Add Point'));
  if (!ready) {
    debugDumpApp();
    fail(
      'ResiCheck UI did not reach the ready state within $settleTimeout.',
    );
  }

  return resolvedStorage;
}

class _TestProjectStorageService extends ProjectStorageService {
  _TestProjectStorageService(Directory overrideRoot)
      : super(overrideRoot: overrideRoot);

  @override
  Future<void> ensureSampleProject() async {
    // Skip disk-heavy sample seeding during widget tests; an empty root is fine.
  }
}
