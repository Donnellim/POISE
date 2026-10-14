import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/auth/social_auth.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/device_check_page.dart';
import 'package:flutter_application_1/sign_in_page.dart';
import 'package:flutter_application_1/sign_in_email_page.dart';

void main() {
  testWidgets('Unconfigured email sign-in cannot reach setup or dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SignInPage()));
    await tester.tap(find.text('Sign In with Email'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInEmailPage), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'test-password');
    final submit = find.widgetWithText(ElevatedButton, 'Sign In');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Account sign-in is not configured yet.'), findsOneWidget);
    expect(find.byType(SignInEmailPage), findsOneWidget);
    expect(find.byType(DeviceCheckPage), findsNothing);
    expect(find.byType(DashboardPage), findsNothing);
    expect(SocialAuth.instance.user, isNull);
  });
}
