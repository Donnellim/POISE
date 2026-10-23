import '../database/sync_service.dart';
import '../database/device_posture_event.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../activity_mode.dart';
import '../mode_preferences.dart';
import '../feedback_preferences.dart';
import '../device_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_database.dart';
import '../database/models.dart';
import '../notifications/local_notification_service.dart';

/// Configuration for POISE Bluetooth Low Energy (BLE) communication.
///
/// UUIDs for the ESP32-C3 firmware protocol.
class PoiseBleConfig {
  /// Primary GATT Service UUID for the POISE Peripheral.
  /// (Default: standard 16-bit custom service 0xFFE0 in 128-bit form)
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

  /// GATT Characteristic UUID for real-time posture pitch angle telemetry (Read/Notify).
  static const String postureCharacteristicUuid =
      '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// FFE2 receives ASCII configuration, synchronization and session commands.
  static const String calibrationCharacteristicUuid =
      '0000ffe2-0000-1000-8000-00805f9b34fb';

  static const eventCharacteristicUuid = '0000ffe3-0000-1000-8000-00805f9b34fb';

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
    if (deviceNamePrefixes
        .any((prefix) => upper.contains(prefix.toUpperCase()))) {
      return true;
    }
    final clean = upper
        .replaceAll('.', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '');
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

enum PoiseDeviceState {
  idle,
  calibrationReady,
  calibrating,
  monitoring,
  paused,
  chargingLockout,
  error
}

/// Each notification is a fresh time anchor, even for the same session ID.
class PoiseSessionSnapshot {
  const PoiseSessionSnapshot(this.id, this.elapsed);

  final String id;
  final Duration elapsed;
}

/// Central Bluetooth Low Energy (BLE) service for scanning, connecting,
/// and streaming live posture data from the POISE hardware.
class PoiseBleService extends ChangeNotifier {
  PoiseBleService._();
  static final PoiseBleService instance = PoiseBleService._();

  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  bool _connecting = false;
  ChangeNotifier get protocolChanges => this;
  PoiseDeviceState deviceState = PoiseDeviceState.idle;
  bool vibrationEnabled = true;
  String? protocolError;
  bool _receivedState = false;
  bool _receivedSession = false;
  bool get _snapshotComplete =>
      _receivedState &&
      _receivedConfig &&
      ((deviceState != PoiseDeviceState.monitoring &&
              deviceState != PoiseDeviceState.paused) ||
          _receivedSession);
  bool _receivedConfig = false;
  ActivityMode? _snapshotMode;
  bool? _snapshotVibration;
  Completer<bool>? _pending;
  Set<String> _expected = {};
  String _activeCommand = '';
  bool get commandPending => _pending != null;
  bool get controlsEnabled => isModeSynchronized && !commandPending;
  bool get sessionControlsEnabled =>
      controlsEnabled &&
      deviceState != PoiseDeviceState.calibrating &&
      deviceState != PoiseDeviceState.chargingLockout &&
      deviceState != PoiseDeviceState.error;
  @visibleForTesting
  Future<void> Function(String)? commandWriter;
  @visibleForTesting
  Duration responseTimeout = const Duration(seconds: 8);
  @visibleForTesting
  void receiveMessage(String message) =>
      _handleIncomingTelemetry(utf8.encode(message));

  int sessionEndRevision = 0;
  bool clockSynchronized = false;
  String clockStatus = 'required';
  int pendingEventCount = 0;
  bool importAuthorized = false;
  bool importing = false;
  String? importError;
  int connectionGeneration = 0;
  BluetoothCharacteristic? _eventChar;
  @visibleForTesting
  Future<List<int>> Function()? eventReader;
  @visibleForTesting
  Future<void> Function(DevicePostureEvent)? eventCommitter;
  Future<void> _commandQueue = Future.value();
  int _queuedCommands = 0;
  String? _nextReply;
  String? _ackReply;
  bool _refreshRequested = false;
  bool _importRecheckRequested = false;
  bool _refreshRunning = false;

  Future<bool> synchronizeClock() async {
    return _exchange('TIME:SYNC:',
        {'TIME:SYNC:OK', 'TIME:SYNC:DEFERRED', 'TIME:SYNC:APPLIED'});
  }

  Future<void> _initializeProtocol() async {
    await synchronizeClock();
    if (!isConnected) return;
    await syncSavedModeToHardware();
    if (isConnected) await checkStoredEvents();
  }

  Future<bool> checkStoredEvents() =>
      _exchange('EVENTLOG:STATUS', {'EVENTLOG:PENDING:'});

