import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:resicheck/main.dart';

void main() {
  testWidgets('ResiCheck boots and shows Add Point action', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ResiCheckApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Add Point'), findsOneWidget);
  });
}
