import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/notifications/notification_center.dart';

void main() {
  testWidgets('Bell opens mobile overlay, read and clear persist between tabs',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Device Disconnected'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark all as read'));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Mark all as read'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Mark all as read'))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Clear notifications'));
    await tester.pumpAndSettle();
    expect(find.text('No notifications yet'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
