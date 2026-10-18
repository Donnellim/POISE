import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'models.dart';
import '../analytics/analytics_data.dart';
import '../activity_mode.dart';

/// Singleton manager for the local SQFlite database on mobile (Android/iOS) and web.
/// Implements the offline-first buffer and persistent store matching the POISE ERD.
class PoiseLocalDatabase {
  PoiseLocalDatabase._();
  static final PoiseLocalDatabase instance = PoiseLocalDatabase._();

  static const String dbName = 'poise_local.db';
  static const int dbVersion = 1;

  Database? _db;

  /// Change notification bus for real-time mirroring to UI components (e.g. AnalyticsTab).
  final ValueNotifier<int> onDatabaseChanged = ValueNotifier<int>(0);

  void notifyDatabaseChanged() {
    onDatabaseChanged.value++;
  }

  /// Returns the initialized database, initializing it if necessary.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await init();
    return _db!;
  }

  /// Sets an in-memory or mock database for testing purposes.
  @visibleForTesting
  void setDatabaseForTesting(Database db) {
    _db = db;
  }

  /// Initialize database connection and ensure tables and default modes exist.
  Future<Database> init({String? customPath}) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String path;
    if (kIsWeb) {
      path = customPath ?? dbName;
    } else if (Platform.environment.containsKey('FLUTTER_TEST')) {
      path = customPath ?? inMemoryDatabasePath;
    } else {
      path = customPath ?? p.join(await getDatabasesPath(), dbName);
    }

    if (kIsWeb) {
      try {
        databaseFactory = databaseFactoryFfiWeb;
        final db = await openDatabase(
          path,
          version: dbVersion,
          onCreate: _onCreate,
          onOpen: _onOpen,
        );
        _db = db;
        return db;
      } catch (_) {
        try {
          databaseFactory = databaseFactoryFfiWebNoWebWorker;
          final db = await openDatabase(
            path,
            version: dbVersion,
            onCreate: _onCreate,
            onOpen: _onOpen,
          );
          _db = db;
          return db;
        } catch (_) {
          final db = await openDatabase(
            inMemoryDatabasePath,
            version: dbVersion,
            onCreate: _onCreate,
            onOpen: _onOpen,
          );
          _db = db;
          return db;
        }
      }
    }

    final db = await openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
    _db = db;
    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // 1. Profiles Table
    batch.execute('''
      CREATE TABLE profiles (
        id TEXT PRIMARY KEY,
        full_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 2. Devices Table
    batch.execute('''
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

    // 3. Modes Table
    batch.execute('''
      CREATE TABLE modes (
        id INTEGER PRIMARY KEY,
        mode_name TEXT NOT NULL,
        angle_threshold_deg REAL NOT NULL,
        forgiveness_time_sec REAL NOT NULL
      )
    ''');

    // 4. Sessions Table
    batch.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        device_id TEXT,
        user_id TEXT NOT NULL,
        mode_id INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        updated_at TEXT NOT NULL,
        baseline_angle REAL NOT NULL DEFAULT 0.0,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL,
        FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
        FOREIGN KEY (mode_id) REFERENCES modes(id)
      )
    ''');

    // 5. Posture Events Table
    batch.execute('''
      CREATE TABLE posture_events (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        corrected_at TEXT,
        correction_time_sec REAL,
        tilt_angle REAL NOT NULL,
        duration_sec REAL NOT NULL,
        feedback_triggered INTEGER NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    // Indices for local performance
    batch.execute('CREATE INDEX idx_sessions_user ON sessions(user_id)');
    batch.execute('CREATE INDEX idx_sessions_synced ON sessions(synced)');
    batch.execute('CREATE INDEX idx_events_session ON posture_events(session_id)');
    batch.execute('CREATE INDEX idx_events_synced ON posture_events(synced)');
    batch.execute('CREATE INDEX idx_events_occurred ON posture_events(occurred_at)');

    // Seed default modes
    for (final mode in ModeModel.defaultModes) {
      batch.insert(
        'modes',
        mode.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> _onOpen(Database db) async {
    // Ensure foreign keys are enabled in SQLite
    await db.execute('PRAGMA foreign_keys = ON');

    // Safe auto-migration for existing local tables
    try {
      await db.execute(
          'ALTER TABLE sessions ADD COLUMN baseline_angle REAL NOT NULL DEFAULT 0.0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE posture_events ADD COLUMN corrected_at TEXT');
    } catch (_) {}
    try {
      await db.execute(
          'ALTER TABLE posture_events ADD COLUMN correction_time_sec REAL');
    } catch (_) {}

    // Verify modes are seeded
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM modes'),
    );
    if (count == null || count == 0) {
      final batch = db.batch();
      for (final mode in ModeModel.defaultModes) {
        batch.insert(
          'modes',
          mode.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  // ===========================================================================
  // Profile Methods
  // ===========================================================================

  Future<void> upsertProfile(ProfileModel profile) async {
    final db = await database;
    await db.insert(
      'profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ProfileModel?> getProfile(String id) async {
    final db = await database;
    final res = await db.query('profiles', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return ProfileModel.fromMap(res.first);
  }

  // ===========================================================================
  // Device Methods
  // ===========================================================================

  Future<void> upsertDevice(DeviceModel device) async {
    final db = await database;
    await db.insert(
      'profiles',
      {
        'id': device.userId,
        'full_name': 'User',
        'created_at': device.pairedAt.toIso8601String(),
        'updated_at': device.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'devices',
      device.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DeviceModel?> getDevice(String id) async {
    final db = await database;
    final res = await db.query('devices', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return DeviceModel.fromMap(res.first);
  }

  Future<List<DeviceModel>> getDevicesForUser(String userId) async {
    final db = await database;
    final res = await db.query(
      'devices',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'last_seen_at DESC',
    );
    return res.map(DeviceModel.fromMap).toList();
  }

  Future<List<DeviceModel>> getAllDevices() async {
    final db = await database;
    final res = await db.query('devices', orderBy: 'last_seen_at DESC');
    return res.map(DeviceModel.fromMap).toList();
  }

  // ===========================================================================
  // Mode Methods
  // ===========================================================================

  Future<List<ModeModel>> getAllModes() async {
    final db = await database;
    final res = await db.query('modes', orderBy: 'id ASC');
    return res.map(ModeModel.fromMap).toList();
  }

  Future<ModeModel?> getModeById(int id) async {
    final db = await database;
    final res = await db.query('modes', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return ModeModel.fromMap(res.first);
  }

  // ===========================================================================
  // Session Methods
  // ===========================================================================

  Future<void> insertSession(SessionModel session) async {
    if (_isHeadlessTest) {
      notifyDatabaseChanged();
      return;
    }
    final db = await database;
    await db.insert(
      'profiles',
      {
        'id': session.userId,
        'full_name': 'User',
        'created_at': session.startedAt.toIso8601String(),
        'updated_at': session.startedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final effectiveDeviceId =
        (session.deviceId != null && session.deviceId!.trim().isNotEmpty)
            ? session.deviceId!
            : 'POISE-DEVICE';
    await db.insert(
      'devices',
      {
        'id': effectiveDeviceId,
        'user_id': session.userId,
        'device_name': 'POISE Device',
        'paired_at': session.startedAt.toIso8601String(),
        'last_seen_at': session.startedAt.toIso8601String(),
        'updated_at': session.startedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final sessionToInsert =
        (session.deviceId == null || session.deviceId!.trim().isEmpty)
            ? session.copyWith(deviceId: effectiveDeviceId)
            : session;
    await db.insert(
      'sessions',
      sessionToInsert.toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyDatabaseChanged();
  }

  Future<void> repairNullSessionDevices(String defaultDeviceId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE sessions SET device_id = ? WHERE device_id IS NULL OR device_id = ""',
      [defaultDeviceId],
    );
  }

  Future<void> endSession(String sessionId, DateTime endedAt) async {
    if (_isHeadlessTest) {
      notifyDatabaseChanged();
      return;
    }
    final db = await database;
    await db.update(
      'sessions',
      {
        'ended_at': endedAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'synced': 0, // Needs re-sync to cloud with updated end time
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    notifyDatabaseChanged();
  }

  Future<void> updateSessionProgress(String sessionId, DateTime updatedAt) async {
    if (_isHeadlessTest) {
      notifyDatabaseChanged();
      return;
    }
    final db = await database;
    await db.update(
      'sessions',
      {
        'updated_at': updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    notifyDatabaseChanged();
  }

  Future<void> updateSessionMode(String sessionId, int modeId) async {
    if (_isHeadlessTest) {
      notifyDatabaseChanged();
      return;
    }
    final db = await database;
    await db.update(
      'sessions',
      {
        'mode_id': modeId,
        'updated_at': DateTime.now().toIso8601String(),
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    notifyDatabaseChanged();
  }

  Future<SessionModel?> getActiveSession(String userId) async {
    if (_isHeadlessTest) return null;
    final db = await database;
    final res = await db.query(
      'sessions',
      where: 'user_id = ? AND ended_at IS NULL',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (res.isEmpty) return null;
    return SessionModel.fromMap(res.first);
  }

  Future<SessionModel?> getLatestActiveSession() async {
    if (_isHeadlessTest) return null;
    final db = await database;
    final res = await db.query(
      'sessions',
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (res.isEmpty) return null;
    return SessionModel.fromMap(res.first);
  }

  Future<int> getTodayTotalWearSeconds() async {
    final records = await getAllPostureRecords();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayRecords = records
        .where((r) => !r.at.isBefore(todayStart) && !r.at.isAfter(now));
    return todayRecords.fold<int>(0, (int sum, r) => sum + r.seconds);
  }

  Future<List<SessionModel>> getSessionsForUser(String userId) async {
    final db = await database;
    final res = await db.query(
      'sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
    );
    return res.map(SessionModel.fromMap).toList();
  }

  Future<List<SessionModel>> getUnsyncedSessions() async {
    final db = await database;
    final res = await db.query(
      'sessions',
      where: 'synced = 0',
      orderBy: 'started_at ASC',
    );
    return res.map(SessionModel.fromMap).toList();
  }

  Future<void> markSessionsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE sessions SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  // ===========================================================================
  // Posture Event Methods (Offline Edge Buffering & Sync)
  // ===========================================================================

  Future<void> insertPostureEvent(PostureEventModel event) async {
    if (_isHeadlessTest) {
      notifyDatabaseChanged();
      return;
    }
    final db = await database;
    await db.insert(
      'profiles',
      {
        'id': 'local_user',
        'full_name': 'User',
        'created_at': event.occurredAt.toIso8601String(),
        'updated_at': event.occurredAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'sessions',
      {
        'id': event.sessionId,
        'user_id': 'local_user',
        'mode_id': 1,
        'started_at': event.occurredAt.toIso8601String(),
        'updated_at': event.occurredAt.toIso8601String(),
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert(
      'posture_events',
      event.toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyDatabaseChanged();
  }

  Future<void> insertPostureEventsBatch(List<PostureEventModel> events) async {
    if (events.isEmpty) return;
    if (mockRecordsForTesting != null) {
      notifyDatabaseChanged();
      return;
    }
    final db = await database;
    final batch = db.batch();
    for (final event in events) {
      batch.insert(
        'profiles',
        {
          'id': 'local_user',
          'full_name': 'User',
          'created_at': event.occurredAt.toIso8601String(),
          'updated_at': event.occurredAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'sessions',
        {
          'id': event.sessionId,
          'user_id': 'local_user',
          'mode_id': 1,
          'started_at': event.occurredAt.toIso8601String(),
          'updated_at': event.occurredAt.toIso8601String(),
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert(
        'posture_events',
        event.toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    notifyDatabaseChanged();
  }

  Future<List<PostureEventModel>> getUnsyncedPostureEvents({int limit = 100}) async {
    final db = await database;
    final res = await db.query(
      'posture_events',
      where: 'synced = 0',
      orderBy: 'occurred_at ASC',
      limit: limit,
    );
    return res.map(PostureEventModel.fromMap).toList();
  }

  Future<void> updatePostureEventCorrection({
    required String id,
    required DateTime correctedAt,
    required double correctionTimeSec,
  }) async {
    if (mockRecordsForTesting != null) {
      notifyDatabaseChanged();
      return;
    }
    final db = await database;
    await db.update(
      'posture_events',
      {
        'corrected_at': correctedAt.toIso8601String(),
        'correction_time_sec': correctionTimeSec,
        'duration_sec': correctionTimeSec,
        'synced': 0, // Needs re-sync to Supabase cloud
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyDatabaseChanged();
  }

  Future<void> markPostureEventsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE posture_events SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<List<PostureEventModel>> getEventsForSession(String sessionId) async {
    final db = await database;
    final res = await db.query(
      'posture_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'occurred_at ASC',
    );
    return res.map(PostureEventModel.fromMap).toList();
  }

  Future<List<PostureEventModel>> getEventsForPeriod(DateTime start, DateTime end) async {
    final db = await database;
    final res = await db.query(
      'posture_events',
      where: 'occurred_at >= ? AND occurred_at <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'occurred_at ASC',
    );
    return res.map(PostureEventModel.fromMap).toList();
  }

  // ===========================================================================
  // Restore Flow (Hydration from Cloud upon Device Switch / Reset)
  // ===========================================================================

  /// Hydrate local database from cloud data (marked synced: 1)
  Future<void> restoreCloudData({
    required List<SessionModel> sessions,
    required List<PostureEventModel> events,
  }) async {
    final db = await database;
    final batch = db.batch();

    for (final session in sessions) {
      batch.insert(
        'profiles',
        {
          'id': session.userId,
          'full_name': 'User',
          'created_at': session.startedAt.toIso8601String(),
          'updated_at': session.startedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (session.deviceId != null) {
        batch.insert(
          'devices',
          {
            'id': session.deviceId!,
            'user_id': session.userId,
            'device_name': 'POISE Device',
            'paired_at': session.startedAt.toIso8601String(),
            'last_seen_at': session.startedAt.toIso8601String(),
            'updated_at': session.startedAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    for (final session in sessions) {
      batch.insert(
        'sessions',
        session.copyWith(synced: true).toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    for (final event in events) {
      batch.insert(
        'posture_events',
        event.copyWith(synced: true).toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    notifyDatabaseChanged();
  }

  /// Optional mock records list used to bypass raw SQLite I/O during headless widget testing.
  List<PostureRecord>? mockRecordsForTesting;

  bool get _isHeadlessTest =>
      mockRecordsForTesting != null ||
      (Platform.environment.containsKey('FLUTTER_TEST') && _db == null);

  /// Helper to generate neutral posture intervals split at hourly boundaries
  List<PostureRecord> _createNeutralRecords({
    required DateTime start,
    required DateTime end,
    required double baselineAngle,
    required ActivityMode mode,
  }) {
    final records = <PostureRecord>[];
    if (!end.isAfter(start)) return records;

    var currentStart = start;
    while (end.isAfter(currentStart)) {
      final nextHour = DateTime(
        currentStart.year,
        currentStart.month,
        currentStart.day,
        currentStart.hour + 1,
      );
      final chunkEnd = end.isBefore(nextHour) ? end : nextHour;
      final sec = chunkEnd.difference(currentStart).inSeconds;
      if (sec > 0) {
        records.add(PostureRecord(
          at: currentStart,
          seconds: sec,
          pitch: baselineAngle,
          mode: mode,
          slouchEvents: 0,
          warnings: 0,
          correctionSeconds: null,
        ));
      }
      currentStart = chunkEnd;
    }
    return records;
  }

  /// Transforms all stored sessions and posture events into structured PostureRecord objects
  /// for real-time mirroring between the POISE hardware, dashboard monitoring, and Analytics tab.
  Future<List<PostureRecord>> getAllPostureRecords() async {
    if (_isHeadlessTest) {
      return List<PostureRecord>.from(mockRecordsForTesting ?? const []);
    }
    final db = await database;

    final sessionRows = await db.query('sessions', orderBy: 'started_at ASC');
    final eventRows = await db.query('posture_events', orderBy: 'occurred_at ASC');

    final eventsBySession = <String, List<Map<String, Object?>>>{};
    final orphanedEvents = <Map<String, Object?>>[];
    final sessionIds = sessionRows.map((s) => s['id'] as String).toSet();

    for (final e in eventRows) {
      final sId = e['session_id'] as String?;
      if (sId != null && sessionIds.contains(sId)) {
        eventsBySession.putIfAbsent(sId, () => []).add(e);
      } else {
        orphanedEvents.add(e);
      }
    }

    final allRecords = <PostureRecord>[];
    final now = DateTime.now();

    for (final sRow in sessionRows) {
      final sessionStart =
          DateTime.tryParse(sRow['started_at'] as String? ?? '') ?? now;
      final endedAtRaw = sRow['ended_at'] as String?;
      final updatedAtRaw = sRow['updated_at'] as String?;

      DateTime sessionEnd;
      if (endedAtRaw != null) {
        sessionEnd = DateTime.tryParse(endedAtRaw) ?? sessionStart;
      } else {
        // Active session: sync dynamically to current time, unless stale/abandoned > 30 minutes
        final updated =
            updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw) : null;
        if (updated != null && now.difference(updated).inMinutes > 30) {
          sessionEnd = updated;
        } else {
          sessionEnd = now;
        }
      }

      if (sessionEnd.isBefore(sessionStart)) {
        sessionEnd = sessionStart;
      }

      final modeId = sRow['mode_id'] as int? ?? 1;
      final mode = ModeModel.activityModeFromId(modeId);
      final baselineAngle =
          (sRow['baseline_angle'] as num?)?.toDouble() ?? 0.0;
      final sEvents = eventsBySession[sRow['id'] as String] ?? [];

      // Filter and sort slouch events within this session
      final slouchEvents = <Map<String, Object?>>[];
      for (final e in sEvents) {
        final pitch = (e['tilt_angle'] as num?)?.toDouble() ?? 0.0;
        final feedback = (e['feedback_triggered'] as int? ?? 0) == 1;
        final isSlouch = feedback || pitch.abs() >= mode.angle;
        if (isSlouch) {
          slouchEvents.add(e);
        }
      }

      var cursor = sessionStart;

      for (final e in slouchEvents) {
        final occurredAt =
            DateTime.tryParse(e['occurred_at'] as String? ?? '') ?? cursor;
        final correctedAt = e['corrected_at'] != null
            ? DateTime.tryParse(e['corrected_at'] as String)
            : null;
        final corrSec = (e['correction_time_sec'] as num?)?.toDouble() ??
            (e['duration_sec'] as num?)?.toDouble();
        final pitch = (e['tilt_angle'] as num?)?.toDouble() ?? mode.angle.toDouble();
        final feedback = (e['feedback_triggered'] as int? ?? 0) == 1;
        final slouchDur =
            (corrSec?.round() ?? 1) > 0 ? (corrSec?.round() ?? 1) : 1;

        // Emit neutral interval before this slouch event if any elapsed
        if (occurredAt.isAfter(cursor)) {
          allRecords.addAll(_createNeutralRecords(
            start: cursor,
            end: occurredAt,
            baselineAngle: baselineAngle,
            mode: mode,
          ));
        }

        // Emit the slouch record
        allRecords.add(PostureRecord(
          at: occurredAt,
          correctedAt: correctedAt,
          seconds: slouchDur,
          pitch: pitch,
          mode: mode,
          slouchEvents: 1,
          warnings: feedback ? 1 : 0,
          correctionSeconds: corrSec,
        ));

        // Advance cursor past this slouch
        final eventEnd =
            correctedAt ?? occurredAt.add(Duration(seconds: slouchDur));
        cursor = eventEnd.isAfter(cursor) ? eventEnd : cursor;
      }

      // Emit neutral interval from last event to session end
      if (sessionEnd.isAfter(cursor)) {
        allRecords.addAll(_createNeutralRecords(
          start: cursor,
          end: sessionEnd,
          baselineAngle: baselineAngle,
          mode: mode,
        ));
      } else if (slouchEvents.isEmpty && sessionStart == sessionEnd) {
        // If session just started and has 0 seconds, emit at least 1 second neutral baseline if session is active
        if (endedAtRaw == null) {
          allRecords.add(PostureRecord(
            at: sessionStart,
            seconds: 1,
            pitch: baselineAngle,
            mode: mode,
            slouchEvents: 0,
            warnings: 0,
            correctionSeconds: null,
          ));
        }
      }
    }

    // Process any orphaned events not tied to a registered session
    for (final row in orphanedEvents) {
      final at = DateTime.tryParse(row['occurred_at'] as String? ?? '') ?? now;
      final correctedAt = row['corrected_at'] != null
          ? DateTime.tryParse(row['corrected_at'] as String)
          : null;
      final correctionTimeSec =
          (row['correction_time_sec'] as num?)?.toDouble() ??
              (row['duration_sec'] as num?)?.toDouble();
      final pitch = (row['tilt_angle'] as num?)?.toDouble() ?? 0.0;
      final seconds = (correctionTimeSec?.round() ?? 1) > 0
          ? (correctionTimeSec?.round() ?? 1)
          : 1;
      final feedback = (row['feedback_triggered'] as int? ?? 0) == 1;
      final isSlouched = pitch.abs() >= ActivityMode.normal.angle;
      final slouchEvents = (feedback || isSlouched) ? 1 : 0;
      allRecords.add(PostureRecord(
        at: at,
        correctedAt: correctedAt,
        seconds: seconds,
        pitch: pitch,
        mode: ActivityMode.normal,
        slouchEvents: slouchEvents,
        warnings: slouchEvents,
        correctionSeconds: correctionTimeSec,
      ));
    }

    allRecords.sort((a, b) => a.at.compareTo(b.at));
    return allRecords;
  }

  Future<bool> isDatabaseEmpty() async {
    final db = await database;
    final sessionCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sessions'),
    ) ?? 0;
    final eventCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM posture_events'),
    ) ?? 0;
    return sessionCount == 0 && eventCount == 0;
  }

  Future<void> clearPostureData() async {
    final db = await database;
    await db.delete('posture_events');
    await db.delete('sessions');
    await db.delete('devices');
    notifyDatabaseChanged();
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('posture_events');
    await db.delete('sessions');
    await db.delete('devices');
    await db.delete('profiles');
    notifyDatabaseChanged();
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
