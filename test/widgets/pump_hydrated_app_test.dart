import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/services/storage_service.dart';

import '../test_utils/pump_app.dart';

void main() {
  testWidgets('app hydrates and shows project list', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('resicheck_test_case');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final storage = ProjectStorageService(overrideRoot: tempDir);
    await pumpResiCheckApp(tester, storage: storage);
    expect(find.text('ResiCheck Projects'), findsOneWidget);
  });
}
