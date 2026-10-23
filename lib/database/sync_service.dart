import 'device_posture_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_database.dart';
import 'models.dart';
import 'network_service.dart';

enum SyncStatus { idle, syncing, success, error }

/// Sync coordinator managing two-tier synchronization between local SQFlite and Supabase Cloud.
/// Implements both the push (phone -> Supabase) and restore (Supabase -> phone) flows.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ValueNotifier<SyncStatus> status =
      ValueNotifier<SyncStatus>(SyncStatus.idle);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier<DateTime?>(null);

  bool get isSyncing => status.value == SyncStatus.syncing;
  bool get isOnline => NetworkService.instance.isConnected;
  bool _syncPending = false;

  /// Initializes connectivity listener to auto-sync when internet/mobile data is restored.
  void initialize() {
    NetworkService.instance.initialize(
      onConnectionRestored: () {
        if (_supabase != null && _supabase!.auth.currentUser != null) {
          unawaited(syncToCloud());
        }
      },
    );
  }

  SupabaseClient? get _supabase {
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        return Supabase.instance.client;
      }
    } catch (_) {}
    return null;
  }

  Future<void> approveDeviceHistory(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('poise.deviceHistoryConsent.$userId', true);
    await PoiseLocalDatabase.instance.linkDeviceHistory(userId);
  }

  Future<void> _syncDeviceHistory(SupabaseClient client, String userId) async {
    final db = await PoiseLocalDatabase.instance.database;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('poise.deviceHistoryConsent.$userId') == true) {
      await PoiseLocalDatabase.instance.linkDeviceHistory(userId);
    }
    final rows = await db.query('device_posture_events',
        where: 'owner_id = ? AND synced = 0', whereArgs: [userId]);
    for (final row in rows) {
      if (client.auth.currentUser?.id != userId) {
        throw StateError('Account changed during sync');
      }
      await client.from('device_posture_events').upsert({
        for (final key in DevicePostureEvent.fields) key: row[key],
        'user_id': userId,
      }, onConflict: 'user_id,device_id,event_id', ignoreDuplicates: true);
      // Never mark a conflicting cloud row as synced.
      final remote = await client
          .from('device_posture_events')
          .select()
          .eq('user_id', userId)
          .eq('device_id', row['device_id']!)
          .eq('event_id', row['event_id']!)
          .single();
      if (DevicePostureEvent.fields.any((key) => row[key] != remote[key])) {
        throw StateError('Conflicting cloud posture event');
      }
      await db.update('device_posture_events', {'synced': 1},
          where: 'owner_id = ? AND device_id = ? AND event_id = ?',
          whereArgs: [userId, row['device_id'], row['event_id']]);
    }
    // Paginate so a new phone restores more than Supabase's default row limit.
    for (var offset = 0;; offset += 500) {
      if (client.auth.currentUser?.id != userId) {
        throw StateError('Account changed during restore');
      }
      final remote = await client
          .from('device_posture_events')
          .select()
          .eq('user_id', userId)
          .order('device_id')
          .order('event_id')
          .range(offset, offset + 499);
      for (final row in remote) {
        await PoiseLocalDatabase.instance.commitDeviceEvent(
            DevicePostureEvent.parse({...row, 'is_final': true}),
            ownerId: userId,
            synced: true);
      }
      if (remote.length < 500) break;
    }
  }

  /// Pushes un-synced sessions and posture events from local SQFlite to Supabase.
  /// Only runs when an authenticated Supabase session is active and internet is connected.
  Future<bool> syncToCloud() async {
    final hasInternet = await NetworkService.instance.checkConnectivity();
    if (!hasInternet) {
      lastError.value =
          'No internet connection. Please connect to Wi-Fi or mobile data to sync with the cloud.';
      status.value = SyncStatus.error;
      return false;
    }

    final client = _supabase;
    if (client == null) {
      lastError.value =
          'Cloud sync requires an active account. Please sign in or register to sync your posture data to the cloud.';
      status.value = SyncStatus.error;
      return false;
    }

    if (isSyncing) {
      _syncPending = true;
      return true;
    }

    status.value = SyncStatus.syncing;
    lastError.value = null;

    try {
      final localDb = PoiseLocalDatabase.instance;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        lastError.value =
            'User authentication session is missing. Please sign in again.';
        status.value = SyncStatus.error;
        return false;
      }

      await _syncDeviceHistory(client, userId);

      // 0. Ensure user profile exists in Supabase Cloud
      final currentUser = client.auth.currentUser;
      final meta = currentUser?.userMetadata ?? {};
      final name = meta['full_name'] ??
          meta['name'] ??
          currentUser?.email?.split('@').first ??
          'User';
      final now = DateTime.now().toUtc();
      final createdAt =
          DateTime.tryParse(currentUser?.createdAt ?? '')?.toUtc() ?? now;

      try {
        await client.from('profiles').upsert({
          'id': ensureUuid(userId),
          'full_name': name,
          'created_at': createdAt.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      } catch (e) {
        debugPrint('Sync profile ensure warning: $e');
      }

      // 0.1 Ensure default modes exist in Supabase Cloud
      try {
        for (final mode in ModeModel.defaultModes) {
          await client.from('modes').upsert(mode.toMap());
        }
      } catch (_) {}

      final unsyncedSessions = await localDb.getUnsyncedSessions();

      // 1. Sync paired devices first so foreign key constraints on sessions succeed
      final localDevices = await localDb.getAllDevices();
      final targetDevices = <String, DeviceModel>{};
      for (final d in localDevices) {
        final normalizedName = (d.deviceName.isEmpty ||
                d.deviceName.toUpperCase().contains('POISE-BLE') ||
                d.deviceName.toUpperCase().contains('SIMULATED') ||
                d.deviceName.toUpperCase().contains('P.O.I.S.E.'))
            ? 'POISE Device'
            : d.deviceName;
        targetDevices[d.id] = DeviceModel(
          id: d.id,
          userId: userId,
          deviceName: normalizedName,
          pairedAt: d.pairedAt,
          lastSeenAt: d.lastSeenAt,
          updatedAt: d.updatedAt,
        );
      }

      // Default fallback device for any sessions started without a paired BLE device
      final defaultDeviceId = ensureUuid('poise-device-$userId');
      targetDevices[defaultDeviceId] ??= DeviceModel(
        id: defaultDeviceId,
        userId: userId,
        deviceName: 'POISE Device',
        pairedAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Also ensure devices referenced by unsynced sessions exist
      for (final s in unsyncedSessions) {
        final devId = (s.deviceId != null && s.deviceId!.trim().isNotEmpty)
            ? s.deviceId!
            : defaultDeviceId;
        if (!targetDevices.containsKey(devId)) {
          targetDevices[devId] = DeviceModel(
            id: devId,
            userId: userId,
            deviceName: 'POISE Device',
            pairedAt: s.startedAt,
            lastSeenAt: s.updatedAt,
            updatedAt: s.updatedAt,
          );
        }
      }

      for (final device in targetDevices.values) {
        try {
          await client.from('devices').upsert(device.toSupabaseMap());
        } catch (_) {}
      }

      // Repair local records in case any had null/empty deviceId
      try {
        await localDb.repairNullSessionDevices(defaultDeviceId);
      } catch (_) {}

      // 2. Push un-synced sessions (re-mapping any mismatched user IDs to current userId and guaranteeing non-null deviceId)
      if (unsyncedSessions.isNotEmpty) {
        final sessionsToSync = unsyncedSessions.map((s) {
          var mapped = s;
          if (mapped.userId != userId) {
            mapped = mapped.copyWith(userId: userId);
          }
          if (mapped.deviceId == null || mapped.deviceId!.trim().isEmpty) {
            mapped = mapped.copyWith(deviceId: defaultDeviceId);
          }
          return mapped;
        }).toList();

        final sessionPayloads = sessionsToSync
            .map((s) => s.toSupabaseMap(fallbackDeviceId: defaultDeviceId))
            .toList();
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
        try {
          await client.from('posture_events').upsert(eventPayloads);
        } on PostgrestException catch (e) {
          if (e.code == '42703' &&
              (e.message.contains('synced') ||
                  e.details?.toString().contains('synced') == true)) {
            for (final p in eventPayloads) {
              p.remove('synced');
            }
            await client.from('posture_events').upsert(eventPayloads);
          } else {
            rethrow;
          }
        }
        await localDb
            .markPostureEventsSynced(unsyncedEvents.map((e) => e.id).toList());

        if (unsyncedEvents.length < 100) break;
      }

      lastSyncTime.value = DateTime.now();
      status.value = SyncStatus.success;
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23503' &&
          (e.message.contains('modes') ||
              e.details?.toString().contains('modes') == true)) {
        lastError.value =
            'The "modes" table is empty in Supabase. Please run the SQL seed in your Supabase SQL editor.';
      } else if (e.code == '42P01') {
        lastError.value =
            'A required database table is missing in Supabase. Please execute supabase_schema.sql in your Supabase project.';
      } else if (e.code == '42501') {
        lastError.value =
            'Supabase Row Level Security policy blocked write. Please verify RLS policies in Supabase.';
      } else {
        lastError.value = 'Supabase sync error (${e.code}): ${e.message}';
      }
      status.value = SyncStatus.error;
      return false;
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('Failed host lookup') ||
          errStr.contains('ClientException') ||
          errStr.contains('Network is unreachable') ||
          errStr.contains('Connection refused') ||
          errStr.contains('HandshakeException')) {
        lastError.value =
            'Internet disconnected. Posture data is safely saved locally and will auto-sync once reconnected.';
      } else {
        lastError.value = errStr;
      }
      status.value = SyncStatus.error;
      return false;
    } finally {
      if (status.value == SyncStatus.syncing) {
        status.value = SyncStatus.idle;
      }
      if (_syncPending) {
        _syncPending = false;
        unawaited(syncToCloud());
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

    if (!NetworkService.instance.isConnected) return false;

    final localDb = PoiseLocalDatabase.instance;
    try {
      await _syncDeviceHistory(client, userId);
    } catch (error) {
      lastError.value = error.toString();
      status.value = SyncStatus.error;
      return false;
    }
    final isEmpty = await localDb.isDatabaseEmpty();
    if (!isEmpty && !force) {
      // Local database already has records, no initial hydration needed.
      return false;
    }

    status.value = SyncStatus.syncing;
    lastError.value = null;

    try {
      // 1. Fetch user's devices
      final devicesResponse =
          await client.from('devices').select().eq('user_id', userId);
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

  /// Deletes all sessions, posture events, and devices from Supabase Cloud for the authenticated user.
  Future<bool> deleteAllCloudData() async {
    final client = _supabase;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return false;

    try {
      await client.from('device_posture_events').delete().eq('user_id', userId);
      // 1. Try calling the PostgreSQL RPC function delete_user_posture_data()
      try {
        await client.rpc('delete_user_posture_data');
        return true;
      } catch (_) {
        // Fallback: Delete rows directly via tables
      }

      // Fetch user's session IDs to delete associated posture events
      final sessionsResponse =
          await client.from('sessions').select('id').eq('user_id', userId);
      final sessionIds =
          (sessionsResponse as List).map((s) => s['id'] as String).toList();

      if (sessionIds.isNotEmpty) {
        const chunkSize = 50;
        for (int i = 0; i < sessionIds.length; i += chunkSize) {
          final chunk = sessionIds.sublist(
            i,
            i + chunkSize > sessionIds.length
                ? sessionIds.length
                : i + chunkSize,
          );
          await client
              .from('posture_events')
              .delete()
              .inFilter('session_id', chunk);
        }
      }

      // Delete user's sessions
      await client.from('sessions').delete().eq('user_id', userId);

      // Delete user's devices
      await client.from('devices').delete().eq('user_id', userId);

      return true;
    } catch (e) {
      debugPrint('[SyncService] deleteAllCloudData error: $e');
      lastError.value = e.toString();
      return false;
    }
  }

  /// Deletes the user's account and all associated cloud data from Supabase.
  Future<bool> deleteUserAccount() async {
    final client = _supabase;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return false;

    try {
      // 1. Delete all user posture telemetry and devices first
      await deleteAllCloudData();

      // 2. Call the PostgreSQL RPC function delete_user_account()
      try {
        await client.rpc('delete_user_account');
      } on PostgrestException catch (e) {
        debugPrint('[SyncService] delete_user_account RPC error: ${e.message}');
        if (e.code == 'PGRST202' ||
            e.message.contains('not find the function')) {
          throw Exception(
            'The delete_user_account() SQL function is missing in your Supabase project. '
            'Please run the delete_user_account function in your Supabase SQL Editor.',
          );
        }
        rethrow;
      }

      // 3. Delete profile directly as a secondary safeguard
      try {
        await client.from('profiles').delete().eq('id', userId);
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('[SyncService] deleteUserAccount error: $e');
      lastError.value = e.toString();
      throw Exception(
          'Failed to delete user account: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }
}
