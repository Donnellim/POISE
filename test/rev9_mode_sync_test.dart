import 'package:flutter_application_1/tabs/dashboard_tab.dart';
import 'package:flutter_application_1/database/local_database.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/activity_mode.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter_application_1/tabs/controls_tab.dart';

void main() {
  final ble = PoiseBleService.instance;
  final commands = <String>[];
  const device =
      PoiseDiscoveredDevice(id: 'SIMULATED-POISE', name: 'POISE', rssi: -50);
  void snapshot({String state = 'IDLE', int mode = 4, int vib = 0}) {
    ble.receiveMessage('STATE:$state');
    ble.receiveMessage('CONFIG:MODE:$mode,VIB:$vib');
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ble.resetForTesting();
    ble.simulateForTesting = true;
    commands.clear();
    ble.commandWriter = (command) async {
      commands.add(command);
      if (command == 'STATE:SYNC') snapshot();
    };
  });
  tearDown(() async {
    await ble.disconnect();
    ble.resetForTesting();
  });

  test(
      'connection only requests snapshot; disconnect preserves configuration and rejects commands',
      () async {
    expect(await ble.connect(device), isTrue);
    expect(commands, ['STATE:SYNC']);
    expect(ble.controlsEnabled, isTrue);
    expect(ble.hardwareActiveMode, ActivityMode.commuting);
    expect(ble.vibrationEnabled, isFalse);
    await ble.disconnect();
    expect(ble.controlsEnabled, isFalse);
    expect(ble.hardwareActiveMode, ActivityMode.commuting);
    expect(ble.vibrationEnabled, isFalse);
    expect(await ble.sendModeCommand(ActivityMode.focus), isFalse);
    expect(await ble.sendVibrationCommand(true), isFalse);
    expect(await ble.sendSessionCommand('SESSION:START'), isFalse);
    expect(commands, ['STATE:SYNC']);
    await ble.connect(device);
    expect(commands, ['STATE:SYNC', 'STATE:SYNC']);
    expect(ble.hardwareActiveMode, ActivityMode.commuting);
  });

  test('state and configuration must both arrive before enabling controls',
      () async {
    final sent = Completer<void>();
    ble.commandWriter = (command) async {
      commands.add(command);
      sent.complete();
    };
    final connection = ble.connect(device);
    await sent.future;
    ble.receiveMessage('STATE:PAUSED');
    expect(ble.controlsEnabled, isFalse);
    ble.receiveMessage('12.5');
    expect(ble.currentPitchAngle, 12.5);
    expect(ble.controlsEnabled, isFalse);
    ble.receiveMessage('CONFIG:MODE:2,VIB:1');
    await connection;
    expect(ble.controlsEnabled, isTrue);
    expect(ble.deviceState, PoiseDeviceState.paused);
    expect(ble.hardwareActiveMode, ActivityMode.focus);
  });

  test('mode and vibration only change after corresponding acknowledgment',
      () async {
    await ble.connect(device);
    final mode = ble.sendModeCommand(ActivityMode.leisure);
    expect(ble.hardwareActiveMode, ActivityMode.commuting);
    expect(ble.controlsEnabled, isFalse);
    ble.receiveMessage('MODE:APPLIED:3');
    expect(await mode, isTrue);
    final vibration = ble.sendVibrationCommand(true);
    expect(ble.vibrationEnabled, isFalse);
    ble.receiveMessage('VIB:APPLIED:1');
    expect(await vibration, isTrue);
    expect(ble.vibrationEnabled, isTrue);
    await ble.disconnect();
    ble.commandWriter = (command) async {
      commands.add(command);
      snapshot(mode: 3, vib: 1);
    };
    await ble.connect(device);
    expect(ble.hardwareActiveMode, ActivityMode.leisure);
    expect(ble.vibrationEnabled, isTrue);
  });

  test('start sends one command and follows calibration then monitoring',
      () async {
    await ble.connect(device);
    final start = ble.sendSessionCommand('SESSION:START');
    expect(ble.deviceState, PoiseDeviceState.idle);
    ble.receiveMessage('STATE:CALIBRATING');
    expect(ble.deviceState, PoiseDeviceState.calibrating);
    expect(ble.sessionControlsEnabled, isFalse);
    ble.receiveMessage('STATE:MONITORING');
    expect(await start, isTrue);
    expect(commands, ['STATE:SYNC', 'SESSION:START']);
    for (final entry in {
      'SESSION:PAUSE': 'SESSION:PAUSED',
      'SESSION:RESUME': 'SESSION:RESUMED',
      'SESSION:END': 'SESSION:ENDED'
    }.entries) {
      final result = ble.sendSessionCommand(entry.key);
      ble.receiveMessage(entry.value);
      expect(await result, isTrue);
    }
    expect(ble.deviceState, PoiseDeviceState.idle);
  });

  test('disconnect during a command never reports success', () async {
    await ble.connect(device);
    final start = ble.sendSessionCommand('SESSION:START');
    ble.receiveMessage('STATE:CALIBRATING');
    await ble.disconnect();
    expect(await start, isFalse);
    expect(ble.sessionControlsEnabled, isFalse);
    expect(ble.protocolError, contains('disconnected'));
  });

  test('missing or malformed synchronization retains confirmed settings',
      () async {
    await ble.connect(device);
    ble.responseTimeout = const Duration(milliseconds: 20);
    ble.commandWriter = (_) async {
      ble.receiveMessage('STATE:IDLE');
      ble.receiveMessage('CONFIG:MODE:9,VIB:1');
    };
    expect(await ble.syncSavedModeToHardware(), isFalse);
    expect(ble.controlsEnabled, isFalse);
    expect(ble.hardwareActiveMode, ActivityMode.commuting);
    expect(ble.vibrationEnabled, isFalse);
    expect(ble.protocolError, contains('STATE:SYNC'));
  });

  test('lost acknowledgment requests synchronization without assuming success',
      () async {
    await ble.connect(device);
    ble.responseTimeout = const Duration(milliseconds: 20);
    expect(await ble.sendModeCommand(ActivityMode.normal), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(commands, ['STATE:SYNC', 'MODE:1', 'STATE:SYNC']);
    expect(ble.hardwareActiveMode, ActivityMode.commuting);
  });

  for (final state in [
    'IDLE',
    'PAUSED',
    'MONITORING',
    'CHARGING_LOCKOUT',
    'ERROR'
  ]) {
    test('restore $state on reconnect', () async {
      ble.commandWriter = (_) async {
        snapshot(state: state);
      };
      await ble.connect(device);
      expect(
          ble.deviceState,
          {
            'IDLE': PoiseDeviceState.idle,
            'PAUSED': PoiseDeviceState.paused,
            'MONITORING': PoiseDeviceState.monitoring,
            'CHARGING_LOCKOUT': PoiseDeviceState.chargingLockout,
            'ERROR': PoiseDeviceState.error
          }[state]);
      expect(ble.sessionControlsEnabled,
          state != 'CHARGING_LOCKOUT' && state != 'ERROR');
    });
  }

  test('unknown ASCII messages never become posture readings', () async {
    await ble.connect(device);
    ble.receiveMessage('15.5');
    for (final message in [
      'CONFIG:MODE:99,VIB:1',
      'STATE:UNKNOWN',
      'ERROR:BAD_COMMAND',
      'MODE:APPLIED:7'
    ]) {
      ble.receiveMessage(message);
      expect(ble.currentPitchAngle, 15.5);
    }
  });

  testWidgets(
      'disconnected controls preserve visible values and have no callbacks',
      (tester) async {
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ControlsTab(
      selectedMode: ActivityMode.commuting,
      vibrationEnabled: false,
      onModeChanged: (_) => changes++,
      onVibrationChanged: (_) => changes++,
    ))));
    await tester.tap(find.text('Focus'));
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.first.value, isFalse);
    expect(switches.first.onChanged, isNull);
    expect(changes, 0);
    expect(find.textContaining('Device disconnected'), findsOneWidget);
  });
  testWidgets(
      'dashboard follows firmware calibration, monitoring, disconnect and paused reconnect',
      (tester) async {
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    addTearDown(() => PoiseLocalDatabase.instance.mockRecordsForTesting = null);
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ble.connect(device));
    await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: DashboardTab(activeMode: ActivityMode.commuting))));
    await tester.pump();
    expect(find.text('Session Inactive'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-toggle')));
    await tester.pump();
    expect(commands, ['STATE:SYNC', 'SESSION:START']);
    expect(find.text('Session Running'), findsNothing);
    ble.receiveMessage('STATE:CALIBRATING');
    await tester.pump();
    expect(find.textContaining('Calibrating'), findsWidgets);
    expect(find.text('Session Running'), findsNothing);
    ble.receiveMessage('SESSION:STARTED');
    await tester.pump();
    expect(find.text('Session Running'), findsOneWidget);
    await tester.runAsync(() => ble.disconnect());
    await tester.pump();
    expect(find.text('Session unavailable (disconnected)'), findsOneWidget);
    expect(
        tester
            .widget<GestureDetector>(
                find.byKey(const ValueKey('session-toggle')))
            .onTap,
        isNull);
    ble.commandWriter = (_) async {
      snapshot(state: 'PAUSED');
    };
    await tester.runAsync(() => ble.connect(device));
    await tester.pump();
    expect(find.text('Session Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
