import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:resicheck/main.dart';
import 'package:resicheck/services/storage_service.dart';

Future<void> pumpAppAndHydrate(
  WidgetTester tester, {
  ProjectStorageService? storage,
}) async {
  final projectStorage = storage ??
      ProjectStorageService(
        overrideRoot: Directory.systemTemp.createTempSync('resicheck_test'),
      );
  await tester.pumpWidget(
    ProviderScope(
      child: ResiCheckApp(storage: projectStorage),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  testWidgets('app hydrates and shows project list', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('resicheck_test_case');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final storage = ProjectStorageService(overrideRoot: tempDir);
    await pumpAppAndHydrate(tester, storage: storage);
    expect(find.text('ResiCheck Projects'), findsOneWidget);
  });
}
