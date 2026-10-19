import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/activity_mode.dart';
import 'package:flutter_application_1/mode_preferences.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/database/local_database.dart';
import 'package:flutter_application_1/feedback_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.simulateForTesting = true;
    PoiseBleService.instance.resetForTesting();
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    await FeedbackPreferences.load();
    await ModePreferences.load();
  });

  tearDown(() async {
    await PoiseBleService.instance.disconnect();
    PoiseBleService.instance.resetForTesting();
    PoiseLocalDatabase.instance.mockRecordsForTesting = null;
  });

  group('P.O.I.S.E. Rev 9 Mode Sync & Persistence Specifications', () {
    test('1. Phone mode preference defaults to Normal on first launch',
        () async {
      SharedPreferences.setMockInitialValues({});
      final initialMode = await ModePreferences.load();
      expect(initialMode, ActivityMode.normal);
      expect(ModePreferences.savedMode, ActivityMode.normal);
    });

    test('2. Phone mode preference persists across app restarts', () async {
      SharedPreferences.setMockInitialValues({});
      await ModePreferences.saveMode(ActivityMode.commuting);

      // Simulate app kill & relaunch with persisted SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('poise.mode'), 4);

      final reloadedMode = await ModePreferences.load();
      expect(reloadedMode, ActivityMode.commuting);
      expect(ModePreferences.savedMode, ActivityMode.commuting);
    });

    test(
        '3. Saved mode preference is sent to FFE2 automatically after connection and service discovery',
        () async {
      await ModePreferences.saveMode(ActivityMode.commuting);

      final connected = await PoiseBleService.instance.connect(
        const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: 'P.O.I.S.E.',
          rssi: -55,
        ),
      );

      expect(connected, true);
      expect(PoiseBleService.instance.isConnected, true);
      expect(PoiseBleService.instance.lastSentModeCommand, 'MODE:4');
      expect(PoiseBleService.instance.hardwareActiveMode, ActivityMode.commuting);
      expect(PoiseBleService.instance.isModeSynchronized, true);
    });

    test(
        '4. Disconnection retains the phone saved mode preference and does not overwrite it with Normal',
        () async {
      await ModePreferences.saveMode(ActivityMode.commuting);
      await PoiseBleService.instance.connect(
        const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: 'P.O.I.S.E.',
          rssi: -55,
        ),
      );

      expect(PoiseBleService.instance.isModeSynchronized, true);

      // Disconnect
      await PoiseBleService.instance.disconnect();

      // Rev 9 firmware switches hardware to Normal on disconnect
      expect(PoiseBleService.instance.isConnected, false);
      expect(PoiseBleService.instance.hardwareActiveMode, ActivityMode.normal);
      expect(PoiseBleService.instance.isModeSynchronized, false);

      // Phone saved preference MUST remain Commuting!
      expect(PoiseBleService.instance.phoneSavedMode, ActivityMode.commuting);
      expect(ModePreferences.savedMode, ActivityMode.commuting);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('poise.mode'), 4);
    });

    test('5. Reconnecting automatically resends the phone saved mode preference',
        () async {
      // 1. Initial connection with Commuting
      await ModePreferences.saveMode(ActivityMode.commuting);
      await PoiseBleService.instance.connect(
        const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: 'P.O.I.S.E.',
          rssi: -55,
        ),
      );
      expect(PoiseBleService.instance.lastSentModeCommand, 'MODE:4');

      // 2. Disconnect
      await PoiseBleService.instance.disconnect();
      expect(PoiseBleService.instance.isConnected, false);

      // 3. Reconnect
      final reconnected = await PoiseBleService.instance.connect(
        const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: 'P.O.I.S.E.',
          rssi: -55,
        ),
      );

      expect(reconnected, true);
      // Automatically resent Commuting without requiring user reselection!
      expect(PoiseBleService.instance.lastSentModeCommand, 'MODE:4');
      expect(PoiseBleService.instance.hardwareActiveMode, ActivityMode.commuting);
      expect(PoiseBleService.instance.isModeSynchronized, true);
    });

    test(
        '6. Changing mode while connected updates the hardware immediately via FFE2 and saves the preference on the phone',
        () async {
      await PoiseBleService.instance.connect(
        const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: 'P.O.I.S.E.',
          rssi: -55,
        ),
      );

      // Change mode to Leisure (MODE:3)
      final success =
          await PoiseBleService.instance.sendModeCommand(ActivityMode.leisure);
      expect(success, true);
      expect(PoiseBleService.instance.lastSentModeCommand, 'MODE:3');
      expect(PoiseBleService.instance.phoneSavedMode, ActivityMode.leisure);
      expect(PoiseBleService.instance.hardwareActiveMode, ActivityMode.leisure);
      expect(PoiseBleService.instance.isModeSynchronized, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('poise.mode'), 3);
    });

    testWidgets(
        '7. Active monitoring session continues uninterrupted when changing mode while connected',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await PoiseBleService.instance.connect(
        const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: 'P.O.I.S.E.',
          rssi: -55,
        ),
      );

      await tester.pumpWidget(const MaterialApp(
        home: DashboardPage(initialBluetoothConnected: true),
      ));
      await tester.pumpAndSettle();

      // Ensure session is actively running
      if (find.text('Start Session').evaluate().isNotEmpty) {
        await tester.tap(find.text('Start Session'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
      }
      expect(find.text('End Session'), findsOneWidget);

      // Dismiss any overlaying SnackBar before navigating
      ScaffoldMessenger.of(tester.element(find.byType(DashboardPage)))
          .clearSnackBars();
      await tester.pumpAndSettle();

      // Navigate to Controls Tab
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      // Change Mode to Focus (MODE:2)
      await tester.tap(find.text('Focus'));
      await tester.pumpAndSettle();

      expect(PoiseBleService.instance.lastSentModeCommand, 'MODE:2');
      expect(PoiseBleService.instance.hardwareActiveMode, ActivityMode.focus);

      // Return to Dashboard/Home Tab
      await tester.tap(find.byIcon(Icons.home_filled));
      await tester.pumpAndSettle();

      // Session must still be running uninterrupted!
      expect(find.text('End Session'), findsOneWidget);
      expect(find.text('Focus'), findsWidgets);
    });

    testWidgets(
        '8. UI clearly indicates the phone saved preference and synchronization status with the hardware',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Start connected with Commuting
      await ModePreferences.saveMode(ActivityMode.commuting);
      await PoiseBleService.instance.connect(
        const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: 'P.O.I.S.E.',
          rssi: -55,
        ),
      );

      await tester.pumpWidget(const MaterialApp(
        home: DashboardPage(initialBluetoothConnected: true),
      ));
      await tester.pumpAndSettle();

      // In DashboardTab: should show "Hardware Synced"
      expect(find.text('Hardware Synced'), findsOneWidget);

      // In ControlsTab: should show "Synced with POISE hardware (Commuting active)"
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Synced with POISE hardware (Commuting active)'),
        findsOneWidget,
      );

      // Disconnect
      await PoiseBleService.instance.disconnect();
      await tester.pumpAndSettle();

      // In ControlsTab while disconnected: should show phone preference and offline fallback
      expect(
        find.textContaining(
            'Saved on phone: Commuting • Hardware offline (Rev 9 default: Normal)'),
        findsOneWidget,
      );

      // Back in DashboardTab while disconnected: should show saved preference
      await tester.tap(find.byIcon(Icons.home_filled));
      await tester.pumpAndSettle();

      expect(find.text('Saved: Commuting'), findsOneWidget);
    });
  });
}
