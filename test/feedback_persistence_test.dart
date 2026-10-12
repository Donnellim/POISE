import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/feedback_preferences.dart';
import 'package:flutter_application_1/tabs/controls_tab.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FeedbackPreferences.load();
  });

  testWidgets('Routing stays exclusive, persists, and survives tab changes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    final switches = find.descendant(
        of: find.byType(ControlsTab), matching: find.byType(Switch));
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, false);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, false);
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.last).value, true);
    await tester.pumpWidget(const SizedBox());
    FeedbackPreferences.vibration = true;
    await FeedbackPreferences.load();
    expect(FeedbackPreferences.vibration, false);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, false);
    expect(tester.widget<Switch>(switches.last).value, true);
  });

  testWidgets('Turning vibration off cannot bypass denied phone permission',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DashboardPage(initialNotificationPermissionGranted: false)));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    final switches = find.descendant(
        of: find.byType(ControlsTab), matching: find.byType(Switch));
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    expect(find.text('Allow Notifications?'), findsOneWidget);
    await tester.tap(find.text("Don't Allow"));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, false);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, false);
    expect(tester.widget<Switch>(switches.last).value, true);
  });
}
