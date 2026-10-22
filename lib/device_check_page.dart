import 'package:flutter/material.dart';
import 'bluetooth/poise_ble_service.dart';

import 'widgets/gradient_background.dart';
import 'device_setup_page.dart';
import 'dashboard_page.dart';

class DeviceCheckPage extends StatefulWidget {
  const DeviceCheckPage({super.key, this.isGuest = false});
  final bool isGuest;

  @override
  State<DeviceCheckPage> createState() => _DeviceCheckPageState();
}

class _DeviceCheckPageState extends State<DeviceCheckPage> {
  bool _needsDevice = false;

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(flex: 12),

                    // ── Question ──
                    const Text(
                      'Do you have\na P.O.I.S.E.?',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),

                    const Spacer(flex: 3),

                    if (_needsDevice) ...[
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'A P.O.I.S.E. device is required to continue. When you have your device, choose Yes to set up the connection.',
                          style:
                              TextStyle(color: Color(0xFF073344), fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Yes / No Buttons ──
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () async {
                                final ble = PoiseBleService.instance;
                                if (ble.isConnected ||
                                    await ble.checkAndConnectSystemDevice()) {
                                  if (!context.mounted) return;
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => DashboardPage(
                                          isGuest: widget.isGuest),
                                    ),
                                  );
                                } else {
                                  if (!context.mounted) return;
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => DeviceSetupPage(
                                          isGuest: widget.isGuest),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  side: const BorderSide(
                                      color: Colors.black, width: 1),
                                ),
                              ),
                              child: const Text(
                                'Yes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                if (widget.isGuest) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const DashboardPage(
                                        initialBluetoothConnected: false,
                                        isGuest: true,
                                      ),
                                    ),
                                  );
                                } else {
                                  setState(() => _needsDevice = true);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF64A3F2),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  side: const BorderSide(color: Colors.black),
                                ),
                              ),
                              child: const Text(
                                'No',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                )),
              ),
            );
          }),
        ),
      ),
    );
  }
}
