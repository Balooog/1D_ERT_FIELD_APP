import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/ui/project_workflow/table_panel.dart';

import 'util/screenshot.dart';

void main() {
  testWidgets('TablePanel builds in narrow width without overflow',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: TablePanelDebugFixture(),
        ),
      ),
    ));

    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
  });

  testWidgets('TablePanel wide layout capture helper', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1280,
          child: RepaintBoundary(
            key: boundaryKey,
            child: const TablePanelDebugFixture(),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    await TestScreenshot.capture(
      tester,
      find.byKey(boundaryKey),
      'table_panel_wide.png',
    );
  });
}
