import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Configuration for POISE Bluetooth Low Energy (BLE) communication.
///
/// NOTE: Once your firmware developer defines the final UUIDs or data formats,
/// simply update the constants in this class.
class PoiseBleConfig {
  /// Primary GATT Service UUID for the POISE Peripheral.
  /// (Default: standard 16-bit custom service 0xFFE0 in 128-bit form)
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

  /// GATT Characteristic UUID for real-time posture pitch angle telemetry (Read/Notify).
  static const String postureCharacteristicUuid =
      '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// GATT Characteristic UUID for zero baseline calibration or tare command (Write).
  static const String calibrationCharacteristicUuid =
      '0000ffe2-0000-1000-8000-00805f9b34fb';

  /// Advertised name prefixes identifying POISE hardware.
  static const List<String> deviceNamePrefixes = [
    'POISE',
    'POISE-BLE',
    'POISE_DEVICE'
  ];

  /// Default mock device identifier for preview and simulation.
  static const String defaultMockDeviceName = 'POISE-BLE-8492';
}

/// Represents a discovered POISE peripheral during BLE scanning.
class PoiseDiscoveredDevice {
  const PoiseDiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.rawDevice,
  });

  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice? rawDevice;

  @override
  String toString() => '$name ($id, RSSI: $rssi dBm)';
}

/// Connection lifecycle states for the POISE BLE monitoring system.
enum PoiseBleState {
  disconnected,
  scanning,
  connecting,
  connected,
}

/// Central Bluetooth Low Energy (BLE) service for scanning, connecting,
/// and streaming live posture data from the POISE hardware.
class PoiseBleService {
  PoiseBleService._();
  static final PoiseBleService instance = PoiseBleService._();

  // ── State streams ──
  final _connectionStateController =
      StreamController<PoiseBleState>.broadcast();
  Stream<PoiseBleState> get connectionStateStream =>
      _connectionStateController.stream;

  final _isConnectedController = StreamController<bool>.broadcast();
  Stream<bool> get isConnectedStream => _isConnectedController.stream;

  final _scanResultsController =
      StreamController<List<PoiseDiscoveredDevice>>.broadcast();
  Stream<List<PoiseDiscoveredDevice>> get scanResultsStream =>
      _scanResultsController.stream;

  final _pitchAngleController = StreamController<double>.broadcast();
  Stream<double> get pitchAngleStream => _pitchAngleController.stream;

  // ── Current cached states ──
  PoiseBleState _state = PoiseBleState.disconnected;
  PoiseBleState get state => _state;
  bool get isConnected => _state == PoiseBleState.connected;

  String? _connectedDeviceName;
  String? get connectedDeviceName => _connectedDeviceName;

  double _currentPitchAngle = 0.0;
  double get currentPitchAngle => _currentPitchAngle;

  double _zeroBaselineOffset = 0.0;
  double get zeroBaselineOffset => _zeroBaselineOffset;

  // ── BLE Internal Objects ──
  BluetoothDevice? _activeDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;
  StreamSubscription<List<int>>? _charValueSubscription;
  BluetoothCharacteristic? _calibrationChar;

