import 'package:flutter_test/flutter_test.dart';
import 'package:ves_qc/main.dart' as app;

void main() {
  testWidgets('ResiCheck boots and shows Add Point action', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.textContaining('Add Point'), findsOneWidget);
  });
}
