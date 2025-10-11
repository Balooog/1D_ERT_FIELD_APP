import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/main.dart';

void main() {
  testWidgets('ResiCheck boots and shows Add Point action', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ResiCheckApp()));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    final addPointFinder = find.bySemanticsLabel('Add Point');
    expect(addPointFinder, findsOneWidget);
    expect(find.text('Add Point'), findsOneWidget);
    expect(find.text('Add Site'), findsOneWidget);
    expect(find.text('Sites'), findsWidgets);
  });
}
