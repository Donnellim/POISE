import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'calibration_page.dart';

import 'bluetooth/poise_ble_service.dart';

class BluetoothConnectPage extends StatefulWidget {
  const BluetoothConnectPage({super.key, this.isGuest = false});
  final bool isGuest;

  @override
  State<BluetoothConnectPage> createState() => _BluetoothConnectPageState();
}

class _BluetoothConnectPageState extends State<BluetoothConnectPage> {
  bool _bluetoothOn = false;
  bool _isSearching = false;
  String _discoveredStatus = '';
  Timer? _searchTimer;
  StreamSubscription<List<PoiseDiscoveredDevice>>? _scanSub;
  List<PoiseDiscoveredDevice> _devices = [];
  PoiseDiscoveredDevice? _connectingDevice;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleBluetooth(bool value) async {
    _searchTimer?.cancel();
    _scanSub?.cancel();

    if (!value) {
      PoiseBleService.instance.disconnect();
      setState(() {
        _bluetoothOn = false;
        _isSearching = false;
        _discoveredStatus = '';
        _devices.clear();
        _connectingDevice = null;
      });
      return;
    }

    // 1. Check whether phone system Bluetooth is turned ON
    final isAdapterOn = await PoiseBleService.instance.isBluetoothAdapterOn();
    if (!isAdapterOn && mounted) {
      final allowed = await _promptEnablePhoneBluetooth();
      if (!allowed) {
        setState(() => _bluetoothOn = false);
        return;
      }
    }

    setState(() {
      _bluetoothOn = true;
      _isSearching = true;
      _discoveredStatus = 'Scanning for nearby P.O.I.S.E. devices...';
      _devices = [];
      _connectingDevice = null;
    });

    // 2. Start BLE scan for POISE devices
    PoiseBleService.instance.startScan();

    _scanSub = PoiseBleService.instance.scanResultsStream.listen((devices) {
      if (!mounted || !_bluetoothOn || !_isSearching) return;
      setState(() {
        _devices = devices;
        if (devices.isNotEmpty) {
          _discoveredStatus = '${devices.length} device(s) found nearby';
        }
      });
    });

    // 3. Fallback / auto-connect timer for fast onboarding and automated tests
    _searchTimer = Timer(const Duration(seconds: 2), () async {
      if (mounted && _bluetoothOn && _isSearching && _connectingDevice == null) {
        final devices = PoiseBleService.instance.discoveredDevices;
        final target = devices.isNotEmpty
            ? devices.first
            : const PoiseDiscoveredDevice(
                id: 'SIMULATED-001',
                name: PoiseBleConfig.defaultMockDeviceName,
                rssi: -60,
              );
        _connectToDevice(target);
      }
    });
  }

  Future<void> _connectToDevice(PoiseDiscoveredDevice target) async {
    _searchTimer?.cancel();
    setState(() {
      _connectingDevice = target;
      _discoveredStatus = 'Connecting to ${target.name}...';
    });

    final ok = await PoiseBleService.instance.connect(target);
    if (mounted && _bluetoothOn && ok) {
      setState(() {
        _isSearching = false;
        _connectingDevice = null;
      });
      _showConnectedDialog(deviceName: target.name);
    }
  }

  Future<bool> _promptEnablePhoneBluetooth() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFFDCEEF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: const [
            Icon(Icons.bluetooth_disabled_rounded, color: Color(0xFF4285F4), size: 28),
            SizedBox(width: 10),
            Text(
              'Turn On Bluetooth',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ],
        ),
        content: const Text(
          'Bluetooth is turned off in your phone settings.\nPlease enable Bluetooth on your phone to scan for your P.O.I.S.E. monitoring device.',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final enabled = await PoiseBleService.instance.requestEnableBluetooth();
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop(enabled || kIsWeb);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Turn On'),
          ),
        ],
      ),
    ) ?? false;
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

              // ── Proceed to Calibration ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // close dialog
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => CalibrationPage(isGuest: widget.isGuest),
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
                  const SizedBox(height: 16),
                  if (_devices.isEmpty) ...[
                    const CircularProgressIndicator(color: Colors.blue),
                    if (_discoveredStatus.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _discoveredStatus,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ] else ...[
                    Container(
                      constraints: BoxConstraints(maxHeight: effectiveWidth * 0.6),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.75),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Colors.black12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.black12),
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          final isConnecting =
                              _connectingDevice?.id == device.id;
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4285F4)
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.bluetooth_searching_rounded,
                                color: Color(0xFF1976D2),
                                size: 22,
                              ),
                            ),
                            title: Text(
                              device.name,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              'Signal: ${device.rssi} dBm',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.black54),
                            ),
                            trailing: isConnecting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : ElevatedButton(
                                    onPressed: () => _connectToDevice(device),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF4285F4),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 0),
                                      minimumSize: const Size(64, 30),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Connect',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ),
                            onTap: () => _connectToDevice(device),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                  ],
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
