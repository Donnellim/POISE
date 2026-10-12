import 'dart:async';
import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'calibration_page.dart';

class BluetoothConnectPage extends StatefulWidget {
  const BluetoothConnectPage({super.key});

  @override
  State<BluetoothConnectPage> createState() => _BluetoothConnectPageState();
}

class _BluetoothConnectPageState extends State<BluetoothConnectPage> {
  bool _bluetoothOn = false;
  bool _isSearching = false;
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _toggleBluetooth(bool value) {
    _searchTimer?.cancel();

    setState(() {
      _bluetoothOn = value;
    });

    if (value) {
      // Simulate searching for device
      setState(() => _isSearching = true);

      // Simulate finding and connecting to device after 2 seconds
      _searchTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _bluetoothOn) {
          setState(() => _isSearching = false);
          _showConnectedDialog();
        }
      });
    } else {
      setState(() => _isSearching = false);
    }
  }

  void _showConnectedDialog() {
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
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
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
                'Connected to P.O.I.S.E.\ndevice',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 36),

              // ── Proceed to Calibration ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // close dialog
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const CalibrationPage(),
                      ),
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
                    'Proceed to Calibration',
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

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: effectiveWidth * 0.08),
            child: Column(
              children: [
                const Spacer(flex: 3),

                // ── Bluetooth Icon ──
                Image.asset(
                  'assets/images/Bluetooth.png',
                  width: effectiveWidth * 0.4,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: effectiveWidth * 0.1),

                // ── Title ──
                Text(
                  _isSearching
                      ? 'Searching for\nP.O.I.S.E. device...'
                      : 'Please turn on Bluetooth\nto connect your device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: effectiveWidth * 0.065, // Scales text gracefully
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),

                if (_isSearching) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: Colors.blue),
                ],

                const Spacer(flex: 5),

                // ── Minimalist Custom Bluetooth Toggle ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      key: const Key('bluetooth-toggle'),
                      onTap: () => _toggleBluetooth(!_bluetoothOn),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: 40,
                        height: 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10), // Pill shape
                          color: _bluetoothOn
                              ? Colors.blue
                              : Colors.black, // Blue when ON, Black when OFF
                        ),
                        child: Stack(
                          children: [
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              top: 3,
                              bottom: 3,
                              // Sliding logic (Left: 23px when ON to push to right side)
                              left: _bluetoothOn ? 23 : 3,
                              right: _bluetoothOn ? 3 : 23,
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white, // The tiny white dot
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
