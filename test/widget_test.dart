import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/activity_mode.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/calibration_page.dart';
import 'package:flutter_application_1/tabs/dashboard_tab.dart';
import 'package:flutter_application_1/get_started_page.dart';

import 'package:flutter_application_1/database/local_database.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
    await PoiseBleService.instance.connect(const PoiseDiscoveredDevice(
        id: 'SIMULATED-TEST', name: 'POISE', rssi: -50));
  });
  tearDown(() {
    PoiseLocalDatabase.instance.mockRecordsForTesting = null;
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = false;
  });
  testWidgets('Unset mode defaults safely and selection survives reassembly',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('15°/2s'), findsOneWidget);
    {
      final reassembly = tester.binding.reassembleApplication();
      await tester.pump();
      await tester.pump();
      await reassembly;
    }
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ActivityMode.leisure.label));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    {
      final reassembly = tester.binding.reassembleApplication();
      await tester.pump();
      await tester.pump();
      await reassembly;
    }
    await tester.pump();
    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    expect(find.text(ActivityMode.leisure.label), findsOneWidget);
    expect(find.text('20°/3s'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Controls presets drive read-only dashboard summaries',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    for (final mode in ActivityMode.values) {
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode.label));
      await tester.pumpAndSettle();
      expect(find.text('Description'), findsOneWidget);
      expect(find.text(mode.description), findsOneWidget);
      await tester.tap(find.byIcon(Icons.home_filled));
      await tester.pumpAndSettle();
      expect(find.text(mode.label), findsOneWidget);
      expect(find.text(mode.threshold), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('active-mode-summary')));
      await tester.tap(find.byKey(const ValueKey('threshold-summary')));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Device Connected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect Device'));
    await tester.pumpAndSettle();
    expect(find.text('--°'), findsOneWidget);
    expect(find.text(ActivityMode.commuting.threshold), findsNothing);
    expect(find.text('---'), findsNWidgets(2));
    expect(find.text('--:--:--'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Controls tab displays dedicated Description container updating per mode',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    expect(find.text('Normal'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    // Default selection is Normal
    expect(find.text('Description'), findsOneWidget);
    expect(find.text(ActivityMode.normal.description), findsOneWidget);

    // Tap Focus card
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();

    // Description updates to Focus Mode
    expect(find.text(ActivityMode.focus.description), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('10°/1s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Controls tab displays Activity Mode, Description, and Feedback Routing without warning banner',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Activity Mode'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Feedback Routing'), findsOneWidget);

    // Warning banner is removed
    expect(
        find.text(
            'Feedback is triggered when an incorrect posture is maintained according to the selected activity mode.'),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dashboard Bluetooth reconnects without leaving the dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ble = PoiseBleService.instance;
    const device =
        PoiseDiscoveredDevice(id: 'SIMULATED-TEST', name: 'POISE', rssi: -60);
    await ble.connect(device);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pump(const Duration(seconds: 2));
    await ble.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('Not Connected'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('--:--:--'), findsOneWidget);
    await tester.tap(find.text('Not Connected'));
    await tester.pumpAndSettle();
    expect(find.byType(GetStartedPage), findsNothing);
    expect(Navigator.of(tester.element(find.byType(DashboardTab))).canPop(),
        false);
    expect(find.text('Device Connected'), findsOneWidget);
    expect(find.text('Set Your Neutral Posture'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:00:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Failed dashboard reconnect stays disconnected and allows retry',
      (tester) async {
    await PoiseBleService.instance.disconnect();
    PoiseBleService.instance.simulateScanFindsDevice = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('poise.deviceId');
    await tester.pumpWidget(const MaterialApp(
      home: DashboardPage(initialBluetoothConnected: false),
    ));
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Not Connected'));
      await tester.pumpAndSettle();
      expect(find.byType(GetStartedPage), findsNothing);
      expect(find.text('Not Connected'), findsOneWidget);
      expect(find.textContaining('Could not reconnect'), findsOneWidget);
      expect(find.text('Set Your Neutral Posture'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Dashboard Bluetooth scan finds nearby device and connects from disconnected state',
      (tester) async {
    await PoiseBleService.instance.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('poise.deviceId');
    await tester.pumpWidget(const MaterialApp(
      home: DashboardPage(initialBluetoothConnected: false),
    ));
    expect(find.text('Not Connected'), findsOneWidget);
    await tester.tap(find.text('Not Connected'));
    await tester.pump();
    // Immediate scan results can connect before the first frame is rendered.
    expect(find.textContaining('Could not reconnect'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Searching for P.O.I.S.E. Device'), findsNothing);
    expect(find.text('Device Connected'), findsOneWidget);
    expect(find.textContaining('P.O.I.S.E. device connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'Proceed after zero baseline always opens Home and clears setup routes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await PoiseBleService.instance.connect(const PoiseDiscoveredDevice(
      id: 'SIMULATED-TEST',
      name: 'POISE',
      rssi: -60,
    ));
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const DashboardPage()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const CalibrationPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Zero Baseline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed to Dashboard'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardTab).hitTestable(), findsOneWidget);
    expect(find.text('Controls'), findsNothing);
    expect(find.text(find.text('0°').evaluate().isNotEmpty ? '0°' : '--°'),
        findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 568),
    const Size(320, 640),
    const Size(740, 360),
    const Size(343, 762),
    const Size(1920, 1080)
  ]) {
    testWidgets('Dashboard fits $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
      expect(tester.takeException(), isNull);
      final readingFinder = find.text('0°').evaluate().isNotEmpty
          ? find.text('0°')
          : find.text('--°');
      final reading = tester.getRect(readingFinder);
      final model = tester.getRect(find.byType(RealTimeSpineTracker));
      expect(reading.bottom, lessThan(model.top));
      expect(find.text('Optimal Posture'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(DashboardTab), matching: find.byType(Scrollable)),
          findsNothing);
      final session = find.byKey(const ValueKey('session-toggle'));
      expect(tester.getRect(session).bottom,
          lessThan(tester.getRect(find.byIcon(Icons.home_filled)).top));
      final headerBeforeDrag = tester.getTopLeft(find.text('P.O.I.S.E.'));
      await tester.drag(find.byKey(const ValueKey('active-mode-summary')),
          const Offset(0, -150));
      await tester.pump();
      expect(tester.getTopLeft(find.text('P.O.I.S.E.')), headerBeforeDrag);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('GetStartedPage renders and connects without Material assertion',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: GetStartedPage()));
    expect(find.text("Let's Get Started"), findsOneWidget);
    expect(find.text('Connect to Bluetooth'), findsOneWidget);

    await tester.tap(find.text('Connect to Bluetooth'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
