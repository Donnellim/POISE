import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/auth/social_auth.dart';
import 'package:flutter_application_1/auth/social_sign_in_buttons.dart';
import 'package:flutter_application_1/sign_in_page.dart';
import 'package:flutter_application_1/create_account_page.dart';

class FakeAuth implements SocialAuthClient {
  final requests = <SocialProvider>[];
  Completer<AuthProfile?> pending = Completer<AuthProfile?>();
  @override
  void cancelSignIn() {
    if (!pending.isCompleted) pending.complete(null);
  }

  @override
  Future<AuthProfile?> signIn(SocialProvider provider) {
    requests.add(provider);
    return pending.future;
  }
}

void main() {
  testWidgets('Cancel sign-in releases the provider buttons', (tester) async {
    final client = FakeAuth();
    var navigated = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SocialSignInButtons(
          width: 300, client: client, onAuthenticated: (_) => navigated = true),
    )));
    await tester.tap(find.text('Sign In with Google'));
    await tester.pump();
    await tester.tap(find.text('Cancel sign-in'));
    await tester.pumpAndSettle();
    expect(navigated, isFalse);
    expect(find.text('Cancel sign-in'), findsNothing);
    expect(
        tester
            .widget<ElevatedButton>(find.byType(ElevatedButton).first)
            .onPressed,
        isNotNull);
  });

  for (final create in [false, true]) {
    for (final provider in SocialProvider.values) {
      testWidgets(
          '${create ? 'Continue' : 'Sign in'} uses $provider and waits for authentication',
          (tester) async {
        final client = FakeAuth();
        AuthProfile? result;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SocialSignInButtons(
          width: 300,
          createAccount: create,
          client: client,
          onAuthenticated: (profile) => result = profile,
        ))));
        final button = find.byType(ElevatedButton).at(provider.index);
        await tester.tap(button);
        await tester.pump();
        expect(client.requests, [provider]);
        expect(result, isNull);
        for (final widget
            in tester.widgetList<ElevatedButton>(find.byType(ElevatedButton))) {
          expect(widget.onPressed, isNull);
        }
        client.pending.complete(const AuthProfile(
            id: 'verified-user',
            displayName: 'Alex',
            email: 'alex@example.com'));
        await tester.pumpAndSettle();
        expect(result?.id, 'verified-user');
      });
    }
  }

  testWidgets('Cancellation stays on screen; errors allow retry',
      (tester) async {
    final client = FakeAuth();
    var navigationCount = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SocialSignInButtons(
      width: 300,
      client: client,
      onAuthenticated: (_) => navigationCount++,
    ))));
    await tester.tap(find.text('Sign In with Google'));
    client.pending.complete(null);
    await tester.pumpAndSettle();
    expect(navigationCount, 0);
    client.pending = Completer<AuthProfile?>();
    await tester.tap(find.text('Sign In with Microsoft'));
    client.pending.completeError(
        const SignInFailure('Check your connection and try again.'));
    await tester.pumpAndSettle();
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(navigationCount, 0);
    expect(
        tester
            .widget<ElevatedButton>(find.byType(ElevatedButton).first)
            .onPressed,
        isNotNull);
  });

  testWidgets('Both real pages expose setup errors instead of fake success',
      (tester) async {
    for (final page in [const SignInPage(), const CreateAccountPage()]) {
      await tester.pumpWidget(MaterialApp(home: page));
      final buttons = find.byType(SocialSignInButtons);
      expect(buttons, findsOneWidget);
      final button = find
          .descendant(of: buttons, matching: find.byType(ElevatedButton))
          .first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('Account sign-in is not configured yet.'),
          findsOneWidget);
    }
  });
}
