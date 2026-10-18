import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_application_1/database/local_database.dart';
import 'package:flutter_application_1/database/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    // Open in-memory SQLite database for test isolation
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        // Invoke schema creation
        await db.execute('''
          CREATE TABLE profiles (
            id TEXT PRIMARY KEY,
            full_name TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE devices (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            device_name TEXT NOT NULL,
            paired_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE modes (
            id INTEGER PRIMARY KEY,
            mode_name TEXT NOT NULL,
            angle_threshold_deg REAL NOT NULL,
            forgiveness_time_sec REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            device_id TEXT,
            user_id TEXT NOT NULL,
            mode_id INTEGER NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            updated_at TEXT NOT NULL,
            baseline_angle REAL NOT NULL DEFAULT 0.0,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE posture_events (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            corrected_at TEXT,
            correction_time_sec REAL,
            tilt_angle REAL NOT NULL,
            duration_sec REAL NOT NULL,
            feedback_triggered INTEGER NOT NULL DEFAULT 1,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        for (final mode in ModeModel.defaultModes) {
          await db.insert('modes', mode.toMap());
        }
      },
    );
    PoiseLocalDatabase.instance.setDatabaseForTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Modes are seeded with correct presets', () async {
    final modes = await PoiseLocalDatabase.instance.getAllModes();
    expect(modes.length, 4);
    expect(modes[0].modeName, 'Normal');
    expect(modes[0].angleThresholdDeg, 15);
    expect(modes[0].forgivenessTimeSec, 2);

    expect(modes[1].modeName, 'Focus');
    expect(modes[1].angleThresholdDeg, 10);
    expect(modes[1].forgivenessTimeSec, 1);

    expect(modes[2].modeName, 'Leisure');
    expect(modes[2].angleThresholdDeg, 20);
    expect(modes[2].forgivenessTimeSec, 3);

    expect(modes[3].modeName, 'Commuting');
    expect(modes[3].angleThresholdDeg, 25);
    expect(modes[3].forgivenessTimeSec, 5);
  });

  test('Profiles and devices can be inserted, queried, and updated', () async {
    final now = DateTime.now();
    final profile = ProfileModel(
      id: 'usr_123',
      fullName: 'John Doe',
      createdAt: now,
      updatedAt: now,
    );
    await PoiseLocalDatabase.instance.upsertProfile(profile);

    final fetched = await PoiseLocalDatabase.instance.getProfile('usr_123');
    expect(fetched, isNotNull);
    expect(fetched!.fullName, 'John Doe');

    final device = DeviceModel(
      id: 'dev_abc',
      userId: 'usr_123',
      deviceName: 'POISE-XIAO-C3',
      pairedAt: now,
      lastSeenAt: now,
      updatedAt: now,
    );
    await PoiseLocalDatabase.instance.upsertDevice(device);

    final devices = await PoiseLocalDatabase.instance.getDevicesForUser('usr_123');
    expect(devices.length, 1);
    expect(devices.first.deviceName, 'POISE-XIAO-C3');
  });

  test('Sessions and PostureEvents support offline buffering and sync flagging', () async {
    final now = DateTime.now();
    final session = SessionModel(
      id: 'sess_1',
      userId: 'usr_123',
      modeId: 3, // Leisure
      startedAt: now,
      updatedAt: now,
      synced: false,
    );
    await PoiseLocalDatabase.instance.insertSession(session);

    // Verify session is marked unsynced
    var unsyncedSessions = await PoiseLocalDatabase.instance.getUnsyncedSessions();
    expect(unsyncedSessions.length, 1);
    expect(unsyncedSessions.first.synced, false);

    // Insert posture events
    final event1 = PostureEventModel(
      id: 'evt_1',
      sessionId: 'sess_1',
      occurredAt: now,
      tiltAngle: 22.5,
      durationSec: 3.2,
      feedbackTriggered: true,
      synced: false,
    );
    final event2 = PostureEventModel(
      id: 'evt_2',
      sessionId: 'sess_1',
      occurredAt: now.add(const Duration(seconds: 15)),
      tiltAngle: 25.0,
      durationSec: 4.0,
      feedbackTriggered: true,
      synced: false,
    );
    await PoiseLocalDatabase.instance.insertPostureEvent(event1);
    await PoiseLocalDatabase.instance.insertPostureEvent(event2);

    // Query unsynced events
    var unsyncedEvents = await PoiseLocalDatabase.instance.getUnsyncedPostureEvents();
    expect(unsyncedEvents.length, 2);

    // Mark synced
    await PoiseLocalDatabase.instance.markSessionsSynced(['sess_1']);
    await PoiseLocalDatabase.instance.markPostureEventsSynced(['evt_1', 'evt_2']);

    unsyncedSessions = await PoiseLocalDatabase.instance.getUnsyncedSessions();
    expect(unsyncedSessions.isEmpty, true);

    unsyncedEvents = await PoiseLocalDatabase.instance.getUnsyncedPostureEvents();
    expect(unsyncedEvents.isEmpty, true);
  });

  test('Cloud restore hydration correctly marks incoming records as synced', () async {
    final now = DateTime.now();
    final restoredSessions = [
      SessionModel(
        id: 'cloud_sess_1',
        userId: 'usr_123',
        modeId: 1,
        startedAt: now.subtract(const Duration(days: 1)),
        endedAt: now.subtract(const Duration(days: 1, hours: -1)),
        updatedAt: now,
        synced: true,
      ),
    ];
    final restoredEvents = [
      PostureEventModel(
        id: 'cloud_evt_1',
        sessionId: 'cloud_sess_1',
        occurredAt: now.subtract(const Duration(days: 1)),
        tiltAngle: 18.0,
        durationSec: 2.5,
        feedbackTriggered: true,
        synced: true,
      ),
    ];

    await PoiseLocalDatabase.instance.restoreCloudData(
      sessions: restoredSessions,
      events: restoredEvents,
    );

    // Ensure they exist locally but do NOT queue for re-upload
    final unsyncedEvents = await PoiseLocalDatabase.instance.getUnsyncedPostureEvents();
    expect(unsyncedEvents.isEmpty, true);

    final sessionEvents = await PoiseLocalDatabase.instance.getEventsForSession('cloud_sess_1');
    expect(sessionEvents.length, 1);
    expect(sessionEvents.first.tiltAngle, 18.0);
  });
}
