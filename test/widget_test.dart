import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils/pump_app.dart';

void main() {
  testWidgets('ResiCheck boots and shows projects dashboard', (tester) async {
    await pumpResiCheckApp(tester);
    await tester.pump();
    expect(find.text('ResiCheck Projects'), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
