import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'create_account_page.dart';
import 'sign_in_page.dart';
import 'device_check_page.dart';

class OptionPage extends StatelessWidget {
  const OptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;

    // Cap the effective width so it doesn't blow up on wide desktop/web screens!
    final double effectiveWidth =
        screenSize.width > 500 ? 500 : screenSize.width;

    final double buttonWidth = effectiveWidth * 0.8;

    return GradientBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // ── Logo ──
              Image.asset(
                'assets/images/P.O.I.S.E. Logo 1.png',
                width: effectiveWidth * 0.45,
              ),
              const SizedBox(height: 8),

              // ── Title ──
              Text(
                'P.O.I.S.E.',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: effectiveWidth *
                      0.18, // Scales to be huge on mobile, capped on web
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),

              const Spacer(flex: 4),

              // ── Create Account Button ──
              SizedBox(
                width: buttonWidth,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateAccountPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue, // Deep blue
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Sign In Button ──
              SizedBox(
                width: buttonWidth,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SignInPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF64A3F2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // ── Continue as Guest ──
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const DeviceCheckPage(isGuest: true),
                  ));
                },
                child: const Text(
                  'Continue as guest',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
