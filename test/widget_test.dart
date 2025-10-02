import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ves_qc/main.dart';

void main() {
  testWidgets('smoke: app builds under ProviderScope', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: VesQcApp()));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
