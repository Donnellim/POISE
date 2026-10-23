import 'package:flutter/material.dart';
import 'package:flutter_application_1/tabs/analytics_tab.dart';
import 'dart:io';
import 'package:flutter_application_1/activity_mode.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter_application_1/database/device_posture_event.dart';
import 'package:flutter_application_1/database/local_database.dart';

Map<String, dynamic> record() => {
      'schema_version': 1,
      'is_final': true,
      'device_id': 'device-A',
      'event_id': 'event-1',
      'session_id': 'session-1',
      'start_time_ms': 1000,
      'end_time_ms': null,
      'timestamp_status': 'synced',
      'mode_id': 2,
      'peak_deviation_deg': 25.5,
      'vibration_count': 2,
      'correction_status': 'interrupted',
      'end_reason': 'mode_changed',
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ble = PoiseBleService.instance;
  final commands = <String>[];
  var nextCount = 0;
  const device =
      PoiseDiscoveredDevice(id: 'SIMULATED-A', name: 'POISE', rssi: -40);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ble.resetForTesting();
    ble.simulateForTesting = true;
    ble.responseTimeout = const Duration(milliseconds: 100);
    commands.clear();
    nextCount = 0;
    ble.commandWriter = (command) async {
      commands.add(command);
      if (command.startsWith('TIME:SYNC:')) ble.receiveMessage('TIME:SYNC:OK');
      if (command == 'STATE:SYNC') {
        ble.receiveMessage('STATE:IDLE');
        ble.receiveMessage('CONFIG:MODE:1,VIB:1');
      }
      if (command == 'EVENTLOG:STATUS') {
        ble.receiveMessage('EVENTLOG:PENDING:1');
      }
      if (command == 'EVENTLOG:START') {
        ble.receiveMessage('EVENTLOG:AUTHORIZED');
      }
      if (command == 'EVENTLOG:NEXT') {
        ble.receiveMessage(
            nextCount++ == 0 ? 'EVENTLOG:RECORD_READY' : 'EVENTLOG:EMPTY');
      }
      if (command.startsWith('EVENTLOG:ACK:')) {
        ble.receiveMessage('EVENTLOG:ACK:OK');
      }
    };
    ble.eventReader = () async => utf8.encode(jsonEncode(record()));
    ble.eventCommitter = (_) async {};
  });
  tearDown(() async {
    await ble.disconnect();
    ble.resetForTesting();
  });

  test('clock precedes snapshot/status and consent precedes import', () async {
    await ble.connect(device);
    expect(commands[0], matches(r'^TIME:SYNC:[0-9]+$'));
    expect(commands.sublist(1), ['STATE:SYNC', 'EVENTLOG:STATUS']);
    expect(ble.clockSynchronized, isTrue);
    expect(commands, isNot(contains('EVENTLOG:START')));
    await ble.importStoredEvents();
    expect(commands.sublist(3), [
      'EVENTLOG:START',
      'EVENTLOG:NEXT',
      'EVENTLOG:ACK:event-1',
      'EVENTLOG:NEXT'
    ]);
    expect(ble.importError, isNull);
  });
  test('ACK waits for commit completion', () async {
    await ble.connect(device);
    final commit = Completer<void>();
    final entered = Completer<void>();
    ble.eventCommitter = (_) {
      entered.complete();
      return commit.future;
    };
    final importing = ble.importStoredEvents();
    await entered.future;
    expect(commands.where((c) => c.startsWith('EVENTLOG:ACK:')), isEmpty);
    commit.complete();
    await importing;
    expect(commands, contains('EVENTLOG:ACK:event-1'));
  });
  test('SQLite failure never acknowledges', () async {
    await ble.connect(device);
    ble.eventCommitter = (_) async => throw StateError('disk full');
    await ble.importStoredEvents();
    expect(commands.where((c) => c.startsWith('EVENTLOG:ACK:')), isEmpty);
    expect(ble.importError, contains('disk full'));
  });
  test('truncated JSON never acknowledges', () async {
    await ble.connect(device);
    ble.eventReader = () async => utf8.encode('{"event_id":');
    await ble.importStoredEvents();
    expect(commands.where((c) => c.startsWith('EVENTLOG:ACK:')), isEmpty);
    expect(ble.importError, isNotNull);
  });
  test('disconnect during commit cannot ACK on a new connection', () async {
    await ble.connect(device);
    final commit = Completer<void>();
    final entered = Completer<void>();
    ble.eventCommitter = (_) {
      entered.complete();
      return commit.future;
    };
    final importing = ble.importStoredEvents();
    await entered.future;
    await ble.disconnect();
    await ble.connect(device);
    commit.complete();
    await importing;
    expect(ble.importAuthorized, isFalse);
    expect(commands.where((c) => c.startsWith('EVENTLOG:ACK:')), isEmpty);
  });
  test('deferred and failed clocks block fresh sessions until applied',
      () async {
    await ble.connect(device);
    for (final status in ['DEFERRED', 'FAILED', 'REJECTED', 'REQUIRED']) {
      ble.receiveMessage('TIME:SYNC:$status');
      expect(ble.clockSynchronized, isFalse);
      expect(await ble.sendSessionCommand('SESSION:START'), isFalse);
    }
    ble.receiveMessage('TIME:SYNC:APPLIED');
    expect(ble.clockSynchronized, isTrue);
  });
  test('ACK failure retries the committed event without advancing', () async {
    await ble.connect(device);
    final writer = ble.commandWriter!;
    var attempts = 0;
    ble.commandWriter = (command) async {
      if (command.startsWith('EVENTLOG:ACK:')) {
        commands.add(command);
        ble.receiveMessage(
            attempts++ == 0 ? 'EVENTLOG:ACK:FAILED' : 'EVENTLOG:ACK:OK');
      } else {
        await writer(command);
      }
    };
    await ble.importStoredEvents();
    expect(attempts, 2);
    expect(commands.sublist(3), [
      'EVENTLOG:START',
      'EVENTLOG:NEXT',
      'EVENTLOG:ACK:event-1',
      'EVENTLOG:ACK:event-1',
      'EVENTLOG:NEXT'
    ]);
  });
  for (final outcome in [
    'EVENTLOG:CONSENT_REQUIRED',
    'EVENTLOG:UNAVAILABLE',
    'EVENTLOG:ACK:REJECTED'
  ]) {
    test('protocol outcome $outcome stops import', () async {
      await ble.connect(device);
      final writer = ble.commandWriter!;
      ble.commandWriter = (command) async {
        if (command == 'EVENTLOG:START') {
          commands.add(command);
          ble.receiveMessage(outcome);
        } else {
          await writer(command);
        }
      };
      await ble.importStoredEvents();
      expect(ble.importError, isNotNull);
      expect(commands, isNot(contains('EVENTLOG:NEXT')));
    });
  }
  test('mode transition obtains a new session without calibration', () async {
    await ble.connect(device);
    final writer = ble.commandWriter!;
    ble.commandWriter = (command) async {
      if (command == 'MODE:2') {
        commands.add(command);
        ble.receiveMessage('MODE:APPLIED:2\nSESSION:ENDED\nSESSION:STARTED');
      } else if (command == 'STATE:SYNC') {
        commands.add(command);
        ble.receiveMessage(
            'STATE:MONITORING\nCONFIG:MODE:2,VIB:1\nSESSION:SYNC:new-session,ELAPSED_MS:0');
      } else {
        await writer(command);
      }
    };
    expect(await ble.sendModeCommand(ActivityMode.focus), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(ble.sessionSnapshot?.id, 'new-session');
    expect(ble.deviceState, PoiseDeviceState.monitoring);
    expect(commands.where((c) => c.startsWith('CALIBR')), isEmpty);
  });
  test('version 1 upgrade preserves legacy data', () async {
    final folder = await Directory.systemTemp.createTemp('poise-step21-');
    final local = PoiseLocalDatabase.instance;
    final path = '${folder.path}/migration.db';
    var db = await local.init(customPath: path);
    try {
      await db.insert('profiles', {
        'id': 'legacy',
        'created_at': '2026-01-01',
        'updated_at': '2026-01-01'
      });
      await db.execute('DROP TABLE device_posture_events');
      await db.execute('PRAGMA user_version = 1');
      await db.close();
      db = await local.init(customPath: path);
      expect(
          (await db.rawQuery('PRAGMA user_version')).single['user_version'], 2);
      expect(await db.query('profiles', where: 'id = ?', whereArgs: ['legacy']),
          hasLength(1));
      await local.commitDeviceEvent(DevicePostureEvent.parse(record()));
      expect(await local.getDeviceEvents(), hasLength(1));
    } finally {
      await db.close();
      await folder.delete(recursive: true);
    }
  });
  testWidgets('guest can view imported SQLite events with unknown end time',
      (tester) async {
    final local = PoiseLocalDatabase.instance;
    await tester.runAsync(() async {
      await local.init(customPath: ':memory:');
      await local.commitDeviceEvent(DevicePostureEvent.parse(record()));
    });
    await tester.runAsync(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: AnalyticsTab())));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Imported posture events (1)'), findsOneWidget);
    await tester.tap(find.text('Imported posture events (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unknown end'), findsOneWidget);
    expect(find.text('Sync imported history'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => local.close());
  });
  test('final record validation preserves partial timestamps', () {
    final event = DevicePostureEvent.parse(record());
    expect(event.durationMs, isNull);
    expect(event.data['start_time_ms'], 1000);
    expect(() => DevicePostureEvent.parse({...record(), 'is_final': false}),
        throwsFormatException);
    expect(() => DevicePostureEvent.parse({...record(), 'mode_id': 5}),
        throwsFormatException);
  });
  test('SQLite deduplicates exact records and rejects conflicts', () async {
    final local = PoiseLocalDatabase.instance;
    final db = await local.init(customPath: ':memory:');
    try {
      await local.commitDeviceEvent(DevicePostureEvent.parse(record()));
      await local.commitDeviceEvent(DevicePostureEvent.parse(record()));
      expect(await local.getDeviceEvents(), hasLength(1));
      await expectLater(
          local.commitDeviceEvent(
              DevicePostureEvent.parse({...record(), 'vibration_count': 9})),
          throwsStateError);
      expect((await local.getDeviceEvents()).single['vibration_count'], 2);
      expect((await local.getDeviceEvents()).single['owner_id'], isNull);
    } finally {
      await db.close();
    }
  });
}
