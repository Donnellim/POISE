import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/feedback_preferences.dart';
import 'package:flutter_application_1/tabs/controls_tab.dart';
import 'package:flutter_application_1/database/local_database.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    await FeedbackPreferences.load();
  });

  tearDown(() {
    PoiseLocalDatabase.instance.mockRecordsForTesting = null;
  });

  testWidgets(
      'Routing operates independently, persists, and survives tab changes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final switches = find.descendant(
        of: find.byType(ControlsTab), matching: find.byType(Switch));

    // Initially: vibration is ON (switches.first), phoneNotification is OFF (switches.last)
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, false);

    // Turn ON phone notification -> Both should now be ON simultaneously
    ScaffoldMessenger.of(tester.element(find.byType(ControlsTab)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, true);

    // Turn OFF vibration -> Vibration is OFF, Phone Notification remains ON
    ScaffoldMessenger.of(tester.element(find.byType(ControlsTab)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, false);
    expect(tester.widget<Switch>(switches.last).value, true);

    // Turn OFF phone notification -> Both are now OFF simultaneously
    ScaffoldMessenger.of(tester.element(find.byType(ControlsTab)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, false);
    expect(tester.widget<Switch>(switches.last).value, false);

    // Navigate to Home tab and back to Controls -> Both remain OFF
    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, false);
    expect(tester.widget<Switch>(switches.last).value, false);

    // Verify independent preferences persistence across app reloads
    await tester.pumpWidget(const SizedBox());
    FeedbackPreferences.saveVibration(true);
    FeedbackPreferences.savePhoneNotification(true);
    await FeedbackPreferences.load();
    expect(FeedbackPreferences.vibration, true);
    expect(FeedbackPreferences.phoneNotification, true);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Phone notification toggle checks permission independently',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
        home: DashboardPage(initialNotificationPermissionGranted: false)));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final switches = find.descendant(
        of: find.byType(ControlsTab), matching: find.byType(Switch));

    // Initially: vibration is ON, phone notification is OFF
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, false);

    // Attempting to turn ON phone notification triggers permission dialog
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(find.text('Allow Notifications?'), findsOneWidget);

    // Denying keeps phone notification OFF without altering vibration
    await tester.tap(find.text("Don't Allow"));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, false);

    // Tap again and allow permission
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, true);
    expect(tester.widget<Switch>(switches.last).value, true);
    await tester.pumpWidget(const SizedBox());
  });
}
