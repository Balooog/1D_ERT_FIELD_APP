import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ves_qc/main.dart';

void main() {
  testWidgets('ResiCheck boots and shows Add Point action', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ResiCheckApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add Point'), findsOneWidget);
  });
}
