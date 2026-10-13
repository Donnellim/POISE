import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'bluetooth_connect_page.dart';

class GetStartedPage extends StatelessWidget {
  const GetStartedPage({super.key, this.isGuest = false});
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double effectiveWidth = screenSize.width > 500 ? 500 : screenSize.width;
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
              
              const Spacer(flex: 2),

              // ── Title ──
              Text(
                "Let's Get Started",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: effectiveWidth * 0.115, // Scales to match mockup
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),

              // ── Description ──
              Text(
                'Bluetooth access is required to connect to your\nP.O.I.S.E. device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const Spacer(flex: 6),

              // ── Connect to Bluetooth Button ──
              SizedBox(
                width: buttonWidth,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BluetoothConnectPage(isGuest: isGuest),
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
                    'Connect to Bluetooth',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}