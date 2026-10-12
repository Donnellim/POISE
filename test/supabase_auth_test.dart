import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/auth/social_auth.dart';

Session session({String id = 'verified-user'}) => Session(
      accessToken: 'test-only-token',
      tokenType: 'bearer',
      user: User(
          id: id,
          appMetadata: const {},
          userMetadata: const {'full_name': 'Alex Example'},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
          email: 'alex@example.com'),
    );

void main() {
  test('Provider mapping uses Azure and requests email for Microsoft', () {
    expect(SocialProvider.google.oauthProvider, OAuthProvider.google);
    expect(SocialProvider.facebook.oauthProvider, OAuthProvider.facebook);
    expect(SocialProvider.microsoft.oauthProvider, OAuthProvider.azure);
    expect(SocialProvider.microsoft.scopes, 'email');
  });

  test('Browser launch waits for a verified session and maps the profile',
      () async {
    final events = StreamController<AuthState>();
    final auth =
        SocialAuth.forTesting(events: events.stream, launch: (_) async => true);
    addTearDown(() async {
      await auth.dispose();
      await events.close();
    });
    var completed = false;
    final result = auth.signIn(SocialProvider.google).then((profile) {
      completed = true;
      return profile;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    expect(auth.user, isNull);
    events.add(AuthState(AuthChangeEvent.signedIn, session()));
    final profile = await result;
    expect(profile?.displayName, 'Alex Example');
    expect(profile?.email, 'alex@example.com');
    expect(auth.user?.id, 'verified-user');
  });

  test('Cancellation and timeout allow retry without granting access',
      () async {
    final events = StreamController<AuthState>();
    final auth = SocialAuth.forTesting(
        events: events.stream,
        launch: (_) async => true,
        timeout: const Duration(milliseconds: 20));
    addTearDown(() async {
      await auth.dispose();
      await events.close();
    });
    final cancelled = auth.signIn(SocialProvider.facebook);
    auth.cancelSignIn();
    expect(await cancelled, isNull);
    await expectLater(
        auth.signIn(SocialProvider.microsoft), throwsA(isA<SignInFailure>()));
    expect(auth.user, isNull);
    final retry = auth.signIn(SocialProvider.microsoft);
    events.add(AuthState(AuthChangeEvent.signedIn, session()));
    expect((await retry)?.id, 'verified-user');
  });

  test('Launch failure and callback error do not create sessions', () async {
    final events = StreamController<AuthState>();
    var launchWorks = false;
    final auth = SocialAuth.forTesting(
        events: events.stream, launch: (_) async => launchWorks);
    addTearDown(() async {
      await auth.dispose();
      await events.close();
    });
    await expectLater(
        auth.signIn(SocialProvider.google), throwsA(isA<SignInFailure>()));
    launchWorks = true;
    final result = auth.signIn(SocialProvider.google);
    events.addError(const AuthException('Consent denied'));
    await expectLater(result, throwsA(isA<SignInFailure>()));
    expect(auth.user, isNull);
    expect(auth.lastError.value, isNotNull);
  });

  test('Cold callback notifies app; token refresh does not navigate again',
      () async {
    final events = StreamController<AuthState>();
    final auth =
        SocialAuth.forTesting(events: events.stream, launch: (_) async => true);
    final received = <AuthProfile>[];
    final subscription = auth.incomingSignIns.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await auth.dispose();
      await events.close();
    });
    events.add(AuthState(AuthChangeEvent.signedIn, session()));
    await Future<void>.delayed(Duration.zero);
    expect(received.length, 1);
    events.add(AuthState(AuthChangeEvent.tokenRefreshed, session()));
    await Future<void>.delayed(Duration.zero);
    expect(received.length, 1);
    events.add(AuthState(AuthChangeEvent.signedOut, null));
    await Future<void>.delayed(Duration.zero);
    expect(auth.user, isNull);
  });
}
