import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_database.dart';
import 'models.dart';

enum SyncStatus { idle, syncing, success, error }

/// Sync coordinator managing two-tier synchronization between local SQFlite and Supabase Cloud.
/// Implements both the push (phone -> Supabase) and restore (Supabase -> phone) flows.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ValueNotifier<SyncStatus> status = ValueNotifier<SyncStatus>(SyncStatus.idle);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier<DateTime?>(null);

  bool get isSyncing => status.value == SyncStatus.syncing;

  SupabaseClient? get _supabase {
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        return Supabase.instance.client;
      }
    } catch (_) {}
    return null;
  }

  /// Pushes un-synced sessions and posture events from local SQFlite to Supabase.
  /// Only runs when an authenticated Supabase session is active.
  Future<bool> syncToCloud() async {
    final client = _supabase;
    if (client == null) {
      // Offline or unauthenticated; local buffering remains untouched.
      return false;
    }

    if (isSyncing) return false;

    status.value = SyncStatus.syncing;
    lastError.value = null;

    try {
      final localDb = PoiseLocalDatabase.instance;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        status.value = SyncStatus.idle;
        return false;
      }

      // 0. Ensure default modes exist in Supabase Cloud
      try {
        for (final mode in ModeModel.defaultModes) {
          await client.from('modes').upsert(mode.toMap());
        }
      } catch (_) {}

      // 1. Sync paired devices first so foreign key constraints on sessions succeed
      final devices = await localDb.getDevicesForUser(userId);
      if (devices.isNotEmpty) {
        for (final device in devices) {
          try {
            await client.from('devices').upsert(device.toSupabaseMap());
          } catch (_) {}
        }
      }

      // 2. Push un-synced sessions (re-mapping any 'local_user' to current userId)
      final unsyncedSessions = await localDb.getUnsyncedSessions();
      if (unsyncedSessions.isNotEmpty) {
        final sessionsToSync = unsyncedSessions.map((s) {
          if (s.userId == 'local_user' || s.userId.isEmpty) {
            return s.copyWith(userId: userId);
          }
          return s;
        }).toList();

        final sessionPayloads =
            sessionsToSync.map((s) => s.toSupabaseMap()).toList();
        await client.from('sessions').upsert(sessionPayloads);
        await localDb
            .markSessionsSynced(unsyncedSessions.map((s) => s.id).toList());
      }

      // 3. Push un-synced posture events in batches of 100
      while (true) {
        final unsyncedEvents =
            await localDb.getUnsyncedPostureEvents(limit: 100);
        if (unsyncedEvents.isEmpty) break;

        final eventPayloads =
            unsyncedEvents.map((e) => e.toSupabaseMap()).toList();
        await client.from('posture_events').upsert(eventPayloads);
        await localDb
            .markPostureEventsSynced(unsyncedEvents.map((e) => e.id).toList());

        if (unsyncedEvents.length < 100) break;
      }

      lastSyncTime.value = DateTime.now();
      status.value = SyncStatus.success;
      return true;
    } catch (e) {
      lastError.value = e.toString();
      status.value = SyncStatus.error;
      return false;
    } finally {
      if (status.value == SyncStatus.syncing) {
        status.value = SyncStatus.idle;
      }
    }
  }

  /// Restores data after device loss / fresh install (Supabase -> Phone).
  /// Pulls all sessions and posture events scoped to the authenticated user and
  /// populates local SQFlite with synced: true.
  Future<bool> restoreFromCloud({bool force = false}) async {
    final client = _supabase;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return false;

    final localDb = PoiseLocalDatabase.instance;
    final isEmpty = await localDb.isDatabaseEmpty();
    if (!isEmpty && !force) {
      // Local database already has records, no initial hydration needed.
      return false;
    }

    status.value = SyncStatus.syncing;
    lastError.value = null;

    try {
      // 1. Fetch user's devices
      final devicesResponse = await client
          .from('devices')
          .select()
          .eq('user_id', userId);
      for (final raw in (devicesResponse as List)) {
        final device = DeviceModel.fromMap(raw as Map<String, dynamic>);
        await localDb.upsertDevice(device);
      }

      // 2. Fetch user's sessions
      final sessionsResponse = await client
          .from('sessions')
          .select()
          .eq('user_id', userId)
          .order('started_at', ascending: true);

      final sessionList = (sessionsResponse as List)
          .map((raw) => SessionModel.fromMap(raw as Map<String, dynamic>))
          .toList();

      if (sessionList.isEmpty) {
        status.value = SyncStatus.success;
        return true;
      }

      final sessionIds = sessionList.map((s) => s.id).toList();

      // 3. Fetch posture events for these sessions (chunked by session IDs if necessary)
      final List<PostureEventModel> eventList = [];
      const chunkSize = 50;
      for (int i = 0; i < sessionIds.length; i += chunkSize) {
        final chunk = sessionIds.sublist(
          i,
          i + chunkSize > sessionIds.length ? sessionIds.length : i + chunkSize,
        );
        final eventsResponse = await client
            .from('posture_events')
            .select()
            .inFilter('session_id', chunk)
            .order('occurred_at', ascending: true);

        for (final raw in (eventsResponse as List)) {
          eventList.add(PostureEventModel.fromMap(raw as Map<String, dynamic>));
        }
      }

      // 4. Save to local database with synced = 1
      await localDb.restoreCloudData(
        sessions: sessionList,
        events: eventList,
      );

      lastSyncTime.value = DateTime.now();
      status.value = SyncStatus.success;
      return true;
    } catch (e) {
      lastError.value = e.toString();
      status.value = SyncStatus.error;
      return false;
    } finally {
      if (status.value == SyncStatus.syncing) {
        status.value = SyncStatus.idle;
      }
    }
  }
}