  Timer? _mockStreamTimer;
  final List<PoiseDiscoveredDevice> _discoveredDevices = [];
  List<PoiseDiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  /// Check whether the current platform supports BLE hardware.
  Future<bool> isBleSupported() async {
    try {
      if (kIsWeb) return false;
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Check whether the phone's physical Bluetooth adapter is turned on.
  Future<bool> isBluetoothAdapterOn() async {
    try {
      if (kIsWeb) return true; // Web / localhost testing uses simulated BLE flow
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) return true; // Unit test/headless/desktop runner fallback
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return true; // Graceful fallback
    }
  }

  /// Request the OS to turn on the phone's Bluetooth adapter (prompt on Android).
  Future<bool> requestEnableBluetooth() async {
    try {
      if (kIsWeb) return true; // Web / localhost testing consent granted
      await FlutterBluePlus.turnOn();
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return true;
    }
  }

  /// Stream of phone system Bluetooth adapter states.
  Stream<BluetoothAdapterState> get adapterStateStream {
    try {
      return FlutterBluePlus.adapterState;
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Start scanning for nearby POISE devices.
  Future<void> startScan({Duration timeout = const Duration(seconds: 4)}) async {
    _discoveredDevices.clear();
    _scanResultsController.add(_discoveredDevices);
    _setState(PoiseBleState.scanning);

    final supported = await isBleSupported();
    if (!supported) {
      // Hardware unavailable (or unit test/desktop environment):
      // Gracefully simulate discovering the POISE device so the app is always testable.
      _discoveredDevices.add(const PoiseDiscoveredDevice(
        id: 'SIMULATED-POISE-001',
        name: PoiseBleConfig.defaultMockDeviceName,
        rssi: -58,
      ));
      _scanResultsController.add(List.unmodifiable(_discoveredDevices));
      return;
    }

    try {
      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        bool updated = false;
        for (final result in results) {
          final advName = result.advertisementData.advName;
          final devName = result.device.platformName;
          final effectiveName = advName.isNotEmpty ? advName : devName;

          final matchesPrefix = PoiseBleConfig.deviceNamePrefixes.any(
            (prefix) => effectiveName.toUpperCase().contains(prefix.toUpperCase()),
          );

          if (matchesPrefix || effectiveName.isNotEmpty) {
            final exists = _discoveredDevices.any((d) => d.id == result.device.remoteId.str);
            if (!exists) {
              _discoveredDevices.add(PoiseDiscoveredDevice(
                id: result.device.remoteId.str,
                name: effectiveName.isNotEmpty ? effectiveName : 'POISE Device',
                rssi: result.rssi,
                rawDevice: result.device,
              ));
              updated = true;
            }
          }
        }
        if (updated) {
          _scanResultsController.add(List.unmodifiable(_discoveredDevices));
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      debugPrint('[PoiseBleService] startScan failed: $e');
      // Fallback to simulated mock device
      if (_discoveredDevices.isEmpty) {
        _discoveredDevices.add(const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-001',
          name: PoiseBleConfig.defaultMockDeviceName,
          rssi: -60,
        ));
        _scanResultsController.add(List.unmodifiable(_discoveredDevices));
      }
    }
  }

  /// Stop the active BLE scan.
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSubscription?.cancel();
    if (_state == PoiseBleState.scanning) {
      _setState(PoiseBleState.disconnected);
    }
  }

  /// Connect to a discovered POISE peripheral.
  Future<bool> connect(PoiseDiscoveredDevice device) async {
    await stopScan();
    _setState(PoiseBleState.connecting);

    if (device.rawDevice == null) {
      // Simulated / Mock connection
      _connectedDeviceName = device.name;
      _currentPitchAngle = 0.0;
      _pitchAngleController.add(0.0);
      _setState(PoiseBleState.connected);
      return true;
    }

    final rawDevice = device.rawDevice!;
    _activeDevice = rawDevice;

    try {
      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = rawDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      await rawDevice.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );
      _connectedDeviceName = device.name;

      // Discover GATT services and posture telemetry characteristic
      await _discoverServices(rawDevice);

      _setState(PoiseBleState.connected);
      return true;
    } catch (e) {
      debugPrint('[PoiseBleService] Connect error: $e');
      _handleDisconnection();
      return false;
    }
  }

  /// Discovers GATT services and subscribes to the posture telemetry stream.
  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? telemetryChar;

      for (final service in services) {
        final sUuid = service.uuid.toString().toLowerCase();
        for (final char in service.characteristics) {
          final cUuid = char.uuid.toString().toLowerCase();

          // Check if matches configured telemetry characteristic or has notify property
          if (cUuid == PoiseBleConfig.postureCharacteristicUuid.toLowerCase() ||
              sUuid == PoiseBleConfig.serviceUuid.toLowerCase()) {
            if (char.properties.notify || char.properties.indicate) {
              telemetryChar = char;
            }
          }

          if (cUuid == PoiseBleConfig.calibrationCharacteristicUuid.toLowerCase()) {
            _calibrationChar = char;
          }
        }
      }

      if (telemetryChar != null) {
        await telemetryChar.setNotifyValue(true);
        await _charValueSubscription?.cancel();
        _charValueSubscription =
            telemetryChar.onValueReceived.listen(_handleIncomingTelemetry);
      }
    } catch (e) {
      debugPrint('[PoiseBleService] Service discovery error: $e');
    }
  }

  /// Parses and processes incoming BLE bytes into degrees.
  /// Supports:
  /// 1. ASCII String format: e.g. "12.5" or "-3.2\n"
  /// 2. Binary 32-bit Float (IEEE 754, 4 bytes)
  /// 3. Binary 16-bit Signed Integer (degrees * 10 or * 100)
  void _handleIncomingTelemetry(List<int> bytes) {
    if (bytes.isEmpty) return;

    double? rawAngle;

    // 1. Try ASCII String decode
    try {
      final str = utf8.decode(bytes).trim();
      rawAngle = double.tryParse(str);
    } catch (_) {}

    // 2. Try Binary 4-byte Float
    if (rawAngle == null && bytes.length >= 4) {
      try {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        rawAngle = byteData.getFloat32(0, Endian.little);
      } catch (_) {}
    }

    // 3. Try Binary 2-byte Signed Int (degrees * 10)
    if (rawAngle == null && bytes.length >= 2) {
      try {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        final rawInt = byteData.getInt16(0, Endian.little);
        rawAngle = rawInt / 10.0;
      } catch (_) {}
    }

    if (rawAngle != null) {
      // Calculate effective angle relative to zero baseline calibration
      final calibratedAngle = (rawAngle - _zeroBaselineOffset).clamp(-60.0, 60.0);
      _currentPitchAngle = calibratedAngle;
      _pitchAngleController.add(calibratedAngle);
    }
  }

  /// Disconnects from the connected POISE hardware.
  Future<void> disconnect() async {
    _stopMockTelemetryStream();
    await _charValueSubscription?.cancel();
    _charValueSubscription = null;

    try {
      await _activeDevice?.disconnect();
    } catch (_) {}

    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;
    _activeDevice = null;
    _connectedDeviceName = null;
    _handleDisconnection();
  }

  void _handleDisconnection() {
    _stopMockTelemetryStream();
    _activeDevice = null;
    _connectedDeviceName = null;
    _currentPitchAngle = 0.0;
    _pitchAngleController.add(0.0);
    _setState(PoiseBleState.disconnected);
  }

  /// Calibrate zero baseline: sets the current angle as 0° (tare),
  /// and transmits a calibration command to the hardware if supported.
  Future<void> setZeroBaseline({double? baselinePitch}) async {
    _zeroBaselineOffset = baselinePitch ?? _currentPitchAngle;
    _currentPitchAngle = 0.0;
    _pitchAngleController.add(0.0);

    // If connected to hardware, write tare command [0x01] to calibration characteristic
    if (_calibrationChar != null) {
      try {
        await _calibrationChar!.write([0x01], withoutResponse: false);
      } catch (e) {
        debugPrint('[PoiseBleService] Write calibration command error: $e');
      }
    }
  }

  void _setState(PoiseBleState newState) {
    _state = newState;
    _connectionStateController.add(newState);
    _isConnectedController.add(newState == PoiseBleState.connected);
  }

  /// Emits a simulated pitch angle reading (useful for testing or manual simulation).
  void simulatePitchAngle(double angle) {
    final calibrated = (angle - _zeroBaselineOffset).clamp(-60.0, 60.0);
    _currentPitchAngle = calibrated;
    _pitchAngleController.add(calibrated);
  }

  /// Starts mock telemetry drift for demo purposes without hardware.
  void startMockTelemetryStream() {
    stopMockTelemetryStream();
    int step = 0;
    _mockStreamTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_state == PoiseBleState.connected) {
        step++;
        final simulatedAngle = (step % 12 == 0)
            ? 18.0
            : (step % 6 == 0 ? 8.0 : 2.5);
        final calibrated = (simulatedAngle - _zeroBaselineOffset).clamp(-60.0, 60.0);
        _currentPitchAngle = calibrated;
        _pitchAngleController.add(calibrated);
      }
    });
  }

  /// Stops mock telemetry drift.
  void stopMockTelemetryStream() {
    _mockStreamTimer?.cancel();
    _mockStreamTimer = null;
  }

  void _stopMockTelemetryStream() => stopMockTelemetryStream();

  /// Reset internal state for tests or fresh sessions
  void resetForTesting() {
    stopMockTelemetryStream();
    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _charValueSubscription?.cancel();
    _discoveredDevices.clear();
    _activeDevice = null;
    _connectedDeviceName = null;
    _zeroBaselineOffset = 0.0;
    _currentPitchAngle = 0.0;
    _state = PoiseBleState.disconnected;
  }

  /// Release resources
  void dispose() {
    stopMockTelemetryStream();
    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _charValueSubscription?.cancel();
    _connectionStateController.close();
    _isConnectedController.close();
    _scanResultsController.close();
    _pitchAngleController.close();
  }
}
