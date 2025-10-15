import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/ui/project_workflow/table_panel.dart';

import 'util/screenshot.dart';

Future<void> _pumpTablePanel(
  WidgetTester tester,
  double width, {
  GlobalKey? boundaryKey,
}) async {
  final view = tester.view;
  final originalPhysicalSize = view.physicalSize;
  final originalDevicePixelRatio = view.devicePixelRatio;
  view.devicePixelRatio = originalDevicePixelRatio;
  view.physicalSize = Size(
    width * originalDevicePixelRatio,
    900 * originalDevicePixelRatio,
  );
  addTearDown(() {
    view.physicalSize = originalPhysicalSize;
    view.devicePixelRatio = originalDevicePixelRatio;
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: boundaryKey == null
              ? const TablePanelDebugFixture()
              : RepaintBoundary(
                  key: boundaryKey,
                  child: const TablePanelDebugFixture(),
                ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull);
}

Iterable<Rect> _headerRects(WidgetTester tester) sync* {
  for (var col = 1; col <= 4; col++) {
    yield tester.getRect(find.byKey(ValueKey('hdr_c$col')));
  }
}

Iterable<Rect> _bodyRowRects(WidgetTester tester, int rowIndex) sync* {
  for (var col = 1; col <= 4; col++) {
    yield tester.getRect(find.byKey(ValueKey('row${rowIndex}_c$col')));
  }
}

void _expectHeaderAlignment(WidgetTester tester, int bodyRowIndex) {
  final header = _headerRects(tester).toList();
  final bodyRow = _bodyRowRects(tester, bodyRowIndex).toList();

  for (var i = 0; i < 4; i++) {
    expect(
      (header[i].left - bodyRow[i].left).abs(),
      lessThan(0.51),
      reason: 'Header column ${i + 1} should line up with body',
    );
    expect(
      (header[i].right - bodyRow[i].right).abs(),
      lessThan(0.51),
      reason: 'Header width for column ${i + 1} should match body',
    );
  }

  expect(
    header.first.bottom <= bodyRow.first.top - 2,
    isTrue,
    reason: 'Body rows should not overlap the header',
  );
}

void _expectNoHorizontalOverlap(List<Rect> rects) {
  for (var i = 0; i < rects.length - 1; i++) {
    expect(
      rects[i].right <= rects[i + 1].left + 0.5,
      isTrue,
      reason: 'Column ${i + 1} should not overlap column ${i + 2}',
    );
  }
}

void main() {
  final wideWidths = [1366.0, 1250.0, 1024.0];

  testWidgets('TablePanel 4-column grid stays aligned on wide widths',
      (tester) async {
    for (final width in wideWidths) {
      await _pumpTablePanel(tester, width);
      final rowRects = _bodyRowRects(tester, 0).toList();
      _expectHeaderAlignment(tester, 0);
      _expectNoHorizontalOverlap(rowRects);
      expect(
        (rowRects[2].top - rowRects[3].top).abs(),
        lessThan(0.51),
        reason: 'Res columns should share the same top alignment',
      );
      expect(
        (rowRects[2].bottom - rowRects[3].bottom).abs(),
        lessThan(0.51),
        reason: 'Res columns should share the same bottom alignment',
      );
    }
  });

  testWidgets('TablePanel splits rows cleanly below desktop breakpoint',
      (tester) async {
    await _pumpTablePanel(tester, 900);

    final rowRects = _bodyRowRects(tester, 0).toList();
    _expectHeaderAlignment(tester, 0);

    expect(
      (rowRects[0].top - rowRects[1].top).abs(),
      lessThan(0.51),
      reason: 'Columns 1 and 2 should share a row in compact mode',
    );
    expect(
      rowRects[0].bottom + 4 <= rowRects[3].top,
      isTrue,
      reason: 'Second line should render beneath the first without overlap',
    );
    _expectNoHorizontalOverlap(rowRects.sublist(0, 2).toList());
    _expectNoHorizontalOverlap([
      rowRects[2],
      rowRects[3],
    ]);
  });

  testWidgets('Inline SD disclosure keeps column height stable on desktop',
      (tester) async {
    await _pumpTablePanel(tester, 1366);

    final before = tester.getRect(find.byKey(const ValueKey('row0_c3'))).height;

    await tester.tap(find.byKey(const ValueKey('row0_c3_sd_icon')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    final after = tester.getRect(find.byKey(const ValueKey('row0_c3'))).height;

    expect(
      (after - before).abs(),
      lessThan(0.51),
      reason: 'Row height should remain stable when SD dialog is shown',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Flag toggle keeps layout stable on desktop', (tester) async {
    await _pumpTablePanel(tester, 1366);

    final before = tester.getRect(find.byKey(const ValueKey('row0_c3'))).height;

    await tester.tap(find.byKey(const ValueKey('row0_c3_flag_icon')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    final after = tester.getRect(find.byKey(const ValueKey('row0_c3'))).height;

    expect(
      (after - before).abs(),
      lessThan(0.51),
      reason: 'Flag toggling should not alter column height',
    );
  });

  testWidgets('History button opens overlay', (tester) async {
    await _pumpTablePanel(tester, 1366);

    await tester.tap(find.byKey(const ValueKey('row0_c3_history_icon')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('SD chip opens popover on narrow layout', (tester) async {
    await _pumpTablePanel(tester, 900);

    await tester.tap(find.byKey(const ValueKey('row0_c3_menu')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit SD'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('TablePanel screenshot captures configured widths',
      (tester) async {
    final captureTargets = <double, String>{
      1366.0: 'table_panel_wide.png',
      1250.0: 'table_panel_1250.png',
      1024.0: 'table_panel_1024.png',
      900.0: 'table_panel_900.png',
    };

    for (final entry in captureTargets.entries) {
      final width = entry.key;
      final fileName = entry.value;
      final boundaryKey = GlobalKey();
      await _pumpTablePanel(
        tester,
        width,
        boundaryKey: boundaryKey,
      );
      await TestScreenshot.capture(
        tester,
        find.byKey(boundaryKey),
        fileName,
      );
    }
  });
}
