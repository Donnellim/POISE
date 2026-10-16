import 'package:flutter/material.dart';
import '../session_entry_page.dart';
import 'social_auth.dart';

class SocialSignInButtons extends StatefulWidget {
  const SocialSignInButtons(
      {super.key,
      required this.width,
      this.createAccount = false,
      this.client,
      this.onAuthenticated});
  final double width;
  final bool createAccount;
  final SocialAuthClient? client;
  final ValueChanged<AuthProfile>? onAuthenticated;

  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  SocialProvider? _pending;
  String? _error;

  @override
  void dispose() {
    if (_pending != null) {
      (widget.client ?? SocialAuth.instance).cancelSignIn();
    }
    super.dispose();
  }

  Future<void> _signIn(SocialProvider provider) async {
    if (_pending != null) return;
    setState(() {
      _pending = provider;
      _error = null;
    });
    try {
      final profile =
          await (widget.client ?? SocialAuth.instance).signIn(provider);
      if (!mounted || profile == null) return;
      if (widget.onAuthenticated != null) {
        widget.onAuthenticated!(profile);
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const SessionEntryPage()),
          (_) => false,
        );
      }
    } on SignInFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Sign-in is unavailable right now. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        child: Column(children: [
          for (final provider in SocialProvider.values) ...[
            if (provider != SocialProvider.google) const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _pending == null ? () => _signIn(provider) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF80DEEA),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Colors.black)),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_pending == provider)
                    const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Image.asset('assets/images/${_name(provider)}_Icon.png',
                        width: 24, height: 24),
                  const SizedBox(width: 10),
                  Flexible(
                      child: Text(
                          '${widget.createAccount ? 'Continue' : 'Sign In'} with ${_name(provider)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold))),
                ]),
              ),
            ),
          ],
          if (_pending != null)
            TextButton(
              onPressed: () =>
                  (widget.client ?? SocialAuth.instance).cancelSignIn(),
              child: const Text('Cancel sign-in'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF8B1420), fontSize: 13))),
            ),
        ]),
      );

  String _name(SocialProvider provider) => switch (provider) {
        SocialProvider.google => 'Google',
        SocialProvider.facebook => 'Facebook',
        SocialProvider.microsoft => 'Microsoft',
      };
}
