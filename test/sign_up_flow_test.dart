import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/auth/social_auth.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/device_check_page.dart';
import 'package:flutter_application_1/sign_up_page.dart';
import 'package:flutter_application_1/sign_in_page.dart';
import 'package:flutter_application_1/sign_in_email_page.dart';

void main() {
  testWidgets('Account creation routes to SignInEmailPage with pre-filled email',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SocialAuth.instance.onSignUpForTesting = (email, password) async {};
    addTearDown(() => SocialAuth.instance.onSignUpForTesting = null);

    await tester.pumpWidget(const MaterialApp(home: SignUpPage()));
    expect(find.byType(SignUpPage), findsOneWidget);

    // Enter registration details
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'newuser@poise.app');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'Password123');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'), 'Password123');

    // Tap create account
    final createBtn = find.widgetWithText(ElevatedButton, 'Create Account');
    await tester.ensureVisible(createBtn);
    await tester.tap(createBtn);
    await tester.pumpAndSettle();

    // Dialog appears with success and Proceed to Sign In button
    expect(find.text('Registration Complete!'), findsOneWidget);
    expect(find.text('Proceed to Sign In'), findsOneWidget);
    expect(find.byType(DeviceCheckPage), findsNothing);
    expect(find.byType(DashboardPage), findsNothing);

    // Tap Proceed to Sign In
    await tester.tap(find.text('Proceed to Sign In'));
    await tester.pumpAndSettle();

    // Should navigate to SignInEmailPage with pre-filled email
    expect(find.byType(SignInEmailPage), findsOneWidget);
    expect(find.text('newuser@poise.app'), findsOneWidget);
    expect(find.byType(DeviceCheckPage), findsNothing);
    expect(find.byType(DashboardPage), findsNothing);

    // Tap back button from SignInEmailPage -> safely routes to SignInPage, never blank screen
    final backBtn = find.byIcon(Icons.arrow_back);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.byType(SignInEmailPage), findsNothing);
  });

  testWidgets(
      'SignInEmailPage standalone back button safely falls back to SignInPage',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Pumping directly without previous routes
    await tester.pumpWidget(const MaterialApp(home: SignInEmailPage()));
    expect(find.byType(SignInEmailPage), findsOneWidget);

    final backBtn = find.byIcon(Icons.arrow_back);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // Must not be blank; falls back to SignInPage
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.byType(SignInEmailPage), findsNothing);
  });

  testWidgets(
      'SignUpPage rejects passwords with fewer than 8 chars, no letters, or no numbers',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SignUpPage()));

    // 1. Password with only letters (no numbers)
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'test@poise.app');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'abcdefgh');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'), 'abcdefgh');

    final createBtn = find.widgetWithText(ElevatedButton, 'Create Account');
    await tester.ensureVisible(createBtn);
    await tester.tap(createBtn);
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Password must be at least 8 characters long and contain both letters and numbers'),
        findsOneWidget);

    // 2. Password with only numbers (no letters)
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), '12345678');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'), '12345678');
    await tester.ensureVisible(createBtn);
    await tester.tap(createBtn);
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Password must be at least 8 characters long and contain both letters and numbers'),
        findsOneWidget);

    // 3. Password shorter than 8 chars
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'Pass1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password'), 'Pass1');
    await tester.ensureVisible(createBtn);
    await tester.tap(createBtn);
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Password must be at least 8 characters long and contain both letters and numbers'),
        findsOneWidget);
  });
}
