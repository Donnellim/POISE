import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../activity_mode.dart';
import '../mode_preferences.dart';
import '../device_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_database.dart';
import '../database/models.dart';
import '../notifications/local_notification_service.dart';

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

  /// Standard Bluetooth SIG Battery Service UUID (0x180F)
  static const String batteryServiceUuid =
      '0000180f-0000-1000-8000-00805f9b34fb';

  /// Standard Bluetooth SIG Battery Level Characteristic UUID (0x2A19)
  static const String batteryLevelCharacteristicUuid =
      '00002a19-0000-1000-8000-00805f9b34fb';

  /// Advertised name prefixes identifying POISE hardware.
  static const List<String> deviceNamePrefixes = [
    'P.O.I.S.E',
    'P.O.I.S.E.',
    'POISE',
    'POISE-BLE',
    'POISE_DEVICE'
  ];

  /// Returns true if the device name matches P.O.I.S.E or any POISE variant,
  /// ignoring punctuation and casing (e.g. "P.O.I.S.E", "P.O.I.S.E.", "POISE").
  static bool isPoiseDeviceName(String name) {
    if (name.isEmpty) return false;
    final upper = name.toUpperCase();
    if (deviceNamePrefixes.any((prefix) => upper.contains(prefix.toUpperCase()))) {
      return true;
    }
    final clean = upper.replaceAll('.', '').replaceAll('-', '').replaceAll('_', '').replaceAll(' ', '');
    return clean.contains('POISE');
  }

  /// Default mock device identifier for preview and simulation.
  static const String defaultMockDeviceName = 'P.O.I.S.E';
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

/// Actions or state changes reported by the physical POISE hardware (e.g. gesture triple-click).
enum PoiseDeviceSessionAction {
  started,
  paused,
  resumed,
  ended,
}

/// Central Bluetooth Low Energy (BLE) service for scanning, connecting,
/// and streaming live posture data from the POISE hardware.
class PoiseBleService {
  PoiseBleService._();
  static final PoiseBleService instance = PoiseBleService._();

  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  bool _connecting = false;

  @visibleForTesting
  bool simulateForTesting = false;

  bool get isTesting => simulateForTesting;

