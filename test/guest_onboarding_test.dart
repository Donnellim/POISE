import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/option_page.dart';
import 'package:flutter_application_1/device_check_page.dart';
import 'package:flutter_application_1/device_setup_page.dart';
import 'package:flutter_application_1/get_started_page.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/sign_in_email_page.dart';
import 'package:flutter_application_1/sign_up_page.dart';
import 'package:flutter_application_1/widgets/guest_account_prompt.dart';

void main() {
  testWidgets('Guest prompt and device reconfirmation fit a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DeviceCheckPage()));
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(
        home: DashboardPage(
            initialBluetoothConnected: false, requiresAccount: true)));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> start(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
  }

  testWidgets(
      'Guest No opens disconnected dashboard; sign-in returns to device check',
      (tester) async {
    await start(tester, const OptionPage());
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();
    expect(tester.widget<DeviceCheckPage>(find.byType(DeviceCheckPage)).isGuest,
        true);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(
        tester
            .widget<DashboardPage>(find.byType(DashboardPage))
            .initialBluetoothConnected,
        false);
    expect(find.byType(GuestAccountPrompt), findsOneWidget);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign In with Email'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInEmailPage), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();
    expect(tester.widget<DeviceCheckPage>(find.byType(DeviceCheckPage)).isGuest,
        false);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceCheckPage), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing);
    }
    expect(
        find.textContaining('A P.O.I.S.E. device is required'), findsOneWidget);
    expect(Navigator.of(tester.element(find.byType(DeviceCheckPage))).canPop(),
        false);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceSetupPage), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceCheckPage), findsOneWidget);
    expect(Navigator.of(tester.element(find.byType(DeviceCheckPage))).canPop(),
        false);
  });

  testWidgets('Guest setup No preserves guest status; Yes follows normal setup',
      (tester) async {
    await start(tester, const DeviceCheckPage(isGuest: true));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceSetupPage), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<DeviceCheckPage>(find.byType(DeviceCheckPage)).isGuest,
          true);
    }
    expect(Navigator.of(tester.element(find.byType(DeviceCheckPage))).canPop(),
        false);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.byType(GetStartedPage), findsOneWidget);
    expect(find.byType(GuestAccountPrompt), findsNothing);
    await tester.tap(find.text('Connect to Bluetooth'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bluetooth-toggle')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed to Calibration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Zero Baseline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed to Dashboard'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(GuestAccountPrompt), findsNothing);
  });

  testWidgets(
      'Guest account creation proceeds to non-guest device confirmation',
      (tester) async {
    await start(tester, const DeviceCheckPage(isGuest: true));
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Up with Email'));
    await tester.pumpAndSettle();
    expect(find.byType(SignUpPage), findsOneWidget);
    final create = find.widgetWithText(ElevatedButton, 'Create Account');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Device Check'));
    await tester.pumpAndSettle();
    expect(tester.widget<DeviceCheckPage>(find.byType(DeviceCheckPage)).isGuest,
        false);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsNothing);
    expect(find.byType(DeviceCheckPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Closing sign-in preserves prompt and guest can return to setup',
      (tester) async {
    await start(
        tester,
        const DashboardPage(
            initialBluetoothConnected: false, requiresAccount: true));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(GuestAccountPrompt), findsOneWidget);
    await tester.tap(find.text('Back to device check'));
    await tester.pumpAndSettle();
    expect(tester.widget<DeviceCheckPage>(find.byType(DeviceCheckPage)).isGuest,
        true);
  });
}
