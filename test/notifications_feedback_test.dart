import 'package:flutter/material.dart';
import 'package:flutter_application_1/feedback_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/tabs/controls_tab.dart';
import 'package:flutter_application_1/tabs/profile_tab.dart';

void main() {
  setUp(() => FeedbackPreferences.vibration = true);
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
      'Turning OFF Vibration in Controls automatically turns ON Phone Notification',
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

    // Vibration is now OFF, and Phone Notification automatically turned ON
    expect(tester.widget<Switch>(switches.first).value, isFalse);
    expect(tester.widget<Switch>(switches.last).value, isTrue);
    expect(
      find.text(
        'Device vibration turned off. Phone notification enabled to maintain posture feedback.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Turning OFF Phone Notification while Vibration is OFF automatically turns Vibration ON',
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

    // Turn Vibration OFF (Phone Notification turns ON)
    await tester.tap(switches.first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switches.first).value, isFalse);
    expect(tester.widget<Switch>(switches.last).value, isTrue);

    // Now attempt to turn Phone Notification OFF
    await tester.tap(switches.last);
    await tester.pumpAndSettle();

    // Phone Notification turned OFF, and Vibration automatically turned back ON
    expect(tester.widget<Switch>(switches.first).value, isTrue);
    expect(tester.widget<Switch>(switches.last).value, isFalse);
    expect(
      find.text(
        'Phone notification turned off. Device vibration enabled to maintain posture feedback.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Selecting phone notifications switches vibration off, and vice versa',
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

    // Turn Phone Notification ON while Vibration is already ON
    await tester.tap(switches.last);
    await tester.pumpAndSettle();

    // Only phone notifications are ON
    expect(tester.widget<Switch>(switches.first).value, isFalse);
    expect(tester.widget<Switch>(switches.last).value, isTrue);

    // Turn Phone Notification OFF while Vibration is ON (Vibration stays ON)
    await tester.tap(switches.last);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switches.first).value, isTrue);
    expect(tester.widget<Switch>(switches.last).value, isFalse);
  });

  testWidgets(
      'Disabling Notifications permission in Profile disables Phone Notification and forces Vibration ON',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // First go to Controls and set Phone Notification ON, Vibration OFF
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final controlsSwitches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );
    await tester.tap(controlsSwitches.first); // Vibration OFF -> Phone ON
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(controlsSwitches.first).value, isFalse);
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
    expect(
      find.text(
        'Notification permission disabled. Device vibration enabled for feedback.',
      ),
      findsOneWidget,
    );

    // Check Controls Tab: Phone Notification must now be OFF, Vibration ON
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(controlsSwitches.first).value, isTrue);
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

    // Go back to Profile Tab and check that Notifications permission is now ON!
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(profileSwitches.last).value, isTrue);
  });

  testWidgets(
      'Switches in Controls and Profile tabs have consistent circle sizing and matching configurations',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Controls Tab switches
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    final controlsSwitches = find.descendant(
      of: find.byType(ControlsTab),
      matching: find.byType(Switch),
    );
    for (final element in controlsSwitches.evaluate()) {
      final widget = element.widget as Switch;
      expect(widget.thumbIcon, isNotNull);
      expect(widget.activeTrackColor, const Color(0xFF388AF6));
      expect(widget.inactiveTrackColor, const Color(0xFF1E1E1E));
      expect(widget.activeThumbColor, Colors.white);
      expect(widget.inactiveThumbColor, Colors.white);
    }

    // Profile Tab switches
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final profileSwitches = find.descendant(
      of: find.byType(ProfileTab),
      matching: find.byType(Switch),
    );
    for (final element in profileSwitches.evaluate()) {
      final widget = element.widget as Switch;
      expect(widget.thumbIcon, isNotNull);
      expect(widget.activeTrackColor, const Color(0xFF388AF6));
      expect(widget.inactiveTrackColor, const Color(0xFF1E1E1E));
      expect(widget.activeThumbColor, Colors.white);
      expect(widget.inactiveThumbColor, Colors.white);
    }

    // Compare rendered sizes between controls and profile switches
    final profileSwitchSize = tester.getSize(profileSwitches.first);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    final controlsSwitchSize = tester.getSize(controlsSwitches.first);

    expect(controlsSwitchSize, equals(profileSwitchSize));
  });
}