  void _requestLifecycleRefresh() {
    _refreshRequested = true;
    if (_refreshRunning) return;
    _refreshRunning = true;
    unawaited(() async {
      try {
        while (_refreshRequested && isConnected) {
          _refreshRequested = false;
          // Queue behind the command whose notifications triggered this refresh.
          await Future<void>.value();
          await _commandQueue;
          if (!isConnected) break;
          await syncSavedModeToHardware();
          await checkStoredEvents();
          if (importAuthorized && !importing) await importStoredEvents();
        }
      } finally {
        _refreshRunning = false;
      }
    }());
  }

  Future<void> importStoredEvents() async {
    if (!isConnected || importing) return;
    final generation = connectionGeneration;
    bool current() => isConnected && generation == connectionGeneration;
    importing = true;
    importError = null;
    _changed();
    try {
      if (!importAuthorized) {
        if (!await _exchange('EVENTLOG:START', {'EVENTLOG:AUTHORIZED'}) ||
            !current()) {
          throw StateError('Device did not authorize import');
        }
        importAuthorized = true;
      }
      while (current()) {
        if (!await _exchange(
                'EVENTLOG:NEXT', {'EVENTLOG:RECORD_READY', 'EVENTLOG:EMPTY'}) ||
            !current()) {
          throw StateError('Unable to request stored event');
        }
        if (_nextReply == 'EVENTLOG:EMPTY') {
          pendingEventCount = 0;
          if (_importRecheckRequested) {
            _importRecheckRequested = false;
            await checkStoredEvents();
            continue;
          }
          break;
        }
        final bytes = await (eventReader != null
                ? eventReader!()
                : _eventChar != null
                    ? _eventChar!.read()
                    : Future<List<int>>.error(
                        StateError('Readable FFE3 unavailable')))
            .timeout(responseTimeout);
        if (!current()) return;
        final event = DevicePostureEvent.parse(
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
        await (eventCommitter != null
            ? eventCommitter!(event)
            : PoiseLocalDatabase.instance.commitDeviceEvent(event));
        if (!current()) return;
        // The durable SQLite commit (including matching duplicates) is the ACK boundary.
        bool acknowledged = false;
        for (var attempt = 0; attempt < 3 && current(); attempt++) {
          final received = await _exchange('EVENTLOG:ACK:${event.eventId}',
              {'EVENTLOG:ACK:OK', 'EVENTLOG:ACK:FAILED'});
          if (!current()) return;
          if (received && _ackReply == 'EVENTLOG:ACK:OK') {
            acknowledged = true;
            break;
          }
          if (!received || _ackReply != 'EVENTLOG:ACK:FAILED') break;
        }
        if (!acknowledged) {
          throw StateError(
              'Event acknowledgement failed; retry import to resume');
        }
        if (pendingEventCount > 0) pendingEventCount--;
      }
    } catch (error) {
      if (current()) {
        importError =
            'Import stopped: $error. Unacknowledged records remain on the device.';
      }
    } finally {
      if (generation == connectionGeneration) {
        importing = false;
        _changed();
        if (!simulateForTesting) unawaited(SyncService.instance.syncToCloud());
      }
    }
  }

  void _changed() {
    notifyListeners();
    _modeSyncController.add(isModeSynchronized);
  }

  void _confirmConfig(ActivityMode mode, bool vibration) {
    _hardwareActiveMode = mode;
    _phoneSavedMode = mode;
    vibrationEnabled = vibration;
    _modeStreamController.add(mode);
    unawaited(ModePreferences.saveMode(mode));
    unawaited(FeedbackPreferences.saveVibration(vibration));
  }

  bool _handleProtocol(String message) {
    if (message.startsWith('TIME:SYNC:') || message.startsWith('EVENTLOG:')) {
      if (message == 'EVENTLOG:RECORD_READY' &&
          importing &&
          !(_activeCommand == 'EVENTLOG:NEXT' &&
              _pending != null &&
              !_pending!.isCompleted)) {
        _importRecheckRequested = true;
      }
      if (message.startsWith('TIME:SYNC:')) {
        clockStatus = message.substring('TIME:SYNC:'.length).toLowerCase();
        clockSynchronized = clockStatus == 'ok' || clockStatus == 'applied';
      }
      if (message.startsWith('EVENTLOG:PENDING:')) {
        final count =
            int.tryParse(message.substring('EVENTLOG:PENDING:'.length));
        if (count == null || count < 0) return true;
        pendingEventCount = count;
      }
      if (message == 'EVENTLOG:CONSENT_REQUIRED') importAuthorized = false;
      if (_pending != null && !_pending!.isCompleted) {
        if (_expected.contains(message) ||
            (_expected.contains('EVENTLOG:PENDING:') &&
                message.startsWith('EVENTLOG:PENDING:'))) {
          if (message == 'EVENTLOG:EMPTY' ||
              message == 'EVENTLOG:RECORD_READY') {
            _nextReply = message;
          }
          if (message.startsWith('EVENTLOG:ACK:')) _ackReply = message;
          _pending!.complete(true);
        } else if ([
          'TIME:SYNC:FAILED',
          'TIME:SYNC:REJECTED',
          'TIME:SYNC:REQUIRED',
          'EVENTLOG:CONSENT_REQUIRED',
          'EVENTLOG:UNAVAILABLE',
          'EVENTLOG:ACK:REJECTED'
        ].contains(message)) {
          if (message == 'EVENTLOG:EMPTY' ||
              message == 'EVENTLOG:RECORD_READY') {
            _nextReply = message;
          }
          if (message.startsWith('EVENTLOG:ACK:')) _ackReply = message;
          _pending!.complete(false);
        }
      }
      if (message == 'EVENTLOG:RECORD_READY' &&
          importAuthorized &&
          !importing) {
        _requestLifecycleRefresh();
      }
      _changed();
      return true;
    }
    if (message == 'SESSION:ENDED') sessionEndRevision++;
    if (message == 'SESSION:STARTED') {
      _sessionSnapshot = null;
      _deviceSessionSeconds = 0;
    }
    if (message == 'SESSION:ENDED' ||
        message == 'SESSION:STARTED' ||
        message.startsWith('MODE:APPLIED:')) {
      _requestLifecycleRefresh();
    }

    if (message.startsWith('SESSION:SYNC:')) {
      debugPrint('[PoiseBleService] RX FFE1 $message');
      final match = RegExp(r'^SESSION:SYNC:([^,\s]+),ELAPSED_MS:([0-9]+)$')
          .firstMatch(message);
      final milliseconds = match == null ? null : int.tryParse(match[2]!);
      if (milliseconds != null) {
        _receivedSession = true;
        _sessionSnapshot = PoiseSessionSnapshot(
            match![1]!, Duration(milliseconds: milliseconds));
        _deviceSessionSeconds = _sessionSnapshot!.elapsed.inSeconds;
        if (_pending != null &&
            !_pending!.isCompleted &&
            _expected.isEmpty &&
            _snapshotComplete) {
          _pending!.complete(true);
        }
        _changed();
      }
      return true;
    }
    final config =
        RegExp(r'^CONFIG:MODE:([1-4]),VIB:([01])$').firstMatch(message);
    if (config != null) {
      _snapshotMode = ActivityMode.values[int.parse(config[1]!) - 1];
      _snapshotVibration = config[2] == '1';
      _receivedConfig = true;
      if (isModeSynchronized && !commandPending) {
        _confirmConfig(_snapshotMode!, _snapshotVibration!);
      }
    } else {
      final states = <String, PoiseDeviceState>{
        'STATE:IDLE': PoiseDeviceState.idle,
        'STATE:CALIBRATION_READY': PoiseDeviceState.calibrationReady,
        'STATE:CALIBRATING': PoiseDeviceState.calibrating,
        'STATE:MONITORING': PoiseDeviceState.monitoring,
        'STATE:PAUSED': PoiseDeviceState.paused,
        'STATE:CHARGING_LOCKOUT': PoiseDeviceState.chargingLockout,
        'STATE:ERROR': PoiseDeviceState.error,
        'SESSION:STARTED': PoiseDeviceState.monitoring,
        'SESSION:RESUMED': PoiseDeviceState.monitoring,
        'SESSION:PAUSED': PoiseDeviceState.paused,
        'SESSION:ENDED': PoiseDeviceState.idle,
      };
      if (states.containsKey(message)) {
        deviceState = states[message]!;
        if (deviceState == PoiseDeviceState.idle) {
          _sessionSnapshot = null;
          _deviceSessionSeconds = 0;
        }
        if (message.startsWith('STATE:')) _receivedState = true;
        if (deviceState == PoiseDeviceState.error ||
            deviceState == PoiseDeviceState.chargingLockout) {
          protocolError = deviceState == PoiseDeviceState.error
              ? 'Device reported an error.'
              : 'Charging: session controls unavailable.';
          if (!_activeCommand.startsWith('TIME:') &&
              !_activeCommand.startsWith('EVENTLOG:') &&
              _expected.isNotEmpty &&
              _pending != null &&
              !_pending!.isCompleted) {
            _pending!.complete(false);
          }
        }
      } else if (RegExp(r'^MODE:APPLIED:[1-4]$').hasMatch(message)) {
        _confirmConfig(
            ActivityMode.values[int.parse(message.split(':').last) - 1],
            vibrationEnabled);
      } else if (RegExp(r'^VIB:APPLIED:[01]$').hasMatch(message)) {
        _confirmConfig(_hardwareActiveMode, message.endsWith('1'));
      } else {
        return message.startsWith('STATE:') ||
            message.startsWith('CONFIG:') ||
            message.startsWith('MODE:') ||
            message.startsWith('VIB:');
      }
    }
    if (_pending != null && !_pending!.isCompleted) {
      if (_expected.contains(message) ||
          (_expected.isEmpty && _snapshotComplete)) {
        _pending!.complete(true);
      }
    }
    _changed();
    return true;
  }

  Future<bool> _exchange(String command, Set<String> expected) {
    final generation = connectionGeneration;
    Future<bool> run() async {
      if (generation != connectionGeneration) return false;
      return _performExchange(command, expected);
    }

    final result =
        (_queuedCommands++ == 0 ? run() : _commandQueue.then((_) => run()))
            .whenComplete(() => _queuedCommands--);
    _commandQueue =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> _performExchange(String command, Set<String> expected) async {
    if (!isConnected || commandPending) return false;
    if (command == 'TIME:SYNC:') {
      command += DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    }
    if (command == 'EVENTLOG:NEXT') _nextReply = null;
    if (command.startsWith('EVENTLOG:ACK:')) _ackReply = null;
    _activeCommand = command;
    final pending = Completer<bool>();
    _pending = pending;
    _expected = expected;
    protocolError = null;
    _changed();
    try {
      debugPrint('[PoiseBleService] TX FFE2 $command');
      if (commandWriter != null) {
        await commandWriter!(command).timeout(responseTimeout);
      } else if (_calibrationChar != null) {
        await _calibrationChar!
            .write(utf8.encode(command),
                withoutResponse: !_calibrationChar!.properties.write)
            .timeout(responseTimeout);
      } else if (_activeDevice == null && allowsSimulation) {
        if (command == 'STATE:SYNC') {
          receiveMessage(
              'STATE:${deviceState == PoiseDeviceState.chargingLockout ? 'CHARGING_LOCKOUT' : deviceState == PoiseDeviceState.calibrationReady ? 'CALIBRATION_READY' : deviceState.name.toUpperCase()}');
          receiveMessage(
              'CONFIG:MODE:${_hardwareActiveMode.index + 1},VIB:${vibrationEnabled ? 1 : 0}');
          if (deviceState == PoiseDeviceState.monitoring ||
              deviceState == PoiseDeviceState.paused) {
            receiveMessage('SESSION:SYNC:simulation,ELAPSED_MS:0');
          }
        } else if (command == 'EVENTLOG:STATUS') {
          receiveMessage('EVENTLOG:PENDING:0');
        } else {
          receiveMessage(expected.first);
        }
      } else {
        throw StateError('FFE2 is unavailable');
      }
      final accepted = await pending.future.timeout(responseTimeout);
      if (!accepted) throw StateError('Device unavailable or command rejected');
      return isConnected;
    } catch (_) {
      protocolError = isConnected
          ? 'Device did not confirm $command. Synchronize or reconnect to retry.'
          : 'Device disconnected. Reconnect to continue.';
      _isModeSynchronized = false;
      return false;
    } finally {
      if (identical(_pending, pending)) _pending = null;
      _changed();
    }
  }

  @visibleForTesting
  bool simulateForTesting = false;
  @visibleForTesting
  bool simulateScanFindsDevice = true;
  @visibleForTesting
  Future<bool> Function()? permissionRequester;

  static const _accessChannel = MethodChannel('poise/bluetooth_access');

  /// Ask before inspecting the adapter or discovering devices on Android.
  Future<bool> requestBluetoothPermissions() async {
    try {
      if (permissionRequester != null) return await permissionRequester!();
      if (allowsSimulation || defaultTargetPlatform != TargetPlatform.android) {
        return true;
      }
      return await _accessChannel.invokeMethod<bool>('requestPermissions') ??
          false;
    } catch (e) {
      debugPrint('[PoiseBleService] Bluetooth permission request failed: $e');
      return false;
    }
  }

  Future<void> openBluetoothPermissionSettings() async {
    if (!allowsSimulation && defaultTargetPlatform == TargetPlatform.android) {
      await _accessChannel.invokeMethod<void>('openSettings');
    }
  }

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
  PoiseSessionSnapshot? _sessionSnapshot;
  PoiseSessionSnapshot? get sessionSnapshot => _sessionSnapshot;

  void updateDeviceSessionSeconds(int seconds) {
    if (seconds >= 0 && seconds <= 86400 && seconds != _deviceSessionSeconds) {
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
      isConnected &&
      _isModeSynchronized &&
      (_hardwareActiveMode == _phoneSavedMode);

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
      if (!simulateScanFindsDevice) return;
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
    connectionGeneration++;
    clockSynchronized = false;
    clockStatus = 'required';
    importAuthorized = false;
    pendingEventCount = 0;
    _isModeSynchronized = false;
    _watchAdapter();
    await stopScan();
    _setState(PoiseBleState.connecting);

    if (device.rawDevice == null) {
      // Simulated / Mock connection
      _connectedDeviceName = device.name;
      _setState(PoiseBleState.connected);
      await _rememberDevice(device);
      await _initializeProtocol();
      await DeviceSession.completeSetup();
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
      await _initializeProtocol();
      await DeviceSession.completeSetup();
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

          if (service.uuid == Guid(PoiseBleConfig.serviceUuid) &&
              char.uuid == Guid(PoiseBleConfig.eventCharacteristicUuid) &&
              char.properties.read) {
            _eventChar = char;
          }
          if (service.uuid == Guid(PoiseBleConfig.serviceUuid) &&
              char.uuid == Guid(PoiseBleConfig.calibrationCharacteristicUuid)) {
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
          if (batteryChar.properties.notify ||
              batteryChar.properties.indicate) {
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

      if (telemetryChar == null ||
          _calibrationChar == null ||
          !(_calibrationChar!.properties.write ||
              _calibrationChar!.properties.writeWithoutResponse)) {
        throw StateError(
            'Expected FFE0 service with FFE1 notify and FFE2 write');
      }
      await _charValueSubscription?.cancel();
      _charValueSubscription =
          telemetryChar.onValueReceived.listen(_handleIncomingTelemetry);
      await telemetryChar.setNotifyValue(true);
      debugPrint('[PoiseBleService] Subscribed to FFE1 notifications');
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
      if (str.contains('\n')) {
        for (final line in str.split(RegExp(r'[\r\n]+'))) {
          if (line.isNotEmpty) receiveMessage(line);
        }
        return;
      }
      if (_handleProtocol(str)) return;

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
        final clean = str
            .replaceFirst(RegExp(r'^(SESSION:|ELAPSED:|UPTIME:)'), '')
            .trim();
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

    // Never reinterpret unknown ASCII responses as binary measurements.
    if (bytes.every((b) => b >= 32 && b <= 126) && rawAngle == null) return;

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

  void _applyCalibratedPitch(double rawAngle,
      {bool isHardwareDeviation = true}) {
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
    final device = _activeDevice;
    final connectionSubscription = _deviceStateSubscription;
    _deviceStateSubscription = null;
    // Disable controls synchronously, before waiting for platform cleanup.
    _handleDisconnection();
    await connectionSubscription?.cancel();
    try {
      await device?.disconnect();
    } catch (_) {}
  }

  void _handleDisconnection() {
    connectionGeneration++;
    clockSynchronized = false;
    clockStatus = 'required';
    importAuthorized = false;
    importing = false;
    pendingEventCount = 0;
    _eventChar = null;
    _importRecheckRequested = false;
    _refreshRequested = false;
    _stopMockTelemetryStream();
    _activeDevice = null;
    _connectedDeviceName = null;
    _charValueSubscription?.cancel();
    _charValueSubscription = null;
    _batteryCharSubscription?.cancel();
    _batteryCharSubscription = null;
    _calibrationChar = null;
    if (_pending != null && !_pending!.isCompleted) _pending!.complete(false);
    _receivedState = false;
    _receivedSession = false;
    _receivedConfig = false;
    protocolError = 'Device disconnected. Reconnect to continue.';
    _isModeSynchronized = false;
    if (!_modeSyncController.isClosed) {
      _modeSyncController.add(false);
    }
    _setState(PoiseBleState.disconnected);
    _changed();
  }

  /// Separate calibration action; the firmware owns the baseline.
  Future<void> setZeroBaseline({double? baselinePitch}) async {
    await sendSessionCommand('CALIBRATE');
  }

  Future<bool> sendSessionCommand(String command) async {
    if (!sessionControlsEnabled) return false;
    if (['CALIBRATION:READY', 'CALIBRATE', 'SESSION:START'].contains(command) &&
        !clockSynchronized) {
      protocolError =
          'Synchronize the device clock before starting a new session.';
      _changed();
      return false;
    }
    if (command.startsWith('CALIBRATION:') &&
        deviceState != PoiseDeviceState.idle &&
        deviceState != PoiseDeviceState.calibrationReady) {
      return false;
    }
    final responses = <String, Set<String>>{
      'CALIBRATION:READY': {'STATE:CALIBRATION_READY'},
      'CALIBRATION:CANCEL': {'STATE:IDLE'},
      'SESSION:START': {'STATE:MONITORING', 'SESSION:STARTED'},
      'SESSION:PAUSE': {'STATE:PAUSED', 'SESSION:PAUSED'},
      'SESSION:RESUME': {'STATE:MONITORING', 'SESSION:RESUMED'},
      'SESSION:END': {'STATE:IDLE', 'SESSION:ENDED'},
      'CALIBRATE': {'STATE:MONITORING', 'SESSION:STARTED'},
    };
    if (!responses.containsKey(command)) return false;
    final success = await _exchange(command, responses[command]!);
    if (!success && isConnected) await _recoverAfterCommandFailure();
    return success;
  }

  /// Requests state and saved configuration; never pushes phone defaults.
  Future<bool> syncSavedModeToHardware() async {
    if (!isConnected || commandPending) return false;
    _isModeSynchronized = false;
    _receivedState = false;
    _receivedSession = false;
    _receivedConfig = false;
    final success = await _exchange('STATE:SYNC', {});
    _isModeSynchronized = success && _receivedState && _receivedConfig;
    if (_isModeSynchronized) {
      _confirmConfig(_snapshotMode!, _snapshotVibration!);
    }
    _changed();
    return isModeSynchronized;
  }

  Future<void> _recoverAfterCommandFailure() async {
    final failure = protocolError;
    final restored = await syncSavedModeToHardware();
    if (restored && failure != null) {
      protocolError = failure;
      _changed();
    }
  }

  Future<bool> sendModeCommand(ActivityMode mode) async {
    if (!controlsEnabled) return false;
    final id = ModeModel.idForActivityMode(mode);
    _lastSentModeCommand = 'MODE:$id';
    final success = await _exchange('MODE:$id', {'MODE:APPLIED:$id'});
    if (!success && isConnected) unawaited(_recoverAfterCommandFailure());
    return success;
  }

  Future<bool> sendVibrationCommand(bool enabled) async {
    if (!controlsEnabled) return false;
    final value = enabled ? 1 : 0;
    final success = await _exchange('VIB:$value', {'VIB:APPLIED:$value'});
    if (!success && isConnected) unawaited(_recoverAfterCommandFailure());
    return success;
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
    connectionGeneration++;
    clockSynchronized = false;
    clockStatus = 'required';
    importAuthorized = false;
    importing = false;
    pendingEventCount = 0;
    importError = null;
    eventReader = null;
    eventCommitter = null;
    _eventChar = null;
    _importRecheckRequested = false;
    _refreshRequested = false;
    _importRecheckRequested = false;
    _commandQueue = Future.value();
    stopMockTelemetryStream();
    _adapterSubscription?.cancel();
    _adapterSubscription = null;
    _connecting = false;
    commandWriter = null;
    responseTimeout = const Duration(seconds: 8);
    _pending = null;
    _expected = {};
    _receivedConfig = false;
    _receivedState = false;
    protocolError = null;
    deviceState = PoiseDeviceState.idle;
    vibrationEnabled = true;
    _calibrationChar = null;
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
    _sessionSnapshot = null;
    _batteryLevel = 100;
    _hardwareActiveMode = ActivityMode.normal;
    _phoneSavedMode = ActivityMode.normal;
    ModePreferences.resetForTesting();
    _isModeSynchronized = false;
    _lastSentModeCommand = null;
    simulateQuickSettingsSynced = false;
    simulateScanFindsDevice = true;
    permissionRequester = null;
    _state = PoiseBleState.disconnected;
  }

  /// Release resources
  @override
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
    super.dispose();
  }
}