  bool get allowsSimulation =>
      simulateForTesting ||
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS) ||
      const bool.fromEnvironment('POISE_DEMO');

  void _watchAdapter() {
    if (allowsSimulation || _adapterSubscription != null) return;
    _adapterSubscription = adapterStateStream.listen((state) {
      if (state == BluetoothAdapterState.off ||
          state == BluetoothAdapterState.turningOff ||
          state == BluetoothAdapterState.unauthorized) {
        _handleDisconnection();
        unawaited(DeviceSession.shouldResume(adapterOn: false));
      }
    });
  }

  Future<bool> restoreConnection() async {
    _watchAdapter();
    if (isConnected) return true;
    if (!await isBluetoothAdapterOn()) return false;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('poise.deviceId');
    if (id == null) return false;
    _zeroBaselineOffset = prefs.getDouble('poise.baseline') ?? 0;
    return connect(PoiseDiscoveredDevice(
      id: id,
      name: prefs.getString('poise.deviceName') ?? 'POISE Device',
      rssi: 0,
      rawDevice: id.startsWith('SIMULATED-') && allowsSimulation
          ? null
          : BluetoothDevice.fromId(id),
    ));
  }

  Future<void> _rememberDevice(PoiseDiscoveredDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedName = (device.name.isEmpty ||
            device.name.toUpperCase().contains('POISE-BLE') ||
            device.name.toUpperCase().contains('SIMULATED') ||
            device.name == 'P.O.I.S.E.')
        ? 'POISE Device'
        : device.name;
    await prefs.setString('poise.deviceId', device.id);
    await prefs.setString('poise.deviceName', normalizedName);

    if (simulateForTesting) return;
    try {
      final now = DateTime.now();
      String userId = 'local_user';
      try {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null && !session.isExpired) {
          userId = session.user.id;
        }
      } catch (_) {}

      await PoiseLocalDatabase.instance.upsertDevice(
        DeviceModel(
          id: device.id,
          userId: userId,
          deviceName: normalizedName,
          pairedAt: now,
          lastSeenAt: now,
          updatedAt: now,
        ),
      );
    } catch (_) {}
  }

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

  final _deviceSessionSecondsController = StreamController<int>.broadcast();
  Stream<int> get deviceSessionSecondsStream =>
      _deviceSessionSecondsController.stream;

  final _deviceSessionActionController =
      StreamController<PoiseDeviceSessionAction>.broadcast();
  Stream<PoiseDeviceSessionAction> get deviceSessionActionStream =>
      _deviceSessionActionController.stream;

  int _deviceSessionSeconds = 0;
  int get deviceSessionSeconds => _deviceSessionSeconds;

  void updateDeviceSessionSeconds(int seconds) {
    if (seconds >= 0 && seconds != _deviceSessionSeconds) {
      _deviceSessionSeconds = seconds;
      if (!_deviceSessionSecondsController.isClosed) {
        _deviceSessionSecondsController.add(seconds);
      }
    }
  }

  final _batteryLevelController = StreamController<int>.broadcast();
  Stream<int> get batteryLevelStream => _batteryLevelController.stream;

  int _batteryLevel = 100;
  int get batteryLevel => _batteryLevel;

  void updateBatteryLevel(int level) {
    final clamped = level.clamp(0, 100);
    if (clamped != _batteryLevel) {
      _batteryLevel = clamped;
      if (!_batteryLevelController.isClosed) {
        _batteryLevelController.add(clamped);
      }
      if (clamped <= 20) {
        LocalNotificationService.instance.showDeviceNotice(
          id: 99,
          title: 'Low Battery',
          body: 'Please charge your P.O.I.S.E. device ($clamped% remaining).',
        );
      }
    }
  }

  // ── Current cached states ──
  PoiseBleState _state = PoiseBleState.disconnected;
  PoiseBleState get state => _state;
  bool get isConnected => _state == PoiseBleState.connected;

  final _modeSyncController = StreamController<bool>.broadcast();
  Stream<bool> get modeSyncStream => _modeSyncController.stream;

  final _modeStreamController = StreamController<ActivityMode>.broadcast();
  Stream<ActivityMode> get modeStream => _modeStreamController.stream;

  ActivityMode _phoneSavedMode = ActivityMode.normal;
  ActivityMode get phoneSavedMode => _phoneSavedMode;

  ActivityMode _hardwareActiveMode = ActivityMode.normal;
  ActivityMode get hardwareActiveMode => _hardwareActiveMode;

  bool _isModeSynchronized = false;
  bool get isModeSynchronized =>
      isConnected && _isModeSynchronized && (_hardwareActiveMode == _phoneSavedMode);

  String? _lastSentModeCommand;
  String? get lastSentModeCommand => _lastSentModeCommand;

  String? _connectedDeviceName;
  String? get connectedDeviceName => _connectedDeviceName;

  double _rawPitchAngle = 0.0;
  double get rawPitchAngle => _rawPitchAngle;

  double _currentPitchAngle = 0.0;
  double get currentPitchAngle => _currentPitchAngle;

  double _zeroBaselineOffset = 0.0;
  double get zeroBaselineOffset => _zeroBaselineOffset;

  // ── BLE Internal Objects ──
  BluetoothDevice? _activeDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;
  StreamSubscription<List<int>>? _charValueSubscription;
  StreamSubscription<List<int>>? _batteryCharSubscription;
  BluetoothCharacteristic? _calibrationChar;

  Timer? _mockStreamTimer;
  final List<PoiseDiscoveredDevice> _discoveredDevices = [];
  List<PoiseDiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  @visibleForTesting
  bool simulateQuickSettingsSynced = false;

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
      if (allowsSimulation) return true;
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) return false;
      final state = await FlutterBluePlus.adapterState
          .where((state) => state != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 5));
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return allowsSimulation;
    }
  }

  /// Request the OS to turn on the phone's Bluetooth adapter (prompt on Android).
  ///
  /// Note: If Bluetooth is already turned on, this returns true immediately
  /// without triggering the OS prompt.
  Future<bool> requestEnableBluetooth() async {
    try {
      if (allowsSimulation) return true;
      if (await isBluetoothAdapterOn()) return true;
      await FlutterBluePlus.turnOn();
      final state = await FlutterBluePlus.adapterState
          .where((state) => state != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 5));
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether a POISE device is currently connected or paired to the OS
  /// (e.g. via Android Quick Settings panel or iOS Bluetooth Settings),
  /// and establishes the in-app telemetry connection.
  Future<bool> checkAndConnectSystemDevice() async {
    _watchAdapter();
    if (!await isBluetoothAdapterOn()) return false;

    // Simulation / testing environment support
    if (allowsSimulation) {
      final prefs = await SharedPreferences.getInstance();
      final hasQsSim = simulateQuickSettingsSynced ||
          (prefs.getBool('poise.quick_settings_connected') ?? false);
      if (hasQsSim) {
        return connect(const PoiseDiscoveredDevice(
          id: 'SIMULATED-POISE-QS',
          name: PoiseBleConfig.defaultMockDeviceName,
          rssi: -50,
        ));
      }
      if (simulateForTesting && !hasQsSim) {
        return isConnected;
      }
    }

    try {
      // 1. Retrieve devices currently connected to the OS
      List<BluetoothDevice> systemDevs = [];
      try {
        systemDevs = await FlutterBluePlus.systemDevices([
          Guid(PoiseBleConfig.serviceUuid),
          Guid('00001800-0000-1000-8000-00805f9b34fb'),
        ]);
      } catch (e) {
        debugPrint('[PoiseBleService] systemDevices query error: $e');
      }

      // 2. Also check bonded devices (paired on Android)
      List<BluetoothDevice> bondedDevs = [];
      try {
        bondedDevs = await FlutterBluePlus.bondedDevices;
      } catch (_) {}

      final allCandidates = <BluetoothDevice>{...systemDevs, ...bondedDevs};
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('poise.deviceId');

      for (final dev in allCandidates) {
        final name = dev.platformName.isNotEmpty
            ? dev.platformName
            : (dev.advName.isNotEmpty ? dev.advName : '');
        final isPoiseName = PoiseBleConfig.isPoiseDeviceName(name);
        final isSavedDevice = savedId != null && dev.remoteId.str == savedId;

        if (isPoiseName || isSavedDevice) {
          debugPrint(
              '[PoiseBleService] Found system/Quick Settings synced device: $name (${dev.remoteId.str})');
          final success = await connect(PoiseDiscoveredDevice(
            id: dev.remoteId.str,
            name: name.isNotEmpty ? name : 'POISE Device',
            rssi: 0,
            rawDevice: dev,
          ));
          if (success) {
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[PoiseBleService] Error inspecting system BLE devices: $e');
    }

    return isConnected;
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
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 4)}) async {
    _watchAdapter();
    _discoveredDevices.clear();
    _scanResultsController.add(_discoveredDevices);
    _setState(PoiseBleState.scanning);

    final supported = await isBleSupported();
    if (!supported && allowsSimulation) {
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

          final matchesPrefix = PoiseBleConfig.isPoiseDeviceName(effectiveName);

          if (matchesPrefix) {
            final exists = _discoveredDevices
                .any((d) => d.id == result.device.remoteId.str);
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
      _setState(PoiseBleState.disconnected);
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
    if (_connecting) return false;
    if (device.rawDevice == null && !allowsSimulation) return false;
    _connecting = true;
    _watchAdapter();
    await stopScan();
    _setState(PoiseBleState.connecting);

    if (device.rawDevice == null) {
      // Simulated / Mock connection
      _connectedDeviceName = device.name;
      _setState(PoiseBleState.connected);
      await _rememberDevice(device);
      await syncSavedModeToHardware();
      _connecting = false;
      return true;
    }

    final rawDevice = device.rawDevice!;
    _activeDevice = rawDevice;

    try {
      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = rawDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && isConnected) {
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
      if (!rawDevice.isConnected || !await isBluetoothAdapterOn()) {
        throw StateError('Device disconnected during setup');
      }

      _setState(PoiseBleState.connected);
      await _rememberDevice(device);
      await syncSavedModeToHardware();
      _connecting = false;
      return true;
    } catch (e) {
      debugPrint('[PoiseBleService] Connect error: $e');
      await rawDevice.disconnect();
      _handleDisconnection();
      return false;
    } finally {
      _connecting = false;
    }
  }

  /// Discovers GATT services and subscribes to the posture telemetry stream.
  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? telemetryChar;
      BluetoothCharacteristic? batteryChar;

      for (final service in services) {
        final sUuid = service.uuid.toString().toLowerCase();
        final isBatteryService = sUuid.contains('180f');

        for (final char in service.characteristics) {
          final cUuid = char.uuid.toString().toLowerCase();
          final isBatteryChar = cUuid.contains('2a19');

          if (isBatteryService || isBatteryChar) {
            batteryChar = char;
          }

          // Check if matches configured telemetry characteristic or has notify property
          if (char.uuid == Guid(PoiseBleConfig.postureCharacteristicUuid) &&
              service.uuid == Guid(PoiseBleConfig.serviceUuid)) {
            if (char.properties.notify || char.properties.indicate) {
              telemetryChar = char;
            }
          }

          if (char.uuid == Guid(PoiseBleConfig.calibrationCharacteristicUuid)) {
            _calibrationChar = char;
          }
        }
      }

      if (batteryChar != null) {
        try {
          if (batteryChar.properties.read) {
            final val = await batteryChar.read();
            if (val.isNotEmpty) updateBatteryLevel(val[0]);
          }
          if (batteryChar.properties.notify || batteryChar.properties.indicate) {
            await _batteryCharSubscription?.cancel();
            _batteryCharSubscription =
                batteryChar.onValueReceived.listen((data) {
              if (data.isNotEmpty) updateBatteryLevel(data[0]);
            });
            await batteryChar.setNotifyValue(true);
          }
        } catch (e) {
          debugPrint(
              '[PoiseBleService] Battery characteristic subscription error: $e');
        }
      }

      // Smart fallback: If exact configured UUID was not found, auto-discover by characteristic properties
      if (telemetryChar == null) {
        for (final service in services) {
          final sUuid = service.uuid.toString().toLowerCase();
          if (sUuid.contains('180f') || sUuid.contains('1800') || sUuid.contains('1801')) {
            continue; // Skip battery and standard generic access services
          }
          for (final char in service.characteristics) {
            final cUuid = char.uuid.toString().toLowerCase();
            if ((char.properties.notify || char.properties.indicate) &&
                !cUuid.contains('2a19')) {
              telemetryChar = char;
              debugPrint('[PoiseBleService] Auto-discovered telemetry characteristic: ${char.uuid}');
              break;
            }
          }
          if (telemetryChar != null) break;
        }
      }

      if (_calibrationChar == null) {
        for (final service in services) {
          final sUuid = service.uuid.toString().toLowerCase();
          if (sUuid.contains('180f') || sUuid.contains('1800') || sUuid.contains('1801')) {
            continue;
          }
          for (final char in service.characteristics) {
            if (char.properties.write || char.properties.writeWithoutResponse) {
              _calibrationChar = char;
              debugPrint('[PoiseBleService] Auto-discovered calibration characteristic: ${char.uuid}');
              break;
            }
          }
          if (_calibrationChar != null) break;
        }
      }

      if (telemetryChar == null) {
        throw StateError("POISE telemetry unavailable");
      }
      await _charValueSubscription?.cancel();
      _charValueSubscription =
          telemetryChar.onValueReceived.listen(_handleIncomingTelemetry);
      await telemetryChar.setNotifyValue(true);
      if (telemetryChar.properties.read) await telemetryChar.read();
    } catch (e) {
      debugPrint('[PoiseBleService] Service discovery error: $e');
      rethrow;
    }
  }

  /// Parses and processes incoming BLE bytes into degrees.
  /// Parses and processes incoming BLE bytes into degrees.
  /// Supports:
  /// 1. ASCII String format: e.g. "12.5", "12.5,29", "SESSION:29"
  /// 2. JSON Telemetry format: e.g. {"pitch": 12.5, "elapsed": 29}
  /// 3. Binary 32-bit Float (IEEE 754, 4 bytes)
  /// 4. Binary 16-bit Signed Integer (degrees * 10 or * 100)
  void _handleIncomingTelemetry(List<int> bytes) {
    if (bytes.isEmpty || (!isConnected && !_connecting)) return;

    double? rawAngle;

    // Check if packet contains string/JSON telemetry or offline records
    try {
      final str = utf8.decode(bytes).trim();

      // 1. JSON Telemetry or LittleFS Dump
      if (str.startsWith('{')) {
        final dynamic decoded = json.decode(str);
        if (decoded is Map) {
          // If it contains a list of events, route to LittleFS batch processor
          if (decoded.containsKey('events') && decoded['events'] is List) {
            _processLittleFsPayload(str);
            return;
          }
          final p = (decoded['pitch'] as num?)?.toDouble() ??
              (decoded['angle'] as num?)?.toDouble() ??
              (decoded['tilt'] as num?)?.toDouble();
          if (p != null && p.isFinite) {
            rawAngle = p;
          }
          final el = (decoded['elapsed'] as num?)?.toInt() ??
              (decoded['session_seconds'] as num?)?.toInt() ??
              (decoded['seconds'] as num?)?.toInt() ??
              (decoded['duration'] as num?)?.toInt();
          if (el != null && el >= 0) {
            updateDeviceSessionSeconds(el);
          }
          final bat = (decoded['battery'] as num?)?.toInt() ??
              (decoded['battery_level'] as num?)?.toInt() ??
              (decoded['bat'] as num?)?.toInt() ??
              (decoded['bat_pct'] as num?)?.toInt();
          if (bat != null) {
            updateBatteryLevel(bat);
          }
          if (rawAngle != null) {
            _applyCalibratedPitch(rawAngle);
            return;
          }
        }
      } else if (str.startsWith('[') ||
          str.startsWith('LFS:') ||
          str.startsWith('LOG:')) {
        _processLittleFsPayload(str);
        return;
      }

      // 2. ASCII session and battery commands
      final upper = str.toUpperCase();
      if (upper == 'SESSION:ENDED' ||
          upper == 'SESSION:STOPPED' ||
          upper == 'SESSION:END' ||
          upper == 'END' ||
          upper == 'STOP' ||
          upper == 'TRIPLE_CLICK') {
        _deviceSessionActionController.add(PoiseDeviceSessionAction.ended);
        return;
      }
      if (upper == 'SESSION:STARTED' || upper == 'START') {
        _deviceSessionActionController.add(PoiseDeviceSessionAction.started);
        return;
      }
      if (upper == 'SESSION:PAUSED' || upper == 'PAUSE') {
        _deviceSessionActionController.add(PoiseDeviceSessionAction.paused);
        return;
      }
      if (upper == 'SESSION:RESUMED' || upper == 'RESUME') {
        _deviceSessionActionController.add(PoiseDeviceSessionAction.resumed);
        return;
      }

      if (str.startsWith('SESSION:') ||
          str.startsWith('ELAPSED:') ||
          str.startsWith('UPTIME:')) {
        final clean =
            str.replaceFirst(RegExp(r'^(SESSION:|ELAPSED:|UPTIME:)'), '').trim();
        final s = int.tryParse(clean) ?? double.tryParse(clean)?.toInt();
        if (s != null) {
          updateDeviceSessionSeconds(s);
          return;
        }
      }

      if (str.startsWith('BAT:') ||
          str.startsWith('BATTERY:') ||
          str.startsWith('BATT:')) {
        final clean =
            str.replaceFirst(RegExp(r'^(BAT:|BATTERY:|BATT:)'), '').trim();
        final b = int.tryParse(clean) ?? double.tryParse(clean)?.toInt();
        if (b != null) {
          updateBatteryLevel(b);
          return;
        }
      }

      // 3. ASCII comma/semicolon format: "12.5,29" or "12.5,29,85" -> pitch 12.5, elapsed 29, battery 85
      if (str.contains(',') || str.contains(';')) {
        final parts = str.contains(',') ? str.split(',') : str.split(';');
        final p = double.tryParse(parts[0].trim());
        if (p != null) {
          rawAngle = p;
          if (parts.length > 1) {
            final s = int.tryParse(parts[1].trim()) ??
                double.tryParse(parts[1].trim())?.toInt();
            if (s != null) {
              updateDeviceSessionSeconds(s);
            }
          }
          if (parts.length > 2) {
            final b = int.tryParse(parts[2].trim()) ??
                double.tryParse(parts[2].trim())?.toInt();
            if (b != null) {
              updateBatteryLevel(b);
            }
          }
        }
      } else {
        rawAngle = double.tryParse(str);
      }
    } catch (_) {}

    // 4. Binary 4-byte Float
    if (rawAngle == null && bytes.length >= 4) {
      try {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        rawAngle = byteData.getFloat32(0, Endian.little);
        if (bytes.length >= 8) {
          final el = byteData.getInt32(4, Endian.little);
          if (el >= 0) updateDeviceSessionSeconds(el);
        }
        if (bytes.length >= 12) {
          final bat = byteData.getInt32(8, Endian.little);
          if (bat >= 0 && bat <= 100) updateBatteryLevel(bat);
        }
      } catch (_) {}
    }

    // 5. Binary 2-byte Signed Int (degrees * 10)
    if (rawAngle == null && bytes.length >= 2) {
      try {
        final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
        final rawInt = byteData.getInt16(0, Endian.little);
        rawAngle = rawInt / 10.0;
        if (bytes.length >= 4) {
          final el = byteData.getInt16(2, Endian.little);
          if (el >= 0) updateDeviceSessionSeconds(el);
        }
        if (bytes.length >= 6) {
          final bat = byteData.getInt16(4, Endian.little);
          if (bat >= 0 && bat <= 100) updateBatteryLevel(bat);
        }
      } catch (_) {}
    }

    if (rawAngle != null && rawAngle.isFinite) {
      // The physical POISE firmware transmits the already-calibrated deviation
      // relative to its tare zero baseline over FFE1.
      _applyCalibratedPitch(rawAngle, isHardwareDeviation: true);
    }
  }

  void _applyCalibratedPitch(double rawAngle, {bool isHardwareDeviation = true}) {
    var angle = rawAngle;
    if (angle.abs() > 180.0) {
      angle = angle / 100.0;
    }
    angle = angle.clamp(-60.0, 60.0);
    _rawPitchAngle = angle;
    // When received from physical POISE hardware over FFE1, the value is already the calibrated deviation.
    // If not hardware deviation (e.g. simulated drift before tare), subtract _zeroBaselineOffset.
    final calibratedAngle = isHardwareDeviation
        ? angle
        : (angle - _zeroBaselineOffset).clamp(-60.0, 60.0);
    _currentPitchAngle = calibratedAngle;
    _pitchAngleController.add(calibratedAngle);
  }

  /// Parses LittleFS offline posture logs dumped by POISE hardware upon Bluetooth connection
  Future<void> _processLittleFsPayload(String payload) async {
    try {
      final events = <PostureEventModel>[];
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('poise.deviceId') ?? 'POISE-DEVICE';
      String userId = 'local_user';
      try {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null && !session.isExpired) {
          userId = session.user.id;
        }
      } catch (_) {}

      if (payload.startsWith('{') || payload.startsWith('[')) {
        final dynamic decoded = json.decode(payload);
        final list = decoded is List
            ? decoded
            : (decoded is Map && decoded['events'] is List
                ? decoded['events'] as List
                : [decoded]);
        for (final item in list) {
          if (item is Map) {
            var pitch = (item['pitch'] as num?)?.toDouble() ??
                (item['angle'] as num?)?.toDouble() ??
                0.0;
            if (pitch.abs() > 180.0) pitch /= 100.0;
            pitch = pitch.clamp(-60.0, 60.0);
            final dur = (item['duration'] as num?)?.toDouble() ??
                (item['elapsed'] as num?)?.toDouble() ??
                (item['session_seconds'] as num?)?.toDouble() ??
                1.0;
            final ts = item['timestamp'] != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    (item['timestamp'] as num).toInt())
                : now;
            final modeId = (item['mode_id'] as num?)?.toInt() ?? 1;
            final sessionId = item['session_id'] as String? ??
                'lfs_sess_${ts.millisecondsSinceEpoch}';

            final isOngoing = item['active'] == true || item['ended'] == false;
            final sessionEnd = ts.add(Duration(seconds: dur.toInt()));

            await PoiseLocalDatabase.instance.insertSession(SessionModel(
              id: sessionId,
              deviceId: deviceId,
              userId: userId,
              modeId: modeId,
              startedAt: ts,
              updatedAt: sessionEnd,
              endedAt: isOngoing ? null : sessionEnd,
              synced: false,
            ));

            if (isOngoing || item == list.last) {
              updateDeviceSessionSeconds(dur.toInt());
            }

            events.add(PostureEventModel(
              id: 'lfs_evt_${ts.microsecondsSinceEpoch}_${events.length}',
              sessionId: sessionId,
              occurredAt: ts,
              tiltAngle: pitch,
              durationSec: dur,
              feedbackTriggered: item['feedback'] == true || pitch.abs() > 15,
              synced: false,
            ));
          }
        }
      } else if (payload.startsWith('LFS:') || payload.startsWith('LOG:')) {
        final clean = payload.replaceFirst(RegExp(r'^(LFS:|LOG:)'), '').trim();
        final parts = clean.split(',');
        if (parts.length >= 2) {
          var pitch = double.tryParse(parts[0]) ?? 0.0;
          if (pitch.abs() > 180.0) pitch /= 100.0;
          pitch = pitch.clamp(-60.0, 60.0);
          final dur =
              parts.length > 1 ? (double.tryParse(parts[1]) ?? 1.0) : 1.0;
          final modeId = parts.length > 2 ? (int.tryParse(parts[2]) ?? 1) : 1;
          final ts =
              parts.length > 3 ? (DateTime.tryParse(parts[3]) ?? now) : now;
          final sessionId = 'lfs_sess_${ts.millisecondsSinceEpoch}';
          final sessionEnd = ts.add(Duration(seconds: dur.toInt()));

          await PoiseLocalDatabase.instance.insertSession(SessionModel(
            id: sessionId,
            deviceId: deviceId,
            userId: userId,
            modeId: modeId,
            startedAt: ts,
            updatedAt: sessionEnd,
            endedAt: sessionEnd,
            synced: false,
          ));

          updateDeviceSessionSeconds(dur.toInt());

          events.add(PostureEventModel(
            id: 'lfs_evt_${ts.microsecondsSinceEpoch}',
            sessionId: sessionId,
            occurredAt: ts,
            tiltAngle: pitch,
            durationSec: dur,
            feedbackTriggered: pitch.abs() > 15,
            correctedAt: ts.add(Duration(milliseconds: (dur * 1000).toInt())),
            correctionTimeSec: dur,
            synced: false,
          ));
        }
      }

      if (events.isNotEmpty) {
        await PoiseLocalDatabase.instance.insertPostureEventsBatch(events);
      }
    } catch (e) {
      debugPrint('[PoiseBleService] LittleFS payload parse error: $e');
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
    _charValueSubscription?.cancel();
    _charValueSubscription = null;
    _batteryCharSubscription?.cancel();
    _batteryCharSubscription = null;
    _calibrationChar = null;
    // Under Rev 9 firmware, the hardware falls back to Normal on disconnect.
    // The mobile app retains the phone's last selected preference and does NOT overwrite it.
    _hardwareActiveMode = ActivityMode.normal;
    _isModeSynchronized = false;
    if (!_modeSyncController.isClosed) {
      _modeSyncController.add(false);
    }
    _setState(PoiseBleState.disconnected);
  }

  /// Calibrate zero baseline: sets the current angle as 0° (tare),
  /// and transmits a calibration command to the hardware if supported.
  Future<void> setZeroBaseline({double? baselinePitch}) async {
    var baseline = baselinePitch ??
        (_rawPitchAngle != 0.0
            ? _rawPitchAngle
            : (_currentPitchAngle + _zeroBaselineOffset));
    if (baseline.abs() > 180.0) baseline /= 100.0;
    baseline = baseline.clamp(-60.0, 60.0);
    _zeroBaselineOffset = baseline;
    _currentPitchAngle =
        (_rawPitchAngle - _zeroBaselineOffset).clamp(-60.0, 60.0);
    _pitchAngleController.add(_currentPitchAngle);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('poise.baseline', _zeroBaselineOffset);

    // If connected to hardware, write tare command [0x01] to calibration characteristic
    if (_calibrationChar != null) {
      try {
        await _calibrationChar!.write([0x01], withoutResponse: false);
      } catch (e) {
        debugPrint('[PoiseBleService] Write calibration command error: $e');
      }
    }
  }

  /// Sends a session lifecycle command to the connected hardware.
  Future<bool> sendSessionCommand(String command) async {
    if (_calibrationChar != null) {
      try {
        final bytes = utf8.encode(command);
        await _calibrationChar!.write(bytes, withoutResponse: false);
        return true;
      } catch (e) {
        debugPrint('[PoiseBleService] Write session command error: $e');
      }
    }
    return false;
  }

  /// Synchronizes the phone's saved mode preference with the connected POISE hardware.
  ///
  /// After BLE connection and service discovery:
  /// 1. Loads the phone's saved mode preference.
  /// 2. Sends the corresponding `MODE:<id>` command to FFE2.
  /// 3. Confirms that the command is applied before marking hardware as synchronized.
  Future<bool> syncSavedModeToHardware() async {
    final saved = await ModePreferences.getSavedMode();
    _phoneSavedMode = saved;
    if (!_modeStreamController.isClosed) {
      _modeStreamController.add(saved);
    }

    if (isConnected && (_calibrationChar != null || allowsSimulation)) {
      final modeId = ModeModel.idForActivityMode(saved);
      final cmd = 'MODE:$modeId';
      _lastSentModeCommand = cmd;
      bool success = true;
      if (_calibrationChar != null) {
        success = await sendSessionCommand(cmd);
      }
      if (success) {
        _hardwareActiveMode = saved;
        _isModeSynchronized = true;
        if (!_modeSyncController.isClosed) {
          _modeSyncController.add(true);
        }
        return true;
      }
    }

    _hardwareActiveMode = ActivityMode.normal;
    _isModeSynchronized = false;
    if (!_modeSyncController.isClosed) {
      _modeSyncController.add(false);
    }
    return false;
  }

  /// Transmits active mode configuration to the connected hardware.
  ///
  /// Immediately sends the `MODE:<id>` command, saves the new preference on the phone,
  /// and confirms application on hardware.
  Future<bool> sendModeCommand(ActivityMode mode) async {
    _phoneSavedMode = mode;
    await ModePreferences.saveMode(mode);
    if (!_modeStreamController.isClosed) {
      _modeStreamController.add(mode);
    }

    final modeId = ModeModel.idForActivityMode(mode);
    final cmd = 'MODE:$modeId';
    _lastSentModeCommand = cmd;

    if (isConnected && (_calibrationChar != null || allowsSimulation)) {
      bool success = true;
      if (_calibrationChar != null) {
        success = await sendSessionCommand(cmd);
      }
      if (success) {
        _hardwareActiveMode = mode;
        _isModeSynchronized = true;
        if (!_modeSyncController.isClosed) {
          _modeSyncController.add(true);
        }
        return true;
      }
    }

    _hardwareActiveMode = ActivityMode.normal;
    _isModeSynchronized = false;
    if (!_modeSyncController.isClosed) {
      _modeSyncController.add(false);
    }
    return false;
  }

  /// Transmits device vibration feedback preference to the connected hardware.
  Future<bool> sendVibrationCommand(bool enabled) async {
    return sendSessionCommand('VIB:${enabled ? 1 : 0}');
  }

  void _setState(PoiseBleState newState) {
    _state = newState;
    _connectionStateController.add(newState);
    _isConnectedController.add(newState == PoiseBleState.connected);
  }

  /// Emits a simulated pitch angle reading (useful for testing or manual simulation).
  void simulatePitchAngle(double angle) {
    var a = angle;
    if (a.abs() > 180.0) a /= 100.0;
    a = a.clamp(-60.0, 60.0);
    _rawPitchAngle = a;
    final calibrated = (a - _zeroBaselineOffset).clamp(-60.0, 60.0);
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
        final simulatedAngle =
            (step % 12 == 0) ? 18.0 : (step % 6 == 0 ? 8.0 : 2.5);
        _rawPitchAngle = simulatedAngle;
        final calibrated =
            (simulatedAngle - _zeroBaselineOffset).clamp(-60.0, 60.0);
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

  bool get isMockStreaming =>
      _mockStreamTimer != null && _mockStreamTimer!.isActive;

  void _stopMockTelemetryStream() => stopMockTelemetryStream();

  /// Reset internal state for tests or fresh sessions
  void resetForTesting() {
    stopMockTelemetryStream();
    _adapterSubscription?.cancel();
    _adapterSubscription = null;
    _connecting = false;
    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _charValueSubscription?.cancel();
    _batteryCharSubscription?.cancel();
    _batteryCharSubscription = null;
    _discoveredDevices.clear();
    _activeDevice = null;
    _connectedDeviceName = null;
    _rawPitchAngle = 0.0;
    _zeroBaselineOffset = 0.0;
    _currentPitchAngle = 0.0;
    _deviceSessionSeconds = 0;
    _batteryLevel = 100;
    _hardwareActiveMode = ActivityMode.normal;
    _phoneSavedMode = ActivityMode.normal;
    ModePreferences.resetForTesting();
    _isModeSynchronized = false;
    _lastSentModeCommand = null;
    simulateQuickSettingsSynced = false;
    _state = PoiseBleState.disconnected;
  }

  /// Release resources
  void dispose() {
    stopMockTelemetryStream();
    _adapterSubscription?.cancel();
    _adapterSubscription = null;
    _connecting = false;
    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _charValueSubscription?.cancel();
    _batteryCharSubscription?.cancel();
    _batteryCharSubscription = null;
    _connectionStateController.close();
    _isConnectedController.close();
    _scanResultsController.close();
    _pitchAngleController.close();
    _deviceSessionSecondsController.close();
    _deviceSessionActionController.close();
    _batteryLevelController.close();
    _modeSyncController.close();
    _modeStreamController.close();
  }
}
