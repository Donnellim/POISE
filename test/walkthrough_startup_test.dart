import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/walkthrough_page.dart';
import 'package:flutter_application_1/option_page.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:flutter_application_1/sign_in_page.dart';
import 'package:flutter_application_1/auth/social_auth.dart';

void main() {
  for (final setupComplete in [false, true]) {
    testWidgets(
        'Walkthrough precedes account options with setup=$setupComplete',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'poise.setupComplete': setupComplete,
        'poise.loggedOut': true,
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const PoiseApp());
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(WalkthroughPage), findsOneWidget);
      expect(find.byType(SignInPage), findsNothing);
      expect(find.byType(DashboardPage), findsNothing);
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      expect(find.byType(OptionPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final restoredAtStartup in [true, false]) {
    testWidgets('Browser login waits for Explore: restored=$restoredAtStartup',
        (tester) async {
      SharedPreferences.setMockInitialValues({'poise.setupComplete': true});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = SocialAuth.instance;
      await auth.signOut();
      if (restoredAtStartup) {
        await auth.signInWithPassword('tester@example.com', 'demo');
      }
      await tester.pumpWidget(const PoiseApp());
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      if (!restoredAtStartup) {
        await auth.signInWithPassword('tester@example.com', 'demo');
        await tester.pumpAndSettle();
      }
      expect(find.byType(WalkthroughPage), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing);
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(auth.user?.isDemo, true);
      await tester.pumpWidget(const SizedBox());
      await auth.signOut();
    }, skip: !kIsWeb);
  }
}
