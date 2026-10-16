import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'models.dart';

/// Singleton manager for the local SQFlite database on mobile (Android/iOS) and web.
/// Implements the offline-first buffer and persistent store matching the POISE ERD.
class PoiseLocalDatabase {
  PoiseLocalDatabase._();
  static final PoiseLocalDatabase instance = PoiseLocalDatabase._();

  static const String dbName = 'poise_local.db';
  static const int dbVersion = 1;

  Database? _db;

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
    if (session.deviceId != null) {
      await db.insert(
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
    await db.insert(
      'sessions',
      session.toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> endSession(String sessionId, DateTime endedAt) async {
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
  }

  Future<SessionModel?> getActiveSession(String userId) async {
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
  }

  Future<void> insertPostureEventsBatch(List<PostureEventModel> events) async {
    if (events.isEmpty) return;
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

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('posture_events');
    await db.delete('sessions');
    await db.delete('devices');
    await db.delete('profiles');
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
