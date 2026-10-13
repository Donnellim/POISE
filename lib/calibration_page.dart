import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'dashboard_page.dart';

import 'bluetooth/poise_ble_service.dart';

class CalibrationPage extends StatelessWidget {
  const CalibrationPage({super.key, this.isGuest = false});
  final bool isGuest;

  void _showCalibratedOverlay(BuildContext context) {
    PoiseBleService.instance.setZeroBaseline();
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF4DB6AC), // Deep Teal
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Checkmark Icon ──
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Color(0xFFB2DFDB), // Light teal circle
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Color(0xFF00796B), // Dark teal checkmark
                  size: 40,
                ),
              ),
              const SizedBox(height: 28),

              // ── Title ──
              const Text(
                'Baseline Established!',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // ── Subtitle ──
              const Text(
                'Your neutral posture has been set.\n'
                'You can now start monitoring your posture.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),

              // ── Proceed to Dashboard ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop(); // close dialog
                    // Navigate to dashboard and clear all previous routes
                    navigator.pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => DashboardPage(
                          isGuest: isGuest,
                          initialBluetoothConnected: true,
                        ),
                      ),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: const Text(
                    'Proceed to Dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
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

              // ── Posture Icon ──
              Image.asset(
                'assets/images/Zero_Baseline_Icon.png',
                width: effectiveWidth * 0.4,
                fit: BoxFit.contain,
              ),

              SizedBox(height: effectiveWidth * 0.1),

              // ── Title ──
              Text(
                'Set Your Neutral Posture',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: effectiveWidth * 0.07, // Scales gracefully
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // ── Description ──
              Text(
                'Sit manually with your back straight, shoulders relaxed,\n'
                'and head facing forward.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const Spacer(flex: 5),

              // ── Set Zero Baseline Button ──
              SizedBox(
                width: buttonWidth,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _showCalibratedOverlay(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: const Text(
                    'Set Zero Baseline',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Cancel Button ──
              SizedBox(
                width: buttonWidth,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF64A3F2), // Lighter blue
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
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
