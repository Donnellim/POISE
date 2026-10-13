import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/password_reset.dart';
import 'widgets/gradient_background.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.initialEmail = '', this.client});
  final String initialEmail;
  final PasswordResetClient? client;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final _client = widget.client ?? SupabasePasswordReset();
  int _step = 0;
  int _cooldown = 0;
  bool _busy = false;
  bool _hidden = true;
  String? _error;
  Timer? _timer;

  void _startCooldown() {
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cooldown--);
      if (_cooldown == 0) timer.cancel();
    });
  }

  Future<void> _submit({bool resend = false}) async {
    if (_busy || (!resend && !_form.currentState!.validate())) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_step == 0 || resend) {
        await _client.sendCode(_email.text.trim());
        if (!mounted) return;
        _code.clear();
        _startCooldown();
        setState(() => _step = 1);
      } else if (_step == 1) {
        await _client.verifyCode(_email.text.trim(), _code.text.trim());
        if (!mounted) return;
        setState(() => _step = 2);
      } else {
        await _client.resetPassword(_password.text);
        if (!mounted) return;
        Navigator.of(context).pop(_email.text.trim());
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Unable to continue. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_client.dispose());
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Forgot password?', 'Verify your email', 'Reset password'];
    return PopScope(
      canPop: !_busy,
      child: GradientBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(backgroundColor: Colors.transparent),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Theme(
                    data: ThemeData.light().copyWith(
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: const Color(0xFFB2EBF2),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                    child: Material(
                      color: const Color(0xFFD6EAF8),
                      borderRadius: BorderRadius.circular(28),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Step ${_step + 1} of 3',
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              Text(titles[_step],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              Text(
                                  _step == 0
                                      ? 'Enter your account email to request a verification code.'
                                      : _step == 1
                                          ? 'If an account exists for ${_email.text.trim()}, a code will be sent. Check your inbox and spam folder.'
                                          : 'Choose a new password with at least 8 characters, including letters and numbers.',
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 24),
                              if (_step == 0)
                                TextFormField(
                                  key: const ValueKey('reset-email'),
                                  controller: _email,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration:
                                      const InputDecoration(labelText: 'Email'),
                                  validator: (value) =>
                                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                              .hasMatch(value!.trim())
                                          ? null
                                          : 'Enter a valid email address.',
                                ),
                              if (_step == 1) ...[
                                TextFormField(
                                  key: const ValueKey('reset-code'),
                                  controller: _code,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode
                                  ],
                                  decoration: const InputDecoration(
                                      labelText: 'Verification code'),
                                  validator: (value) => RegExp(r'^\d{6,10}$')
                                          .hasMatch(value!.trim())
                                      ? null
                                      : 'Enter the code from your email.',
                                ),
                                TextButton(
                                    onPressed: _busy || _cooldown > 0
                                        ? null
                                        : () => _submit(resend: true),
                                    child: Text(_cooldown > 0
                                        ? 'Resend code in ${_cooldown}s'
                                        : 'Resend code')),
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                              _step = 0;
                                              _error = null;
                                            }),
                                    child: const Text('Use a different email')),
                              ],
                              if (_step == 2) ...[
                                TextFormField(
                                  key: const ValueKey('reset-password'),
                                  controller: _password,
                                  enabled: !_busy,
                                  obscureText: _hidden,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                      labelText: 'New password',
                                      suffixIcon: IconButton(
                                          onPressed: () => setState(
                                              () => _hidden = !_hidden),
                                          tooltip: _hidden
                                              ? 'Show password'
                                              : 'Hide password',
                                          icon: Icon(_hidden
                                              ? Icons.visibility_off
                                              : Icons.visibility))),
                                  validator: (value) => value!.length >= 8 &&
                                          RegExp('[a-zA-Z]').hasMatch(value) &&
                                          RegExp('[0-9]').hasMatch(value)
                                      ? null
                                      : 'Use 8+ characters with letters and numbers.',
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  key: const ValueKey('reset-confirm'),
                                  controller: _confirm,
                                  enabled: !_busy,
                                  obscureText: _hidden,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                      labelText: 'Confirm new password'),
                                  validator: (value) => value == _password.text
                                      ? null
                                      : 'Passwords do not match.',
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                Text(_error!,
                                    style: const TextStyle(color: Colors.red),
                                    semanticsLabel: _error),
                              ],
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : Text([
                                        'Send code',
                                        'Verify code',
                                        'Reset password'
                                      ][_step]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
