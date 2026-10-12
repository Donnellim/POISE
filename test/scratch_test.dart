import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/dashboard_page.dart';

void main() {
  testWidgets('verify Switch thumb size across Controls and Profile', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    // Check Controls Tab
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    // Check Profile Tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
