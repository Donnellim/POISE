import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_application_1/database/local_database.dart';
import 'package:flutter_application_1/database/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PoiseLocalDatabase Integrity & Platform Viability', () {
    setUp(() async {
      await PoiseLocalDatabase.instance.close();
      await PoiseLocalDatabase.instance.init(
        customPath: inMemoryDatabasePath,
      );
      await PoiseLocalDatabase.instance.clearAllData();
    });

    tearDown(() async {
      await PoiseLocalDatabase.instance.close();
    });

    test('Modes table is auto-seeded on initialization', () async {
      final modes = await PoiseLocalDatabase.instance.getAllModes();
      expect(modes.length, 4);
      expect(modes.map((m) => m.modeName), containsAll(['Normal', 'Focus', 'Leisure', 'Commuting']));
    });

    test('Profiles can be upserted and retrieved', () async {
      final now = DateTime.now();
      final profile = ProfileModel(
        id: 'usr_test_123',
        fullName: 'Test User',
        createdAt: now,
        updatedAt: now,
      );

      await PoiseLocalDatabase.instance.upsertProfile(profile);
      final fetched = await PoiseLocalDatabase.instance.getProfile('usr_test_123');
      expect(fetched, isNotNull);
      expect(fetched!.fullName, 'Test User');
      expect(fetched.id, 'usr_test_123');
    });

    test('Devices can be upserted and retrieved for a user', () async {
      final now = DateTime.now();
      // Insert profile first for foreign key integrity
      await PoiseLocalDatabase.instance.upsertProfile(ProfileModel(
        id: 'usr_test_123',
        fullName: 'Device Owner',
        createdAt: now,
        updatedAt: now,
      ));

      final device = DeviceModel(
        id: 'dev_ble_001',
        userId: 'usr_test_123',
        deviceName: 'POISE Device',
        pairedAt: now,
        lastSeenAt: now,
        updatedAt: now,
      );

      await PoiseLocalDatabase.instance.upsertDevice(device);
      final devices = await PoiseLocalDatabase.instance.getDevicesForUser('usr_test_123');
      expect(devices.length, 1);
      expect(devices.first.deviceName, 'POISE Device');
      expect(devices.first.toSupabaseMap()['device_name'], 'POISE Device');
    });

    test('Inserting session automatically inserts stub profile and device if needed', () async {
      final now = DateTime.now();
      final session = SessionModel(
        id: 'sess_100',
        deviceId: 'dev_stub_test',
        userId: 'usr_stub_test',
        modeId: 1,
        startedAt: now,
        updatedAt: now,
        synced: false,
      );

      // Should succeed without throwing FOREIGN KEY constraint failed
      await PoiseLocalDatabase.instance.insertSession(session);

      final active = await PoiseLocalDatabase.instance.getActiveSession('usr_stub_test');
      expect(active, isNotNull);
      expect(active!.id, 'sess_100');

      final unsynced = await PoiseLocalDatabase.instance.getUnsyncedSessions();
      expect(unsynced.any((s) => s.id == 'sess_100'), isTrue);

      await PoiseLocalDatabase.instance.markSessionsSynced(['sess_100']);
      final unsyncedAfter = await PoiseLocalDatabase.instance.getUnsyncedSessions();
      expect(unsyncedAfter.any((s) => s.id == 'sess_100'), isFalse);
    });

    test('Inserting posture events creates necessary prerequisites and queries by period', () async {
      final start = DateTime(2026, 10, 14, 10, 0);
      final event1 = PostureEventModel(
        id: 'evt_1',
        sessionId: 'sess_auto_1',
        occurredAt: DateTime(2026, 10, 14, 10, 15),
        tiltAngle: 18.5,
        durationSec: 3.0,
        feedbackTriggered: true,
        synced: false,
      );

      final event2 = PostureEventModel(
        id: 'evt_2',
        sessionId: 'sess_auto_1',
        occurredAt: DateTime(2026, 10, 14, 10, 30),
        tiltAngle: 22.0,
        durationSec: 4.5,
        feedbackTriggered: true,
        synced: false,
      );

      // Batch insert should succeed without FK errors
      await PoiseLocalDatabase.instance.insertPostureEventsBatch([event1, event2]);

      final eventsInPeriod = await PoiseLocalDatabase.instance.getEventsForPeriod(
        start,
        DateTime(2026, 10, 14, 11, 0),
      );
      expect(eventsInPeriod.length, 2);
      expect(eventsInPeriod.map((e) => e.tiltAngle), containsAll([18.5, 22.0]));

      final unsyncedEvents = await PoiseLocalDatabase.instance.getUnsyncedPostureEvents();
      expect(unsyncedEvents.length, 2);

      await PoiseLocalDatabase.instance.markPostureEventsSynced(['evt_1', 'evt_2']);
      final remaining = await PoiseLocalDatabase.instance.getUnsyncedPostureEvents();
      expect(remaining.isEmpty, isTrue);
    });

    test('restoreCloudData safely hydrates sessions and events marked synced', () async {
      final now = DateTime.now();
      final sessions = [
        SessionModel(
          id: 'cloud_sess_1',
          userId: 'usr_cloud_99',
          modeId: 2,
          startedAt: now.subtract(const Duration(hours: 2)),
          endedAt: now.subtract(const Duration(hours: 1)),
          updatedAt: now,
          synced: false,
        ),
      ];

      final events = [
        PostureEventModel(
          id: 'cloud_evt_1',
          sessionId: 'cloud_sess_1',
          occurredAt: now.subtract(const Duration(hours: 1, minutes: 45)),
          tiltAngle: 12.0,
          durationSec: 2.0,
          feedbackTriggered: true,
          synced: false,
        ),
      ];

      await PoiseLocalDatabase.instance.restoreCloudData(
        sessions: sessions,
        events: events,
      );

      final userSessions = await PoiseLocalDatabase.instance.getSessionsForUser('usr_cloud_99');
      expect(userSessions.length, 1);
      expect(userSessions.first.synced, isTrue);

      final sessionEvents = await PoiseLocalDatabase.instance.getEventsForSession('cloud_sess_1');
      expect(sessionEvents.length, 1);
      expect(sessionEvents.first.synced, isTrue);
    });

    test('getAllDevices returns all registered devices across users', () async {
      final now = DateTime.now();
      await PoiseLocalDatabase.instance.upsertDevice(DeviceModel(
        id: 'dev_1',
        userId: 'usr_a',
        deviceName: 'Device A',
        pairedAt: now,
        lastSeenAt: now,
        updatedAt: now,
      ));
      await PoiseLocalDatabase.instance.upsertDevice(DeviceModel(
        id: 'dev_2',
        userId: 'usr_b',
        deviceName: 'Device B',
        pairedAt: now,
        lastSeenAt: now,
        updatedAt: now,
      ));

      final all = await PoiseLocalDatabase.instance.getAllDevices();
      expect(all.length, 2);
    });

    test('Realtime session with 0.0 degree posture readings buffers properly and remains unsynced', () async {
      final now = DateTime.now();
      const sId = 'sess_realtime_001';
      const devId = 'POISE-DEVICE';

      await PoiseLocalDatabase.instance.insertSession(SessionModel(
        id: sId,
        deviceId: devId,
        userId: 'usr_realtime_user',
        modeId: 1,
        startedAt: now,
        updatedAt: now,
        synced: false,
      ));

      // Realtime 0.0° baseline / good posture reading
      await PoiseLocalDatabase.instance.insertPostureEvent(PostureEventModel(
        id: 'evt_realtime_001',
        sessionId: sId,
        occurredAt: now,
        tiltAngle: 0.0,
        durationSec: 0.0,
        feedbackTriggered: false,
        synced: false,
      ));

      final unsyncedSessions = await PoiseLocalDatabase.instance.getUnsyncedSessions();
      expect(unsyncedSessions.map((s) => s.id), contains(sId));

      final unsyncedEvents = await PoiseLocalDatabase.instance.getUnsyncedPostureEvents();
      expect(unsyncedEvents.map((e) => e.id), contains('evt_realtime_001'));
      expect(unsyncedEvents.firstWhere((e) => e.id == 'evt_realtime_001').tiltAngle, 0.0);
    });
  });
}
