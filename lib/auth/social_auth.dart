import 'dart:async';
import '../device_session.dart';
import '../bluetooth/poise_ble_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_database.dart';
import '../database/models.dart';
import '../database/sync_service.dart';

enum SocialProvider { google, facebook, microsoft }

extension SupabaseProvider on SocialProvider {
  OAuthProvider get oauthProvider => switch (this) {
        SocialProvider.google => OAuthProvider.google,
        SocialProvider.facebook => OAuthProvider.facebook,
        SocialProvider.microsoft => OAuthProvider.azure,
      };
  String get displayName => switch (this) {
        SocialProvider.google => 'Google',
        SocialProvider.facebook => 'Facebook',
        SocialProvider.microsoft => 'Microsoft',
      };
  String get scopes =>
      this == SocialProvider.facebook ? 'email,public_profile' : 'email';
  Map<String, String> get queryParameters => this == SocialProvider.facebook
      ? const {}
      : const {'prompt': 'select_account'};
}

class AuthProfile {
  const AuthProfile(
      {required this.id, this.displayName, this.email, this.isDemo = false});
  factory AuthProfile.fromUser(User user) {
    Map<String, dynamic> metadata =
        Map<String, dynamic>.from(user.userMetadata ?? {});

    // If the user has multiple linked identities (e.g., Microsoft and Google sharing the same email),
    // extract data from the identity that signed in most recently:
    if (user.identities != null && user.identities!.isNotEmpty) {
      final sorted = List<UserIdentity>.from(user.identities!)
        ..sort((a, b) {
          final timeA = DateTime.tryParse(a.lastSignInAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = DateTime.tryParse(b.lastSignInAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
      final latest = sorted.first;
      if (latest.identityData != null && latest.identityData!.isNotEmpty) {
        metadata = Map<String, dynamic>.from(latest.identityData!);
      }
    }

    final givenName = metadata['given_name'] ?? metadata['givenName'];
    final familyName = metadata['family_name'] ?? metadata['surname'];
    final combinedName = (givenName != null || familyName != null)
        ? '${givenName ?? ''} ${familyName ?? ''}'.trim()
        : null;

    final name = metadata['full_name'] ??
        metadata['name'] ??
        metadata['displayName'] ??
        (combinedName != null && combinedName.isNotEmpty ? combinedName : null) ??
        metadata['preferred_username'];

    final email = (metadata['email'] is String && (metadata['email'] as String).isNotEmpty)
        ? metadata['email'] as String
        : user.email ??
            (metadata['preferred_username'] is String &&
                    (metadata['preferred_username'] as String).contains('@')
                ? metadata['preferred_username'] as String
                : null);

    return AuthProfile(
      id: user.id,
      displayName:
          name is String && name.trim().isNotEmpty ? name.trim() : null,
      email: email,
    );
  }
  final String id;
  final String? displayName;
  final String? email;
  final bool isDemo;
}

class SignInFailure implements Exception {
  const SignInFailure(this.message);
  final String message;
}

abstract class SocialAuthClient {
  Future<AuthProfile?> signIn(SocialProvider provider);
  void cancelSignIn();
}

/// Supabase authentication with local SQLite synchronization.
class SocialAuth implements SocialAuthClient {
  static bool get hasOAuthError {
    if (kIsWeb) {
      final uri = Uri.base;
      return uri.queryParameters.containsKey('error') ||
          uri.queryParameters.containsKey('error_description');
    }
    return false;
  }

  static String? get oAuthErrorDescription {
    if (kIsWeb) {
      final uri = Uri.base;
      final desc = uri.queryParameters['error_description'] ??
          uri.queryParameters['error'];
      if (desc != null && desc.isNotEmpty) {
        return desc;
      }
    }
    return null;
  }

  static bool get isOAuthRedirect {
    if (kIsWeb) {
      final uri = Uri.base;
      if (uri.queryParameters.containsKey('code') ||
          uri.fragment.contains('access_token') ||
          uri.fragment.contains('refresh_token')) {
        return true;
      }
    }
    return false;
  }

  static String normalizeSupabaseUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.endsWith('/rest/v1')) {
      trimmed = trimmed.substring(0, trimmed.length - '/rest/v1'.length);
    }
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static const String defaultSupabaseUrl =
      'https://jiscxdnqikbnxgyrvokc.supabase.co';
  static const String defaultSupabaseKey =
      'sb_publishable_Bkg0HqUoPk3rGH66COlwWw_yYO71nJk';

  static String get initialSupabaseUrl {
    const configured = String.fromEnvironment('SUPABASE_URL');
    if (configured.isNotEmpty) return normalizeSupabaseUrl(configured);
    return defaultSupabaseUrl;
  }

  static String get initialSupabaseKey {
    const configured = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (configured.isNotEmpty) return configured;
    return defaultSupabaseKey;
  }

  SocialAuth()
      : _url = initialSupabaseUrl,
        _key = initialSupabaseKey;
  final String _url;
  final String _key;

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
  String? get currentAuthProvider {
    final user = _client?.auth.currentUser;
    if (user == null) return null;
    if (user.identities != null && user.identities!.isNotEmpty) {
      final sorted = List<UserIdentity>.from(user.identities!)
        ..sort((a, b) {
          final timeA = DateTime.tryParse(a.lastSignInAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = DateTime.tryParse(b.lastSignInAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
      return sorted.first.provider;
    }
    return user.appMetadata['provider'] as String?;
  }
  SocialProvider? get currentSocialProvider {
    final provider = currentAuthProvider;
    if (provider == 'google') return SocialProvider.google;
    if (provider == 'azure') return SocialProvider.microsoft;
    if (provider == 'facebook') return SocialProvider.facebook;
    return null;
  }
  bool get isOAuthUser => currentSocialProvider != null;
  Completer<AuthProfile?>? _pending;
  Duration _timeout = const Duration(minutes: 3);

  @visibleForTesting
  Future<void> Function(String email, String password)? onSignUpForTesting;

  @visibleForTesting
  Future<void> Function(String email, String password)? onSignInForTesting;

  @visibleForTesting
  void emitIncomingSignInForTesting(AuthProfile profile) {
    _profile = profile;
    _incomingSignIns.add(profile);
  }

  @visibleForTesting
  SocialAuth.forTesting(
      {required Stream<AuthState> events,
      required Future<bool> Function(SocialProvider) launch,
      Duration timeout = const Duration(minutes: 3)})
      : _url = '',
        _key = '' {
    _timeout = timeout;
    _launch = launch;
    _listen(events);
  }

  Future<void> initialize() async {
    final url = _url;
    final key = _key;
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

  bool _isRegistering = false;

  void _listen(Stream<AuthState> events) {
    _subscription = events.listen((state) {
      if (_isRegistering) return;
      final session = state.session;
      final previousId = _profile?.id;
      _profile = session == null || session.isExpired
          ? null
          : AuthProfile.fromUser(session.user);
      if (_profile == null) return;
      if (session != null) {
        unawaited(_upsertLocalProfile(session.user));
      }
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
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('poise.oauth_in_progress', true);
      } catch (_) {}
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user.firstName');
    await prefs.remove('user.lastName');
    await prefs.remove('user.middleName');
    await prefs.remove('user.contactNumber');
    await prefs.remove('user.fullName');
    await prefs.remove('user.avatar');
    await prefs.remove('user.lastActiveId');
    await prefs.remove('user.lastAuthProvider');

    final bool bluetoothEnabled =
        prefs.getBool('poise.bluetoothEnabled') ?? true;
    final bool isConnected = PoiseBleService.instance.isConnected;
    final bool adapterOn = await PoiseBleService.instance.isBluetoothAdapterOn();
    await PoiseBleService.instance.disconnect();
    await DeviceSession.signedOut(
      adapterOn: adapterOn,
      bluetoothEnabled: bluetoothEnabled && isConnected,
    );
  }

  Future<void> signInWithPassword(String email, String password) async {
    final client = _client;
    if (client == null) {
      if (onSignInForTesting != null) {
        await onSignInForTesting!(email, password);
        return;
      }
      throw const SignInFailure('Account sign-in is not configured yet.');
    }
    try {
      final res = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.user != null) {
        _profile = AuthProfile.fromUser(res.user!);
        try {
          await getProfile();
        } catch (_) {}
        await _upsertLocalProfile(res.user!);
        _incomingSignIns.add(_profile!);
      }
    } on AuthException catch (error) {
      final msg = error.message.toLowerCase();
      if (msg.contains('email not confirmed')) {
        throw const SignInFailure(
            'Your email address is not confirmed yet. Please check your inbox for the confirmation email or reset your password.');
      }
      throw SignInFailure(error.message);
    }
  }

  /// Sign up with email and password, creating both a Supabase user and local profile.
  /// Does not automatically sign in so the user can enter credentials on the Sign In page.
  Future<void> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) async {
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    if (password.length < 8 || !hasLetter || !hasDigit) {
      throw const SignInFailure(
          'Password must be at least 8 characters long and contain both letters and numbers.');
    }

    final client = _client;
    if (client == null) {
      if (onSignUpForTesting != null) {
        await onSignUpForTesting!(email, password);
        return;
      }
      throw const SignInFailure('Account sign-up is not configured yet.');
    }
    _isRegistering = true;
    try {
      final res = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: fullName != null ? {'full_name': fullName} : null,
      );
      if (res.user != null) {
        // Auto-confirm email so the user can immediately sign in without leaving the app/browser
        try {
          await client.rpc('confirm_user_email', params: {
            'user_email': email.trim().toLowerCase(),
          });
        } catch (_) {}

        // If the email already exists in Supabase (e.g. from Google/Facebook/Microsoft OAuth),
        // identities is empty and no new password was set by signUp.
        if (res.user!.identities != null && res.user!.identities!.isEmpty) {
          try {
            await client.rpc('set_user_password', params: {
              'user_email': email.trim().toLowerCase(),
              'new_password': password,
            });
          } catch (_) {}
        }
        await _upsertLocalProfile(res.user!);
      }
      await client.auth.signOut(scope: SignOutScope.local);
      _profile = null;
    } on AuthException catch (error) {
      final msg = error.message.toLowerCase();
      if (msg.contains('already') ||
          msg.contains('registered') ||
          msg.contains('exists')) {
        try {
          await client.rpc('confirm_user_email', params: {
            'user_email': email.trim().toLowerCase(),
          });
          await client.rpc('set_user_password', params: {
            'user_email': email.trim().toLowerCase(),
            'new_password': password,
          });
          await client.auth.signOut(scope: SignOutScope.local);
          _profile = null;
          return;
        } catch (_) {}
      }
      throw SignInFailure(error.message);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _isRegistering = false;
    }
  }

  /// Deletes the user account permanently:
  /// 1. Verifies password credentials with Supabase Auth
  /// 2. Deletes all cloud telemetry and user account from Supabase
  /// 3. Clears all local database data
  /// 4. Clears SharedPreferences
  /// 5. Signs out and resets auth state
  Future<void> deleteAccount({String? password}) async {
    final client = _client;
    final currentUser = client?.auth.currentUser;
    final email = currentUser?.email ?? _profile?.email;
    final provider = currentUser?.appMetadata['provider'] as String?;
    final isOAuth = provider != null && provider != 'email';

    // Strict Password Validation for email/password users
    if (!isOAuth) {
      if (password == null || password.trim().isEmpty) {
        throw const SignInFailure('Password is required to delete your account.');
      }

      if (client != null && email != null) {
        try {
          await client.auth.signInWithPassword(
            email: email,
            password: password.trim(),
          );
        } catch (e) {
          throw const SignInFailure(
              'Incorrect password. Please verify your password and try again.');
        }
      }
    } else {
      if (password != null &&
          password.trim().isNotEmpty &&
          client != null &&
          email != null) {
        try {
          await client.auth.signInWithPassword(
            email: email,
            password: password.trim(),
          );
        } catch (_) {
          throw const SignInFailure(
              'Incorrect password. Please verify your credentials or re-authenticate.');
        }
      }
    }

    // 1. Delete from Supabase Cloud
    try {
      await SyncService.instance.deleteUserAccount();
    } catch (e) {
      throw SignInFailure(
          e.toString().replaceAll('Exception: ', '').replaceAll('SignInFailure: ', ''));
    }

    // 2. Delete from local SQLite database
    await PoiseLocalDatabase.instance.clearAllData();

    // 3. Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('poise.deviceId');
    await prefs.remove('poise.deviceName');
    await prefs.remove('poise.baseline');
    await prefs.remove('user.avatar');
    await prefs.remove('user.fullName');
    await prefs.remove('user.firstName');
    await prefs.remove('user.lastName');
    await prefs.remove('user.middleName');
    await prefs.remove('user.contactNumber');
    await prefs.remove('user.lastActiveId');

    // 4. Sign out
    await signOut();
  }

  /// Deletes account after confirming identity via OAuth provider (Google, Microsoft, Facebook).
  Future<void> deleteAccountWithOAuth(SocialProvider provider) async {
    final client = _client;
    if (client == null) {
      throw const SignInFailure('Account service is not initialized.');
    }

    final reauth = await signIn(provider);
    if (reauth == null) {
      throw const SignInFailure('Re-authentication was cancelled.');
    }

    await SyncService.instance.deleteUserAccount();
    await PoiseLocalDatabase.instance.clearAllData();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('poise.deviceId');
    await prefs.remove('poise.deviceName');
    await prefs.remove('poise.baseline');
    await prefs.remove('user.avatar');
    await prefs.remove('user.fullName');
    await prefs.remove('user.firstName');
    await prefs.remove('user.lastName');
    await prefs.remove('user.middleName');
    await prefs.remove('user.contactNumber');
    await prefs.remove('user.lastActiveId');

    await signOut();
  }

  /// Deletes all posture telemetry and records:
  /// - For authenticated user: deletes from Supabase Cloud and local database
  /// - For guest user: deletes from local database and clears guest cache
  Future<void> deleteAllData() async {
    final isGuest = _profile == null && _client?.auth.currentUser == null;

    if (!isGuest) {
      // Authenticated: Delete cloud data from Supabase
      await SyncService.instance.deleteAllCloudData();
    }

    // Clear local SQLite posture records
    await PoiseLocalDatabase.instance.clearPostureData();

    // Clear telemetry caches in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('poise.deviceId');
    await prefs.remove('poise.deviceName');
    await prefs.remove('poise.baseline');
  }

  /// Updates the authenticated user's password.
  /// Requires verifying their current password first for security.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(newPassword);
    final hasDigit = RegExp(r'[0-9]').hasMatch(newPassword);
    if (newPassword.length < 8 || !hasLetter || !hasDigit) {
      throw const SignInFailure(
          'Password must be at least 8 characters long and contain both letters and numbers.');
    }

    final client = _client;
    if (client == null) {
      throw const SignInFailure('Account service is not initialized.');
    }
    final email = client.auth.currentUser?.email ?? _profile?.email;
    if (email == null) {
      throw const SignInFailure('No logged-in user found.');
    }

    try {
      // 1. Verify current password by signing in
      await client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException catch (e) {
      throw SignInFailure('Current password is incorrect: ${e.message}');
    }

    try {
      // 2. Apply new password
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw SignInFailure(e.message);
    }
  }

  /// Updates full_name in Supabase Auth user metadata, public.profiles table,
  /// and local SQLite database. Triggers updated_at timestamp change in Supabase.
  Future<void> updateProfile({
    required String fullName,
    String? firstName,
    String? lastName,
    String? middleName,
    String? contactNumber,
  }) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client != null && user != null) {
      try {
        // 1. Update or upsert public.profiles in Supabase Cloud
        bool updatedInCloud = false;
        try {
          await client.from('profiles').upsert({
            'id': user.id,
            'full_name': fullName,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'id');
          updatedInCloud = true;
        } catch (e) {
          debugPrint('[SocialAuth] Upsert profiles error: $e. Falling back to direct update...');
        }

        if (!updatedInCloud) {
          try {
            await client.from('profiles').update({
              'full_name': fullName,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', user.id);
          } catch (e) {
            debugPrint('[SocialAuth] Direct update profiles error: $e');
          }
        }

        // 2. Update user metadata in Supabase Auth (best-effort)
        try {
          await client.auth.updateUser(
            UserAttributes(
              data: {
                'full_name': fullName,
                if (firstName != null) 'first_name': firstName,
                if (lastName != null) 'last_name': lastName,
                if (middleName != null) 'middle_name': middleName,
                if (contactNumber != null) 'contact_number': contactNumber,
              },
            ),
          );
        } catch (e) {
          debugPrint('[SocialAuth] Auth updateUser metadata error: $e');
        }

        // 3. Upsert local SQLite database on mobile, web, and desktop
        if (!PoiseBleService.instance.isTesting) {
          try {
            await PoiseLocalDatabase.instance.upsertProfile(
              ProfileModel(
                id: user.id,
                fullName: fullName,
                createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
          } catch (_) {}
        }

        // 4. Update cached AuthProfile in memory
        _profile = AuthProfile(
          id: user.id,
          displayName: fullName,
          email: user.email,
        );

        // 5. Update SharedPreferences cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user.fullName', fullName);
        if (firstName != null) await prefs.setString('user.firstName', firstName);
        if (lastName != null) await prefs.setString('user.lastName', lastName);
        if (middleName != null) await prefs.setString('user.middleName', middleName);
        if (contactNumber != null) await prefs.setString('user.contactNumber', contactNumber);
      } on SignInFailure {
        rethrow;
      } on PostgrestException catch (e) {
        throw SignInFailure(e.message);
      } catch (e) {
        throw SignInFailure(e.toString());
      }
    } else {
      if (_profile != null) {
        _profile = AuthProfile(
          id: _profile!.id,
          displayName: fullName,
          email: _profile!.email,
        );
      }
      if (!PoiseBleService.instance.isTesting) {
        try {
          await PoiseLocalDatabase.instance.upsertProfile(
            ProfileModel(
              id: _profile?.id ?? 'local_user',
              fullName: fullName,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        } catch (_) {}
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user.fullName', fullName);
      if (firstName != null) await prefs.setString('user.firstName', firstName);
      if (lastName != null) await prefs.setString('user.lastName', lastName);
      if (middleName != null) await prefs.setString('user.middleName', middleName);
      if (contactNumber != null) await prefs.setString('user.contactNumber', contactNumber);
    }
  }

  /// Fetches the latest profile from Supabase Cloud DB or local SQLite.
  Future<ProfileModel?> getProfile() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return null;
    try {
      final res = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (res != null) {
        final profile = ProfileModel.fromMap(res);
        await PoiseLocalDatabase.instance.upsertProfile(profile);
        if (profile.fullName != null && profile.fullName!.isNotEmpty) {
          _profile = AuthProfile(
            id: user.id,
            displayName: profile.fullName,
            email: user.email,
          );
        }
        return profile;
      }
    } catch (_) {}
    return await PoiseLocalDatabase.instance.getProfile(user.id);
  }

  Future<void> _upsertLocalProfile(User user) async {
    try {
      final resolvedName =
          AuthProfile.fromUser(user).displayName ?? user.email?.split('@').first;
      final createdAt = DateTime.tryParse(user.createdAt) ?? DateTime.now();
      final now = DateTime.now();

      if (!PoiseBleService.instance.isTesting) {
        await PoiseLocalDatabase.instance.upsertProfile(
          ProfileModel(
            id: user.id,
            fullName: resolvedName,
            createdAt: createdAt,
            updatedAt: now,
          ),
        );
      }

      final client = _client;
      if (client != null) {
        try {
          await client.from('profiles').upsert({
            'id': ensureUuid(user.id),
            'full_name': resolvedName,
            'created_at': createdAt.toUtc().toIso8601String(),
            'updated_at': now.toUtc().toIso8601String(),
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    cancelSignIn();
    await _subscription?.cancel();
    await _incomingSignIns.close();
    lastError.dispose();
  }
}
