import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'dashboard_page.dart';
import 'bluetooth/poise_ble_service.dart';

class GetStartedPage extends StatefulWidget {
  const GetStartedPage({super.key, this.isGuest = false});
  final bool isGuest;

  @override
  State<GetStartedPage> createState() => _GetStartedPageState();
}

class _GetStartedPageState extends State<GetStartedPage> {
  bool _isConnecting = false;
  String _statusMessage = '';
  Timer? _searchTimer;
  StreamSubscription<List<PoiseDiscoveredDevice>>? _scanSub;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scanSub?.cancel();
    unawaited(PoiseBleService.instance.stopScan());
    super.dispose();
  }

  Future<void> _handleConnect() async {
    if (_isConnecting) return;
    _searchTimer?.cancel();
    _scanSub?.cancel();

    final ble = PoiseBleService.instance;

    if (!await ble.requestBluetoothPermissions()) {
      if (mounted) {
        setState(() => _statusMessage =
            'Allow Nearby devices (or Location on older phones) in app permissions, then try again.');
      }
      return;
    }

    // 1. Check whether phone system Bluetooth is turned ON
    final isAdapterOn = await ble.isBluetoothAdapterOn();
    if (!isAdapterOn && mounted) {
      final allowed = await _promptEnablePhoneBluetooth();
      if (!allowed) {
        setState(() {
          _isConnecting = false;
          _statusMessage =
              'Bluetooth must be enabled to connect to your P.O.I.S.E. device.';
        });
        return;
      }
    }

    if (!mounted) return;

    // 2. Check if already connected or synced via Quick Settings panel
    if (await ble.checkAndConnectSystemDevice() || ble.isConnected) {
      if (!mounted) return;
      _showConnectedDialog(deviceName: ble.connectedDeviceName);
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Searching for nearby P.O.I.S.E. devices...';
    });

    // 3. Start scanning for nearby POISE devices
    await ble.startScan();

    _scanSub = ble.scanResultsStream.listen((devices) async {
      if (!mounted || !_isConnecting) return;
      if (devices.isEmpty) return;

      // Prioritize devices matching POISE name prefixes
      final poiseTarget = devices.cast<PoiseDiscoveredDevice?>().firstWhere(
            (d) => d != null && PoiseBleConfig.isPoiseDeviceName(d.name),
            orElse: () => null,
          );

      if (poiseTarget != null) {
        _searchTimer?.cancel();
        await _connectToDevice(poiseTarget);
      }
    });

    // 4. Auto-connect timer fallback for fast discovery / automated tests
    _searchTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || !_isConnecting) return;
      final devices = ble.discoveredDevices;
      final target = devices.cast<PoiseDiscoveredDevice?>().firstWhere(
            (d) => d != null && PoiseBleConfig.isPoiseDeviceName(d.name),
            orElse: () => null,
          );

      if (target != null) {
        await _connectToDevice(target);
      } else {
        await ble.stopScan();
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
          _statusMessage =
              'No P.O.I.S.E. device found. Make sure your device is turned on and try again.';
        });
      }
    });
  }

  Future<void> _connectToDevice(PoiseDiscoveredDevice target) async {
    _searchTimer?.cancel();
    _scanSub?.cancel();
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Connecting to ${target.name}...';
    });

    final ok = await PoiseBleService.instance.connect(target);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _isConnecting = false;
        _statusMessage = '';
      });
      _showConnectedDialog(deviceName: target.name);
    } else {
      setState(() {
        _isConnecting = false;
        _statusMessage =
            'Connection failed. Please ensure your device is nearby and try again.';
      });
    }
  }

  Future<bool> _promptEnablePhoneBluetooth() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: const Color(0xFFDCEEF6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: const [
                Icon(Icons.bluetooth_disabled_rounded,
                    color: Color(0xFF4285F4), size: 28),
                SizedBox(width: 10),
                Text(
                  'Turn On Bluetooth',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
              ],
            ),
            content: const Text(
              'Bluetooth is turned off in your phone settings.\nPlease enable Bluetooth on your phone to scan for your P.O.I.S.E. monitoring device.',
              style:
                  TextStyle(fontSize: 13.5, height: 1.4, color: Colors.black87),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.black54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final enabled =
                      await PoiseBleService.instance.requestEnableBluetooth();
                  if (dialogCtx.mounted) {
                    Navigator.of(dialogCtx).pop(enabled || kIsWeb);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Turn On'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showConnectedDialog({String? deviceName}) {
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
              Text(
                'Connected to ${deviceName ?? "P.O.I.S.E."}\ndevice',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 36),

              // ── Proceed to Dashboard ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // close dialog
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DashboardPage(isGuest: widget.isGuest),
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
              // Back Button (if navigated from setup)
              if (Navigator.of(context).canPop())
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.black, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                )
              else
                const SizedBox(height: 12),

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

              if (_statusMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusMessage.contains('failed') ||
                              _statusMessage.contains('No P.O.I.S.E.')
                          ? Colors.red.shade700
                          : const Color(0xFF073344),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              const Spacer(flex: 6),

              // ── Connect to Bluetooth Button ──
              SizedBox(
                width: buttonWidth,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _handleConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue, // Deep blue
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.blue.withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: _isConnecting
                      ? const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Connecting...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const Text(
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
