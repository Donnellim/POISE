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
    if (state == 'MONITORING' || state == 'PAUSED') {
      ble.receiveMessage('SESSION:SYNC:test-session,ELAPSED_MS:0');
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ble.resetForTesting();
    ble.simulateForTesting = true;
    commands.clear();
    ble.commandWriter = (command) async {
      if (command.startsWith('TIME:SYNC:')) {
        ble.receiveMessage('TIME:SYNC:OK');
        return;
      }
      if (command == 'EVENTLOG:STATUS') {
        ble.receiveMessage('EVENTLOG:PENDING:0');
        return;
      }
      commands.add(command);
      if (command == 'STATE:SYNC') {
        snapshot(
            mode: commands.contains('MODE:3') ? 3 : 4,
            state: ble.deviceState.name.toUpperCase());
      }
      if (command == 'CALIBRATION:READY') {
        ble.receiveMessage('STATE:CALIBRATION_READY');
      }
      if (command == 'CALIBRATION:CANCEL') ble.receiveMessage('STATE:IDLE');
    };
  });
  tearDown(() async {
    await ble.disconnect();
    ble.resetForTesting();
  });

  testWidgets('Home QA: disconnected presentation and idle connection',
      (tester) async {
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    addTearDown(() => PoiseLocalDatabase.instance.mockRecordsForTesting = null);
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DashboardTab(activeMode: ActivityMode.normal))));
    await tester.pump();
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.textContaining('Saved:'), findsNothing);
    final summary = find.byKey(const ValueKey('active-mode-summary'));
    expect(find.descendant(of: summary, matching: find.byType(Icon)),
        findsNothing);
    expect(find.text('--:--:--'), findsOneWidget);
    expect(find.text('---'), findsNWidgets(2));
    expect(find.text(ActivityMode.normal.label), findsNothing);
    expect(find.text(ActivityMode.normal.threshold), findsNothing);
    final toggle = find.byKey(const ValueKey('session-toggle'));
    expect(tester.widget<GestureDetector>(toggle).onTap, isNull);
    final background = tester.widget<Container>(
        find.descendant(of: toggle, matching: find.byType(Container)).first);
    expect((background.decoration as BoxDecoration).color,
        const Color(0xFFA5DCF2));
    await tester.tap(toggle);
    await tester.pump();
    expect(commands, isEmpty);

    await tester.runAsync(() => ble.connect(device));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('Start Session'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('End Session'), findsNothing);
    expect(tester.widget<GestureDetector>(toggle).onTap, isNotNull);
    expect(find.descendant(of: summary, matching: find.byType(Icon)),
        findsOneWidget);
    expect(commands, ['STATE:SYNC']);
    await tester.pumpWidget(const SizedBox());
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
      if (command.startsWith('TIME:SYNC:')) {
        ble.receiveMessage('TIME:SYNC:OK');
        return;
      }
      if (command == 'EVENTLOG:STATUS') {
        ble.receiveMessage('EVENTLOG:PENDING:0');
        return;
      }
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
    expect(ble.controlsEnabled, isFalse);
    ble.receiveMessage('SESSION:SYNC:paused-session,ELAPSED_MS:0');
    await connection;
    expect(ble.controlsEnabled, isTrue);
    expect(ble.deviceState, PoiseDeviceState.paused);
    expect(ble.hardwareActiveMode, ActivityMode.focus);
  });

  test('every session snapshot is parsed, including unchanged IDs and zero',
      () async {
    await ble.connect(device);
    ble.receiveMessage('STATE:MONITORING');
    ble.receiveMessage('SESSION:SYNC:42,ELAPSED_MS:12500');
    final first = ble.sessionSnapshot;
    expect(first!.id, '42');
    expect(first.elapsed.inMilliseconds, 12500);
    ble.receiveMessage('SESSION:SYNC:42,ELAPSED_MS:42500');
    expect(ble.deviceSessionSeconds, 42);
    expect(identical(first, ble.sessionSnapshot), isFalse);
    final latest = ble.sessionSnapshot;
    for (final payload in ['-1', 'oops', '12.5', '']) {
      ble.receiveMessage('SESSION:SYNC:42,ELAPSED_MS:$payload');
      expect(identical(latest, ble.sessionSnapshot), isTrue);
    }
    ble.receiveMessage('SESSION:SYNC:42,ELAPSED_MS:0');
    expect(ble.deviceSessionSeconds, 0);
    ble.receiveMessage('SESSION:STARTED');
    expect(ble.sessionSnapshot, isNull);
  });

  for (final sessionFirst in [true, false]) {
    testWidgets(
        'reconnection corrects same-session timer; session first: '
        '$sessionFirst', (tester) async {
      PoiseLocalDatabase.instance.mockRecordsForTesting = [];
      addTearDown(
          () => PoiseLocalDatabase.instance.mockRecordsForTesting = null);
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var elapsed = 12000;
      var state = 'MONITORING';
      ble.commandWriter = (command) async {
        if (command.startsWith('TIME:SYNC:')) {
          ble.receiveMessage('TIME:SYNC:OK');
          return;
        }
        if (command == 'EVENTLOG:STATUS') {
          ble.receiveMessage('EVENTLOG:PENDING:0');
          return;
        }
        commands.add(command);
        if (command != 'STATE:SYNC') return;
        void session() =>
            ble.receiveMessage('SESSION:SYNC:42,ELAPSED_MS:$elapsed');
        if (sessionFirst) session();
        ble.receiveMessage('STATE:$state');
        ble.receiveMessage('CONFIG:MODE:4,VIB:0');
        if (!sessionFirst) session();
      };
      // Snapshot arriving before the dashboard mounts must also be restored.
      await ble.connect(device);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: DashboardTab(activeMode: ActivityMode.commuting))));
      await tester.pump();
      expect(find.text('00:00:12'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:00:14'), findsOneWidget);
      await ble.disconnect();
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('--:--:--'), findsOneWidget);
      elapsed = 44000;
      await ble.connect(device);
      await tester.pump();
      expect(commands, ['STATE:SYNC', 'STATE:SYNC']);
      expect(find.text('00:00:44'), findsOneWidget);
      expect(find.text('Set Your Neutral Posture'), findsNothing);
      ble.receiveMessage('SESSION:STARTED');
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:00:46'), findsOneWidget);
      // Even an identical snapshot must correct local extrapolation.
      ble.receiveMessage('SESSION:SYNC:42,ELAPSED_MS:44000');
      await tester.pump();
      expect(find.text('00:00:44'), findsOneWidget);
      await ble.disconnect();
      elapsed = 47000;
      state = 'PAUSED';
      await ble.connect(device);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('00:00:47'), findsOneWidget);
      expect(find.text('Set Your Neutral Posture'), findsNothing);
      expect(
          commands, ['STATE:SYNC', 'STATE:SYNC', 'STATE:SYNC', 'STATE:SYNC']);
      ble.receiveMessage('STATE:MONITORING');
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:00:49'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('mode and vibration only change after corresponding acknowledgment',
      () async {
    await ble.connect(device);
    final mode = ble.sendModeCommand(ActivityMode.leisure);
    expect(ble.hardwareActiveMode, ActivityMode.commuting);
    expect(ble.controlsEnabled, isFalse);
    ble.receiveMessage('MODE:APPLIED:3');
    expect(await mode, isTrue);
    await Future<void>.delayed(Duration.zero);
    final vibration = ble.sendVibrationCommand(true);
    expect(ble.vibrationEnabled, isFalse);
    ble.receiveMessage('VIB:APPLIED:1');
    expect(await vibration, isTrue);
    expect(ble.vibrationEnabled, isTrue);
    await ble.disconnect();
    ble.commandWriter = (command) async {
      if (command.startsWith('TIME:SYNC:')) {
        ble.receiveMessage('TIME:SYNC:OK');
        return;
      }
      if (command == 'EVENTLOG:STATUS') {
        ble.receiveMessage('EVENTLOG:PENDING:0');
        return;
      }
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
      ble.commandWriter = (command) async {
        if (command.startsWith('TIME:SYNC:')) {
          ble.receiveMessage('TIME:SYNC:OK');
          return;
        }
        if (command == 'EVENTLOG:STATUS') {
          ble.receiveMessage('EVENTLOG:PENDING:0');
          return;
        }
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

  testWidgets('Step 19 prepares, cancels, and confirms every new session',
      (tester) async {
    PoiseLocalDatabase.instance.mockRecordsForTesting = [];
    addTearDown(() => PoiseLocalDatabase.instance.mockRecordsForTesting = null);
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await ble.connect(device);
    await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: DashboardTab(activeMode: ActivityMode.commuting))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('session-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(commands, ['STATE:SYNC', 'CALIBRATION:READY', 'CALIBRATION:CANCEL']);
    for (var session = 0; session < 2; session++) {
      await tester.tap(find.byKey(const ValueKey('session-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Set Your Neutral Posture'), findsOneWidget);
      expect(commands.where((c) => c == 'CALIBRATE').length, session);
      expect(ble.deviceState, PoiseDeviceState.calibrationReady);
      expect(find.text('00:00:00'), findsOneWidget);
      await tester.tap(find.text('Set Calibration'));
      await tester.pump();
      expect(commands.where((c) => c == 'CALIBRATE').length, session + 1);
      expect(commands, isNot(contains('SESSION:START')));
      expect(find.text('End Session'), findsNothing);
      ble.receiveMessage('STATE:CALIBRATING');
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('00:00:00'), findsOneWidget);
      ble.receiveMessage('SESSION:STARTED');
      await tester.pump();
      expect(find.text('End Session'), findsOneWidget);
      ble.receiveMessage('SESSION:ENDED');
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final dismissal in ['back', 'outside', 'disconnect']) {
    testWidgets('Step 19 handles $dismissal while READY is pending',
        (tester) async {
      PoiseLocalDatabase.instance.mockRecordsForTesting = [];
      addTearDown(
          () => PoiseLocalDatabase.instance.mockRecordsForTesting = null);
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ble.connect(device);
      ble.commandWriter = (command) async {
        if (command.startsWith('TIME:SYNC:')) {
          ble.receiveMessage('TIME:SYNC:OK');
          return;
        }
        if (command == 'EVENTLOG:STATUS') {
          ble.receiveMessage('EVENTLOG:PENDING:0');
          return;
        }
        commands.add(command);
        if (command == 'CALIBRATION:CANCEL') ble.receiveMessage('STATE:IDLE');
      };
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: DashboardTab(activeMode: ActivityMode.commuting))));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('session-toggle')));
      await tester.pumpAndSettle();
      expect(commands, ['STATE:SYNC', 'CALIBRATION:READY']);
      expect(
          tester
              .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'Set Calibration'))
              .onPressed,
          isNull);
      if (dismissal == 'outside') {
        await tester.tapAt(const Offset(5, 5));
      } else {
        if (dismissal == 'disconnect') await ble.disconnect();
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      if (dismissal != 'disconnect') {
        // Closing before READY arrives must serialize CANCEL after READY.
        expect(commands, ['STATE:SYNC', 'CALIBRATION:READY']);
        ble.receiveMessage('STATE:CALIBRATION_READY');
        await tester.pumpAndSettle();
        expect(commands.last, 'CALIBRATION:CANCEL');
        expect(ble.deviceState, PoiseDeviceState.idle);
      } else {
        expect(commands, ['STATE:SYNC', 'CALIBRATION:READY']);
      }
      expect(commands, isNot(contains('CALIBRATE')));
      expect(commands, isNot(contains('SESSION:START')));
      expect(find.text('End Session'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

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
    await tester.tap(find.byType(Switch).first);
    expect(changes, 0);
    expect(find.text('Select the mode based on what you are currently doing.'),
        findsOneWidget);
    expect(find.text('Saved on phone'), findsNothing);
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
    expect(find.text('Session'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-toggle')));
    await tester.pump();
    expect(commands, ['STATE:SYNC', 'CALIBRATION:READY']);
    expect(find.text('Set Your Neutral Posture'), findsOneWidget);
    await tester.tap(find.text('Set Calibration'));
    await tester.pump();
    expect(commands, ['STATE:SYNC', 'CALIBRATION:READY', 'CALIBRATE']);
    expect(find.text('End Session'), findsNothing);
    ble.receiveMessage('STATE:CALIBRATING');
    await tester.pump();
    expect(find.textContaining('Calibrating'), findsWidgets);
    expect(find.text('End Session'), findsNothing);
    final previousWriter = ble.commandWriter!;
    ble.commandWriter = (command) async {
      if (command == 'STATE:SYNC') {
        snapshot(state: 'MONITORING');
      } else {
        await previousWriter(command);
      }
    };
    ble.receiveMessage('SESSION:STARTED');
    await tester.pump();
    expect(find.text('End Session'), findsOneWidget);
    await tester.runAsync(() => ble.disconnect());
    await tester.pump();
    expect(find.text('--:--:--'), findsOneWidget);
    expect(
        tester
            .widget<GestureDetector>(
                find.byKey(const ValueKey('session-toggle')))
            .onTap,
        isNull);
    ble.commandWriter = (command) async {
      if (command.startsWith('TIME:SYNC:')) {
        ble.receiveMessage('TIME:SYNC:OK');
        return;
      }
      if (command == 'EVENTLOG:STATUS') {
        ble.receiveMessage('EVENTLOG:PENDING:0');
        return;
      }
      snapshot(state: 'PAUSED');
    };
    await tester.runAsync(() => ble.connect(device));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
