import 'package:supabase_flutter/supabase_flutter.dart';
import 'social_auth.dart';

abstract class PasswordResetClient {
  Future<void> sendCode(String email);
  Future<void> verifyCode(String email, String code);
  Future<void> resetPassword(String password);
  Future<void> dispose();
}

/// Recovery sessions are intentionally isolated from persisted app sign-in.
class SupabasePasswordReset implements PasswordResetClient {
  GoTrueClient? _client;
  bool _verified = false;
  bool _isSharedAuth = false;

  GoTrueClient get _auth {
    if (_client != null) return _client!;
    try {
      final supa = Supabase.instance.client;
      _isSharedAuth = true;
      return _client = supa.auth;
    } catch (_) {}
    var url = const String.fromEnvironment('SUPABASE_URL');
    var key = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty) url = SocialAuth.defaultSupabaseUrl;
    if (key.isEmpty) key = SocialAuth.defaultSupabaseKey;
    url = SocialAuth.normalizeSupabaseUrl(url);
    if (url.isEmpty || key.isEmpty) {
      throw const AuthException('Password reset is not configured yet.');
    }
    _isSharedAuth = false;
    return _client = GoTrueClient(
      url: '$url/auth/v1',
      headers: {'apikey': key, 'Authorization': 'Bearer $key'},
      autoRefreshToken: false,
      flowType: AuthFlowType.implicit,
    );
  }

  @override
  Future<void> sendCode(String email) async {
    _verified = false;
    await _auth.resetPasswordForEmail(email);
  }

  @override
  Future<void> verifyCode(String email, String code) async {
    _verified = false;
    final response = await _auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
    _verified = response.session != null;
    if (!_verified) throw const AuthException('Please request a new code.');
  }

  @override
  Future<void> resetPassword(String password) async {
    if (!_verified) throw const AuthException('Verify your email first.');
    await _auth.updateUser(UserAttributes(password: password));
    _verified = false;
    // Discard recovery client; the app remains signed out.
    await dispose();
  }

  @override
  Future<void> dispose() async {
    _verified = false;
    if (!_isSharedAuth) {
      _client?.dispose();
    }
    _client = null;
  }
}
