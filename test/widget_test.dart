import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/activity_mode.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/calibration_page.dart';
import 'package:flutter_application_1/tabs/dashboard_tab.dart';
import 'package:flutter_application_1/tabs/controls_tab.dart';
import 'package:flutter_application_1/bluetooth_connect_page.dart';

void main() {
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
    await tester.tap(find.text('Gaming'));
    await tester.pumpAndSettle();
    expect(find.text('Gaming Mode'), findsOneWidget);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    {
      final reassembly = tester.binding.reassembleApplication();
      await tester.pump();
      await tester.pump();
      await reassembly;
    }
    await tester.pump();
    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    expect(find.text('Gaming'), findsOneWidget);
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
      expect(find.text(mode.overlayTitle), findsOneWidget);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
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
    expect(find.text('--°/--s'), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Controls overlay Cancel does not change mode', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    expect(find.text('Normal'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus'));
    await tester.pumpAndSettle();
    expect(find.text('Focus Mode'), findsOneWidget);
    expect(
        find.text(
            'For studying, reading, and other focused academic activities. Uses a more sensitive posture setting to help you stay aware of forward-leaning posture during prolonged study sessions.'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    // Mode should still be Normal
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('15°/2s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Controls tab is unscrollable and does not overlap bottom navigation bar',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(ControlsTab), matching: find.byType(Scrollable)),
        findsNothing);
    final bannerRect = tester.getRect(find.text(
        'Feedback is triggered when an incorrect posture is maintained according to the selected activity mode.'));
    final navBarRect = tester.getRect(find.byIcon(Icons.tune_rounded));
    expect(bannerRect.bottom, lessThan(navBarRect.top));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Reconnect requires a new baseline and cancel cannot resume readings',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.text('Device Connected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recalibrate'));
    await tester.pump();
    expect(find.text('Set Zero Baseline'), findsNothing);
    await tester.tap(find.text('Not Connected'));
    await tester.pumpAndSettle();
    expect(find.text('Set Zero Baseline'), findsOneWidget);
    expect(find.text('--°'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-toggle')));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('--°'), findsOneWidget);
    expect(find.text('--°/--s'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaming'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.home_filled));
    await tester.pumpAndSettle();
    expect(find.text('--°'), findsOneWidget);
    await tester.tap(find.text('Recalibrate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Zero Baseline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('0°'), findsOneWidget);
    expect(find.text('Gaming'), findsOneWidget);
    expect(find.text('20°/3s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:00:00'), findsNothing);
    // Dragging the gauge must never fabricate sensor readings.
    await tester.dragFrom(
        tester.getTopLeft(find.byKey(const ValueKey('pitch-gauge'))) +
            const Offset(20, 70),
        const Offset(80, 0));
    await tester.pump();
    expect(find.text('0°'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Proceed after zero baseline always opens Home and clears setup routes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    expect(find.text('0°'), findsOneWidget);
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
      await tester.pump();
      expect(tester.takeException(), isNull);
      final reading = tester.getRect(find.text('0°'));
      final model = tester.getRect(find.byType(Image).first);
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

  testWidgets('BluetoothConnectPage toggle enables scan and renders without Material assertion',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: BluetoothConnectPage()));
    expect(find.byKey(const Key('bluetooth-toggle')), findsOneWidget);

    // Toggle Bluetooth ON
    await tester.tap(find.byKey(const Key('bluetooth-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
