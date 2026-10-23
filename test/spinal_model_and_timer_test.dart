import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/activity_mode.dart';
import 'package:flutter_application_1/tabs/dashboard_tab.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter_application_1/database/local_database.dart';
import 'package:flutter_application_1/database/network_service.dart';
import 'package:flutter_application_1/analytics/analytics_data.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NetworkService.instance.mockIsConnectedForTesting = false;
    PoiseBleService.instance.simulateForTesting = true;
    PoiseBleService.instance.resetForTesting();
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
    await PoiseBleService.instance.connect(const PoiseDiscoveredDevice(
        id: 'SIMULATED-TEST', name: 'POISE', rssi: -50));
  });

  tearDown(() async {
    await PoiseBleService.instance.disconnect();
    PoiseBleService.instance.resetForTesting();
    PoiseLocalDatabase.instance.mockRecordsForTesting = null;
  });

  group('Static 2D Spinal Model & C7–T1 Alert Specificity', () {
    testWidgets(
        'Spine model renders clean static 2D image without marker during optimal posture',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 5.0,
              isConnected: true,
              activeMode: ActivityMode.normal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Static 2D image is present
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final Image image = tester.widget(imageFinder);
      expect((image.image as AssetImage).assetName,
          'assets/images/spine_model.png');

      // No marker or alert badge on C7-T1 during optimal posture
      expect(find.text('SLOUCH ALERT'), findsNothing);
      expect(find.textContaining('WARN'), findsNothing);
      expect(find.byIcon(Icons.priority_high_rounded), findsNothing);
      expect(find.byIcon(Icons.warning_rounded), findsNothing);
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsNothing);
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsNothing);
    });

    testWidgets(
        'Thresholds and warnings vary strictly per mode at C7–T1 region',
        (tester) async {
      // 1. Focus Mode (10° threshold, 1s dwell)
      // Angle 12° exceeds 10° -> Orange warning glow while counting
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 12.0,
              isConnected: true,
              activeMode: ActivityMode.focus,
              isSlouchWarning: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsOneWidget);
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsNothing);
      expect(find.text('SLOUCH ALERT'), findsNothing);

      // Focus Mode Slouch Alert (time exceeded -> Red alert glow)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 14.0,
              isConnected: true,
              activeMode: ActivityMode.focus,
              isSlouchAlert: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsOneWidget);
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsNothing);
      expect(find.text('SLOUCH ALERT'), findsNothing);

      // 2. Leisure Mode (20° threshold, 3s dwell)
      // Angle 18° is within 20° -> Optimal (no glow)!
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 18.0,
              isConnected: true,
              activeMode: ActivityMode.leisure,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsNothing);
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsNothing);

      // Leisure Mode at 22° in warning window -> Orange glow
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 22.0,
              isConnected: true,
              activeMode: ActivityMode.leisure,
              isSlouchWarning: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsOneWidget);
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsNothing);

      // 3. Commuting Mode (25° threshold, 5s dwell)
      // Angle 22° is within 25° -> Optimal (no glow)!
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 22.0,
              isConnected: true,
              activeMode: ActivityMode.commuting,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsNothing);
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsNothing);

      // Commuting Mode at 27° in warning window -> Orange glow
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 27.0,
              isConnected: true,
              activeMode: ActivityMode.commuting,
              isSlouchWarning: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsOneWidget);
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsNothing);

      // Commuting Mode critical alert (dwell exceeded -> Red glow)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RealTimeSpineTracker(
              pitchAngle: 27.0,
              isConnected: true,
              activeMode: ActivityMode.commuting,
              isSlouchAlert: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('neck-glow-alert')), findsOneWidget);
      expect(find.byKey(const ValueKey('neck-glow-warning')), findsNothing);
    });
  });

  group('Session Timer & Inactive State Isolation', () {
    testWidgets(
        'Dashboard session timer is strictly 00:00:00 when inactive and does not load past sessions',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Prepopulate past sessions (e.g. 1 hour of wear time in Analytics)
      final now = DateTime.now();
      PoiseLocalDatabase.instance.mockRecordsForTesting = [
        PostureRecord(
          at: now.subtract(const Duration(hours: 1)),
          seconds: 3600,
          pitch: 0.0,
          mode: ActivityMode.normal,
          slouchEvents: 0,
          warnings: 0,
        ),
      ];

      // Total wear seconds in Analytics is 3600
      final wearSec =
          await PoiseLocalDatabase.instance.getTodayTotalWearSeconds();
      expect(wearSec, 3600);

      // Load DashboardTab without active session
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardTab(
              activeMode: ActivityMode.normal,
              isBluetoothConnected: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Session status must show Inactive and timer must read 00:00:00 (NOT 01:00:00!)
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('00:00:00'), findsOneWidget);
      expect(find.text('01:00:00'), findsNothing);
      expect(find.text('Start Session'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'Timer increments continuously during active session and resets to 00:00:00 on end',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardTab(
              activeMode: ActivityMode.normal,
              isBluetoothConnected: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Start Session via toggle button
      expect(find.text('Start Session'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('session-toggle')));
      await tester.pump();

      // Session is now running
      await tester.tap(find.text('Set Calibration'));
      await tester.pump();
      expect(find.text('End Session'), findsOneWidget);
      expect(find.text('End Session'), findsOneWidget);

      // Wait 2 seconds
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Timer advances continuously
      expect(find.text('00:00:02'), findsOneWidget);

      // End Session via toggle button
      await tester.tap(find.byKey(const ValueKey('session-toggle')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      // Timer resets strictly to 00:00:00 and displays Session Inactive
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('00:00:00'), findsOneWidget);
      expect(find.text('Start Session'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Posture Meter & Mode Adjustment', () {
    testWidgets(
        'Posture meter renders CustomPaint gauge and does not display recalibrate button',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardTab(
              activeMode: ActivityMode.focus,
              isBluetoothConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pitch gauge CustomPaint is present
      expect(find.byKey(const ValueKey('pitch-gauge')), findsOneWidget);

      // Standalone Recalibrate button is removed
      expect(find.text('Recalibrate'), findsNothing);
      expect(find.byIcon(Icons.sync_rounded), findsNothing);

      // Start Session button is present (which handles baseline tare calibration)
      expect(find.text('Start Session'), findsOneWidget);
    });
  });
}
