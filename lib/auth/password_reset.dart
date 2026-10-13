import 'package:supabase_flutter/supabase_flutter.dart';

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

  GoTrueClient get _auth {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty || key.isEmpty) {
      throw const AuthException('Password reset is not configured yet.');
    }
    return _client ??= GoTrueClient(
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
    // Discard this in-memory recovery client; the app remains signed out.
    await dispose();
  }

  @override
  Future<void> dispose() async {
    _verified = false;
    _client?.dispose();
    _client = null;
  }
}
