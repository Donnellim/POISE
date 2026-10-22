import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/feedback_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/tabs/controls_tab.dart';
import 'package:flutter_application_1/tabs/profile_tab.dart';

import 'package:flutter_application_1/database/local_database.dart';

void main() {
  setUp(() async {
    FeedbackPreferences.vibration = true;
    FeedbackPreferences.phoneNotification = false;
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
    await PoiseBleService.instance.connect(const PoiseDiscoveredDevice(
        id: 'SIMULATED-TEST', name: 'POISE', rssi: -50));
  });

  tearDown(() {
    PoiseLocalDatabase.instance.mockRecordsForTesting = null;
  });

  testWidgets(
      'Default states: Vibration is ON, Phone Notification is OFF in Controls; Notifications permission is ON in Profile',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // ── Navigate to Controls Tab (index 2) ──
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final controlsSwitches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );
    expect(controlsSwitches, findsNWidgets(2));

    // First switch is Vibration on Device (default ON)
    expect(tester.widget<Switch>(controlsSwitches.first).value, isTrue);
    // Second switch is Phone Notification (default OFF / silent)
    expect(tester.widget<Switch>(controlsSwitches.last).value, isFalse);

    // ── Navigate to Profile Tab (index 3) ──
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final profileSwitches = find.descendant(
      of: find.byType(ProfileTab),
      matching: find.byType(Switch),
    );
    expect(profileSwitches, findsNWidgets(2));
    // First is Bluetooth (default ON)
    expect(tester.widget<Switch>(profileSwitches.first).value, isTrue);
    // Second is Notifications system permission (default ON)
    expect(tester.widget<Switch>(profileSwitches.last).value, isTrue);
  });

  testWidgets(
      'Turning OFF Vibration in Controls turns Vibration OFF without forcing Phone Notification ON',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Navigate to Controls Tab
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final switches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );

    expect(tester.widget<Switch>(switches.first).value, isTrue);
    expect(tester.widget<Switch>(switches.last).value, isFalse);

    // Tap Vibration switch to turn it OFF
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    // Vibration is now OFF, and Phone Notification remains OFF (both OFF)
    expect(tester.widget<Switch>(switches.first).value, isFalse);
    expect(tester.widget<Switch>(switches.last).value, isFalse);
    expect(
      find.text('Device vibration feedback disabled.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Turning ON Phone Notification while Vibration is ON enables both simultaneously',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Navigate to Controls Tab
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final switches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );

    // Initial: Vibration ON, Phone Notification OFF
    expect(tester.widget<Switch>(switches.first).value, isTrue);
    expect(tester.widget<Switch>(switches.last).value, isFalse);

    // Tap Phone Notification switch to turn it ON
    await tester.tap(switches.last);
    await tester.pumpAndSettle();

    // Both Vibration AND Phone Notification are ON simultaneously
    expect(tester.widget<Switch>(switches.first).value, isTrue);
    expect(tester.widget<Switch>(switches.last).value, isTrue);
    expect(
      find.text('Phone notification feedback enabled.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Both feedback routing methods can be turned OFF and ON independently',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Navigate to Controls Tab
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final switches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );

    // 1. Turn Vibration OFF -> Both are OFF
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, isFalse);
    expect(tester.widget<Switch>(switches.last).value, isFalse);

    // 2. Turn Phone Notification ON -> Phone ON, Vibration OFF
    ScaffoldMessenger.of(tester.element(find.byType(ControlsTab)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, isFalse);
    expect(tester.widget<Switch>(switches.last).value, isTrue);

    // 3. Turn Vibration ON -> Both are ON
    ScaffoldMessenger.of(tester.element(find.byType(ControlsTab)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, isTrue);
    expect(tester.widget<Switch>(switches.last).value, isTrue);

    // 4. Turn Phone Notification OFF -> Vibration ON, Phone OFF
    ScaffoldMessenger.of(tester.element(find.byType(ControlsTab)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(switches.last);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, isTrue);
    expect(tester.widget<Switch>(switches.last).value, isFalse);
  });

  testWidgets(
      'Disabling Notifications permission in Profile disables Phone Notification',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // First go to Controls and set Phone Notification ON
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final controlsSwitches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );
    await tester.tap(controlsSwitches.last); // Phone ON
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(controlsSwitches.last).value, isTrue);

    // Go to Profile Tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final profileSwitches = find.descendant(
      of: find.byType(ProfileTab),
      matching: find.byType(Switch),
    );
    // Turn Notifications permission OFF
    await tester.tap(profileSwitches.last);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(profileSwitches.last).value, isFalse);

    // Check Controls Tab: Phone Notification must now be OFF
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(controlsSwitches.last).value, isFalse);
  });

  testWidgets(
      'When permission is disabled in Profile, attempting to enable Phone Notification in Controls prompts permission dialog',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Go to Profile and turn Notifications permission OFF
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final profileSwitches = find.descendant(
      of: find.byType(ProfileTab),
      matching: find.byType(Switch),
    );
    await tester.tap(profileSwitches.last);
    await tester.pumpAndSettle();

    // Go to Controls Tab
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final controlsSwitches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(controlsSwitches.last).value, isFalse);

    // Try turning Phone Notification ON
    await tester.tap(controlsSwitches.last);
    await tester.pumpAndSettle();

    // Dialog appears!
    expect(find.text('Allow Notifications?'), findsOneWidget);
    expect(
      find.text(
        'Phone notifications require notification permission on your device to alert you when posture thresholds are exceeded.',
      ),
      findsOneWidget,
    );

    // Tap "Don't Allow"
    await tester.tap(find.text("Don't Allow"));
    await tester.pumpAndSettle();

    // Dialog dismissed and Phone Notification remains OFF
    expect(find.text('Allow Notifications?'), findsNothing);
    expect(tester.widget<Switch>(controlsSwitches.last).value, isFalse);

    // Try turning Phone Notification ON again
    await tester.tap(controlsSwitches.last);
    await tester.pumpAndSettle();
    expect(find.text('Allow Notifications?'), findsOneWidget);

    // Tap "Allow"
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    // Dialog dismissed, Phone Notification is now ON
    expect(find.text('Allow Notifications?'), findsNothing);
    expect(tester.widget<Switch>(controlsSwitches.last).value, isTrue);
    expect(
      find.text(
          'Notification permission granted. Phone notifications enabled.'),
      findsOneWidget,
    );

    // Let the snackbar dismiss
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Go back to Profile Tab and check that Notifications permission is now ON!
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final updatedProfileSwitches = find.descendant(
      of: find.byType(ProfileTab),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(updatedProfileSwitches.last).value, isTrue);
  });

  testWidgets(
      'Switches in Controls and Profile tabs have consistent circle sizing and matching configurations',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Controls Tab
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final controlsSwitches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );
    expect(controlsSwitches, findsNWidgets(2));

    for (int i = 0; i < 2; i++) {
      final s = tester.widget<Switch>(controlsSwitches.at(i));
      expect(s.activeThumbColor, Colors.white);
      expect(s.inactiveThumbColor, Colors.white);
      expect(s.activeTrackColor, const Color(0xFF388AF6));
      expect(s.inactiveTrackColor, const Color(0xFF1E1E1E));
    }

    // Profile Tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final profileSwitches = find.descendant(
      of: find.byType(ProfileTab),
      matching: find.byType(Switch),
    );
    expect(profileSwitches, findsNWidgets(2));

    for (int i = 0; i < 2; i++) {
      final s = tester.widget<Switch>(profileSwitches.at(i));
      expect(s.activeThumbColor, Colors.white);
      expect(s.inactiveThumbColor, Colors.white);
      expect(s.activeTrackColor, const Color(0xFF388AF6));
      expect(s.inactiveTrackColor, const Color(0xFF1E1E1E));
    }
  });
}
