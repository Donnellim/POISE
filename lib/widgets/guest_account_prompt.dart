import 'package:flutter/material.dart';
import '../create_account_page.dart';
import '../sign_in_page.dart';
import '../device_check_page.dart';

/// Keeps the disconnected dashboard visible while explaining the next step.
class GuestAccountPrompt extends StatelessWidget {
  const GuestAccountPrompt({super.key});

  @override
  Widget build(BuildContext context) => Stack(children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Material(
            color: const Color(0xFFB0E0EF),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.person_add_alt_1,
                    size: 40, color: Color(0xFF073344)),
                const SizedBox(height: 16),
                const Text('Welcome to P.O.I.S.E.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF073344),
                        fontSize: 23,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                    'Create an account or sign in to continue. Then we will help you connect your P.O.I.S.E. device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF073344), fontSize: 15, height: 1.4)),
                const SizedBox(height: 24),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const CreateAccountPage())),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF388AF6),
                          foregroundColor: Colors.white),
                      child: const Text('Create Account'),
                    )),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const SignInPage())),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF073344)),
                      child: const Text('Sign In'),
                    )),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              const DeviceCheckPage(isGuest: true))),
                  child: const Text('Back to device check',
                      style: TextStyle(color: Color(0xFF073344))),
                ),
              ]),
            ),
          ),
        )),
      ]);
}
