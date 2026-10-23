import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/tabs/profile_tab.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
    await PoiseBleService.instance.connect(const PoiseDiscoveredDevice(
        id: 'SIMULATED-TEST', name: 'POISE', rssi: -50));
  });
  tearDown(() {
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = false;
  });
  testWidgets(
      'ProfileTab renders all cards, permissions toggles, and action buttons',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Navigate to Profile Tab (index 3)
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('User 1'), findsOneWidget);
    expect(find.text('user1@gmail.com'), findsOneWidget);
    expect(find.text('Manage Account'), findsOneWidget);
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.textContaining('Version 1.0.0'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.text('Delete Account'), findsOneWidget);
    expect(find.text('Delete All Data'), findsOneWidget);

    // Toggle Bluetooth permission switch
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));
    await tester.tap(switches.first);
    await tester.pump();

    // Verify no exceptions
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Turning off Bluetooth in Profile disconnects POISE device on Dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Go to Profile Tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Turn Bluetooth OFF
    final switches = find.byType(Switch);
    expect(tester.widget<Switch>(switches.first).value, isTrue);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switches.first).value, isFalse);
    expect(find.text('Bluetooth turned off. P.O.I.S.E. device disconnected.'),
        findsOneWidget);

    // Go to Dashboard Tab
    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();

    // Verify POISE device is disconnected on Dashboard
    expect(find.text('Not Connected'), findsOneWidget);
    expect(find.text('--°'), findsOneWidget);
    expect(find.text('--:--:--'), findsOneWidget);
  });

  testWidgets(
      'Disconnecting device on Dashboard reflects as turned off in Profile tab',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));

    // Disconnect device on Dashboard
    await tester.tap(find.text('Device Connected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect Device'));
    await tester.pumpAndSettle();

    expect(find.text('Not Connected'), findsOneWidget);

    // Go to Profile Tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Bluetooth switch must be OFF
    final switches = find.byType(Switch);
    expect(tester.widget<Switch>(switches.first).value, isFalse);
  });

  testWidgets(
      'Reconnecting Bluetooth in Profile searches for device and resumes Dashboard without recalibration',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await PoiseBleService.instance.disconnect();
    await tester.pumpWidget(const MaterialApp(
      home: DashboardPage(
        initialBluetoothConnected: false,
        bluetoothSearchDuration: Duration(milliseconds: 100),
      ),
    ));

    // Go to Profile Tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    expect(tester.widget<Switch>(switches.first).value, isFalse);

    // Turn Bluetooth ON to reconnect
    await tester.tap(switches.first);
    await tester.pump();

    // Verify search overlay is active
    expect(find.text('Searching for P.O.I.S.E. Device'), findsOneWidget);
    expect(
        find.text(
            'Searching for POISE Device nearby...\nPlease ensure the device is powered on.'),
        findsOneWidget);

    // Advance search timer
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('Searching for P.O.I.S.E. Device'), findsNothing);
    expect(find.text('Set Your Neutral Posture'), findsNothing);

    // Active monitoring restored on Dashboard
    expect(find.text('Device Connected'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('PITCH ANGLE'), findsOneWidget);
    expect(find.text('Optimal Posture'), findsNothing);
  });

  testWidgets(
      'Canceling Bluetooth search in Profile preserves disconnected state',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await PoiseBleService.instance.disconnect();
    await tester.pumpWidget(const MaterialApp(
      home: DashboardPage(
        initialBluetoothConnected: false,
        bluetoothSearchDuration: Duration(seconds: 10),
      ),
    ));

    // Go to Profile Tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    final switches = find.byType(Switch);
    expect(tester.widget<Switch>(switches.first).value, isFalse);

    // Turn Bluetooth ON to reconnect
    await tester.tap(switches.first);
    await tester.pump();

    expect(find.text('Searching for P.O.I.S.E. Device'), findsOneWidget);

    // Cancel search
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Searching for P.O.I.S.E. Device'), findsNothing);
    expect(tester.widget<Switch>(switches.first).value, isFalse);

    // Go to Dashboard: still disconnected
    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    expect(find.text('Not Connected'), findsOneWidget);
  });

  testWidgets('Log Out overlay displays correctly and cancel dismisses it',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Scroll to and tap Log Out
    await tester.ensureVisible(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsOneWidget);
    expect(
        find.text('Are you sure you would like to log out?'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Log Out'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Cancel'), findsOneWidget);

    // Dismiss with Cancel
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsNothing);
  });

  testWidgets('Delete account overlay displays password input and cancel works',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Scroll to and tap Delete Account
    await tester.ensureVisible(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();

    expect(find.text('Delete account'), findsOneWidget);
    expect(
        find.text(
            'Are you sure you want to delete your account?\nThis action cannot be undone. Please enter your password to confirm.'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, ''), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Delete'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Cancel'), findsOneWidget);

    // Dismiss with Cancel
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete account'), findsNothing);
  });

  testWidgets('Delete all data overlay displays warning icon and cancel works',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Scroll to and tap Delete All Data
    await tester.ensureVisible(find.text('Delete All Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete All Data'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(find.text('Delete all data?'), findsOneWidget);
    expect(
        find.textContaining(
            'Are you sure you want to delete all'),
        findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Delete'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Cancel'), findsOneWidget);

    // Dismiss with Cancel
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete all data?'), findsNothing);
  });

  testWidgets(
      'Manage Account page allows editing profile and updates main profile view',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Tap Manage Account
    await tester.tap(find.text('Manage Account'));
    await tester.pumpAndSettle();

    expect(find.byType(ManageAccountPage), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Edit your photo'), findsOneWidget);
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Account Information'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    // Test password visibility toggle
    final eyeIcons = find.byIcon(Icons.visibility_off_outlined);
    expect(eyeIcons, findsNWidgets(3));
    await tester.tap(eyeIcons.first);
    await tester.pump();
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    // Edit Name
    final firstNameFinder = find.widgetWithText(TextField, 'User');
    await tester.enterText(firstNameFinder, 'Alex');
    await tester.pump();

    // Scroll to and tap Save Changes
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    // Returned to Profile Tab and name is updated!
    expect(find.byType(ManageAccountPage), findsNothing);
    expect(find.text('Alex 1'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(390, 844),
  ]) {
    testWidgets('Profile and Manage Account fit $size without overflow',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Open Manage Account
      await tester.tap(find.text('Manage Account'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
