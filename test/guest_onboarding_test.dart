import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/option_page.dart';
import 'package:flutter_application_1/device_check_page.dart';
import 'package:flutter_application_1/device_setup_page.dart';
import 'package:flutter_application_1/get_started_page.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/sign_in_page.dart';
import 'package:flutter_application_1/create_account_page.dart';
import 'package:flutter_application_1/sign_up_page.dart';
import 'package:flutter_application_1/sign_in_email_page.dart';
import 'package:flutter_application_1/auth/social_auth.dart';
import 'package:flutter_application_1/widgets/guest_account_prompt.dart';
import 'package:flutter_application_1/database/local_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = true;
  });
  tearDown(() async {
    PoiseLocalDatabase.instance.mockRecordsForTesting = null;
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = false;
    await SocialAuth.instance.signOut();
  });
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
      'Guest No opens disconnected dashboard and profile tab shows guest options',
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
    expect(
        tester.widget<DashboardPage>(find.byType(DashboardPage)).isGuest, true);
    expect(find.byType(GuestAccountPrompt), findsNothing);

    // Navigate to Profile tab (the 4th feature tab)
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Verify guest-specific UI elements in Profile tab
    expect(find.text('Guest Account'), findsOneWidget);
    expect(find.text('Save Your Data'), findsOneWidget);
    expect(find.textContaining('Sign in or create an account'), findsOneWidget);
    expect(find.text('Save posture data in local and cloud'), findsOneWidget);
    expect(find.text('Sync using your email account or personal account'),
        findsOneWidget);
    expect(
        find.widgetWithText(ElevatedButton, 'Create Account'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
    expect(find.text('Exit Guest Mode'), findsOneWidget);
    expect(find.text('Manage Account'), findsNothing);
    expect(find.text('Log Out'), findsNothing);
    expect(find.text('Delete Account'), findsNothing);

    // Test Sign In navigation from Profile tab
    final signInBtn = find.widgetWithText(ElevatedButton, 'Sign In');
    await tester.ensureVisible(signInBtn);
    await tester.pumpAndSettle();
    await tester.tap(signInBtn);
    await tester.pumpAndSettle();
    expect(find.byType(SignInPage), findsOneWidget);

    // Pop back to Profile
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets(
      'Guest setup No preserves guest status; Yes follows normal setup through calibration',
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
    expect(tester.widget<GetStartedPage>(find.byType(GetStartedPage)).isGuest,
        true);
    await tester.tap(find.text('Connect to Bluetooth'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed to Calibration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Zero Baseline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed to Dashboard'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(
        tester.widget<DashboardPage>(find.byType(DashboardPage)).isGuest, true);

    // Check Profile tab for guest options
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Guest Account'), findsOneWidget);
    expect(find.text('Save Your Data'), findsOneWidget);
  });

  testWidgets(
      'Guest creates account from Profile tab and proceeds to non-guest device check',
      (tester) async {
    await start(tester, const DeviceCheckPage(isGuest: true));
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    // Navigate to Profile tab
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Tap Create Account on the guest Profile tab
    final createBtn = find.widgetWithText(ElevatedButton, 'Create Account');
    await tester.ensureVisible(createBtn);
    await tester.pumpAndSettle();
    await tester.tap(createBtn);
    await tester.pumpAndSettle();
    expect(find.byType(CreateAccountPage), findsOneWidget);

    await tester.tap(find.text('Sign Up with Email'));
    await tester.pumpAndSettle();
    expect(find.byType(SignUpPage), findsOneWidget);

    SocialAuth.instance.onSignUpForTesting = (email, password) async {};
    addTearDown(() => SocialAuth.instance.onSignUpForTesting = null);

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'guest_converted@poise.app');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'Password123');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'), 'Password123');

    final create = find.widgetWithText(ElevatedButton, 'Create Account');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(find.text('Registration Complete!'), findsOneWidget);
    await tester.tap(find.text('Proceed to Sign In'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInEmailPage), findsOneWidget);
    expect(find.text('guest_converted@poise.app'), findsOneWidget);

    // Mock successful sign in transition
    SocialAuth.instance.onSignInForTesting = (email, password) async {
      final profile = AuthProfile(id: 'guest_converted_id', email: email);
      SocialAuth.instance.emitIncomingSignInForTesting(profile);
    };
    addTearDown(() => SocialAuth.instance.onSignInForTesting = null);

    await tester.enterText(find.byType(TextField).at(1), 'Password123');
    final signInBtn = find.widgetWithText(ElevatedButton, 'Sign In');
    await tester.ensureVisible(signInBtn);
    await tester.tap(signInBtn);
    await tester.pumpAndSettle();

    expect(tester.widget<DeviceCheckPage>(find.byType(DeviceCheckPage)).isGuest,
        false);

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsNothing);
    expect(find.byType(DeviceCheckPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Guest exit overlay allows cancel and exit to option page',
      (tester) async {
    await start(tester, const DashboardPage(isGuest: true));
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();

    // Tap Exit Guest Mode
    final exitBtn = find.text('Exit Guest Mode');
    await tester.ensureVisible(exitBtn);
    await tester.pumpAndSettle();
    await tester.tap(exitBtn);
    await tester.pumpAndSettle();
    expect(find.text('Exit Guest Mode?'), findsOneWidget);

    // Cancel dismisses the dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Exit Guest Mode?'), findsNothing);
    expect(find.text('Guest Account'), findsOneWidget);

    // Tap Exit Guest Mode again and confirm Exit
    await tester.ensureVisible(exitBtn);
    await tester.pumpAndSettle();
    await tester.tap(exitBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(find.byType(OptionPage), findsOneWidget);
  });

  testWidgets('Guest Profile fits small screens without overflow',
      (tester) async {
    for (final size in [
      const Size(320, 568),
      const Size(360, 800),
      const Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: DashboardPage(isGuest: true),
      ));
      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Guest Account'), findsOneWidget);
      expect(find.text('Save Your Data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
