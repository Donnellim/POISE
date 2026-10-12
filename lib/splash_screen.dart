import 'dart:async';
import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'walkthrough_page.dart';
import 'auth/social_auth.dart';
import 'device_check_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;

  late AnimationController _fadeOutController;
  late Animation<double> _fadeOutAnimation;

  @override
  void initState() {
    super.initState();

    // ── Phase 1: Fade IN the logo (0 → 1.5s) ──
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeIn,
    );
    _fadeInController.forward();

    // ── Phase 2: Fade OUT the splash (at 4.2s, over 800ms) ──
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeOutAnimation = CurvedAnimation(
      parent: _fadeOutController,
      curve: Curves.easeOut,
    );

    // Start fade-out shortly before navigating so it feels seamless
    Timer(const Duration(milliseconds: 4200), () {
      if (mounted) {
        _fadeOutController.forward();
      }
    });

    // ── Navigate to walkthrough after 5 seconds ──
    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                SocialAuth.instance.user == null
                    ? const WalkthroughPage()
                    : const DeviceCheckPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double effectiveWidth =
        screenSize.width > 500 ? 500 : screenSize.width;

    return GradientBackground(
      child: Center(
        child: FadeTransition(
          opacity: _fadeInAnimation,
          child: AnimatedBuilder(
            animation: _fadeOutController,
            builder: (context, child) {
              return Opacity(
                opacity: 1.0 - _fadeOutAnimation.value,
                child: child,
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo Image ──
                Image.asset(
                  'assets/images/P.O.I.S.E. Logo 1.png',
                  width: effectiveWidth * 0.45,
                ),
                const SizedBox(height: 8),
                Text(
                  'P.O.I.S.E.',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: effectiveWidth * 0.18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
