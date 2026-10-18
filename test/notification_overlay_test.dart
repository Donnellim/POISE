import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/notifications/notification_center.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter_application_1/widgets/poise_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
  });

  tearDown(() {
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = false;
  });

  testWidgets(
      'Notification bell is removed from mobile app; notifications registered by system',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.pumpAndSettle();

    // Verify notification bell is completely removed from mobile header
    expect(find.byTooltip('Notifications'), findsNothing);
    expect(find.byIcon(Icons.notifications_rounded), findsNothing);

    // Switch to Controls tab: no notification bell
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsNothing);

    // Switch to Analytics tab: no notification bell
    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsNothing);

    // Switch to Profile tab: no notification bell
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PoiseHeader monitors POISE device battery accurately when connected',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 1. Initial connected device with default 100% battery
    await PoiseBleService.instance.connect(const PoiseDiscoveredDevice(
      id: 'BATTERY-TEST-DEV',
      name: 'POISE',
      rssi: -50,
    ));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SafeArea(child: PoiseHeader())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('100%'), findsOneWidget);
    expect(find.bySemanticsLabel('POISE device battery: 100 percent'),
        findsOneWidget);

    // 2. Hardware reports 85% battery
    PoiseBleService.instance.updateBatteryLevel(85);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('85%'), findsOneWidget);
    expect(find.bySemanticsLabel('POISE device battery: 85 percent'),
        findsOneWidget);

    // 3. Hardware reports 20% low battery
    PoiseBleService.instance.updateBatteryLevel(20);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('20%'), findsOneWidget);
    expect(find.bySemanticsLabel('POISE device battery: 20 percent'),
        findsOneWidget);

    // 4. Disconnecting device shows disconnected state
    await PoiseBleService.instance.disconnect();
    await tester.pumpAndSettle();
    expect(find.text('--%'), findsOneWidget);
    expect(find.bySemanticsLabel('POISE device disconnected'), findsOneWidget);
  });

  testWidgets('Small screen and large text remain scrollable without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final center = NotificationCenter.preview();
    addTearDown(center.dispose);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showNotifications(context, center),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Charging'), 150,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Charging'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
