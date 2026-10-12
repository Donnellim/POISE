import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SocialProvider { google, facebook, microsoft }

extension SupabaseProvider on SocialProvider {
  OAuthProvider get oauthProvider => switch (this) {
        SocialProvider.google => OAuthProvider.google,
        SocialProvider.facebook => OAuthProvider.facebook,
        SocialProvider.microsoft => OAuthProvider.azure,
      };
  String get scopes =>
      this == SocialProvider.facebook ? 'email,public_profile' : 'email';
  Map<String, String> get queryParameters => this == SocialProvider.facebook
      ? const {}
      : const {'prompt': 'select_account'};
}

class AuthProfile {
  const AuthProfile({required this.id, this.displayName, this.email});
  factory AuthProfile.fromUser(User user) {
    final metadata = user.userMetadata ?? {};
    final name = metadata['full_name'] ?? metadata['name'];
    return AuthProfile(
        id: user.id,
        displayName: name is String ? name : null,
        email: user.email);
  }
  final String id;
  final String? displayName;
  final String? email;
}

class SignInFailure implements Exception {
  const SignInFailure(this.message);
  final String message;
}

abstract class SocialAuthClient {
  Future<AuthProfile?> signIn(SocialProvider provider);
  void cancelSignIn();
}

/// Supabase authentication only. No application database tables or queries.
class SocialAuth implements SocialAuthClient {
  SocialAuth();
  static final instance = SocialAuth();
  static const mobileRedirect = 'com.poise.app://login-callback/';
  final lastError = ValueNotifier<String?>(null);
  final _incomingSignIns = StreamController<AuthProfile>.broadcast();
  Stream<AuthProfile> get incomingSignIns => _incomingSignIns.stream;
  StreamSubscription<AuthState>? _subscription;
  Future<bool> Function(SocialProvider)? _launch;
  SupabaseClient? _client;
  AuthProfile? _profile;
  AuthProfile? get user => _profile;
  Completer<AuthProfile?>? _pending;
  Duration _timeout = const Duration(minutes: 3);

  @visibleForTesting
  SocialAuth.forTesting(
      {required Stream<AuthState> events,
      required Future<bool> Function(SocialProvider) launch,
      Duration timeout = const Duration(minutes: 3)}) {
    _timeout = timeout;
    _launch = launch;
    _listen(events);
  }

  Future<void> initialize() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty || key.isEmpty || _client != null) return;
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUriPredicate: (uri) =>
              kIsWeb ||
              (uri.scheme == 'com.poise.app' &&
                  uri.host == 'login-callback' &&
                  uri.path == '/'),
        ),
      );
      _client = Supabase.instance.client;
      final session = _client!.auth.currentSession;
      if (session != null && !session.isExpired) {
        _profile = AuthProfile.fromUser(session.user);
      }
      _listen(_client!.auth.onAuthStateChange);
      _launch = (provider) => _client!.auth.signInWithOAuth(
            provider.oauthProvider,
            scopes: provider.scopes,
            queryParams: provider.queryParameters,
            redirectTo: kIsWeb ? _webRedirect : mobileRedirect,
            authScreenLaunchMode: kIsWeb
                ? LaunchMode.platformDefault
                : LaunchMode.externalApplication,
          );
    } catch (_) {
      _launch = null;
      lastError.value =
          'Account sign-in could not initialize. Check the Supabase configuration and restart the app.';
    }
  }

  String get _webRedirect {
    const configured = String.fromEnvironment('SUPABASE_WEB_REDIRECT_URL');
    return configured.isNotEmpty
        ? configured
        : Uri.base.replace(query: '', fragment: '').toString();
  }

  void _listen(Stream<AuthState> events) {
    _subscription = events.listen((state) {
      final session = state.session;
      final previousId = _profile?.id;
      _profile = session == null || session.isExpired
          ? null
          : AuthProfile.fromUser(session.user);
      if (_profile == null) return;
      if (state.event == AuthChangeEvent.signedIn && _pending != null) {
        if (!_pending!.isCompleted) _pending!.complete(_profile);
      } else if (previousId != _profile!.id) {
        // Handles cold starts, web redirects and callbacks arriving after a timeout.
        _incomingSignIns.add(_profile!);
      }
    }, onError: (Object error, StackTrace stack) {
      const message = 'Sign-in could not finish. Please try again.';
      lastError.value = message;
      final pending = _pending;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(const SignInFailure(message));
      }
    });
  }

  @override
  Future<AuthProfile?> signIn(SocialProvider provider) async {
    final launch = _launch;
    if (launch == null) {
      throw const SignInFailure(
          'Account sign-in is not configured yet. Please try again after the app setup is complete.');
    }
    if (_pending != null) return null;
    lastError.value = null;
    final pending = Completer<AuthProfile?>();
    _pending = pending;
    // Observe errors immediately, even if a callback arrives while the browser opens.
    final result = pending.future.timeout(_timeout, onTimeout: () {
      throw const SignInFailure('Sign-in timed out. Please try again.');
    });
    unawaited(result.then<void>((_) {},
        onError: (Object error, StackTrace stack) {}));
    try {
      if (!await launch(provider)) {
        throw const SignInFailure(
            'Could not open account sign-in. Please try again.');
      }
      // Opening a browser is not proof of authentication. Wait for the SDK session.
      return await result;
    } on AuthException {
      throw const SignInFailure(
          'Sign-in is unavailable. Check your connection or the provider setup and try again.');
    } finally {
      if (!pending.isCompleted) pending.complete(null);
      if (identical(_pending, pending)) _pending = null;
    }
  }

  @override
  void cancelSignIn() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  Future<void> signOut() async {
    cancelSignIn();
    await _client?.auth.signOut(scope: SignOutScope.local);
    _profile = null;
  }

  Future<void> dispose() async {
    cancelSignIn();
    await _subscription?.cancel();
    await _incomingSignIns.close();
    lastError.dispose();
  }
}
