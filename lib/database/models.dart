import '../activity_mode.dart';

/// Data models corresponding to the P.O.I.S.E. database schema
/// (both Supabase Cloud PostgreSQL and SQLite/SQFlite Local DB).

class ProfileModel {
  const ProfileModel({
    required this.id,
    this.fullName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? fullName;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'full_name': fullName,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ProfileModel.fromMap(Map<String, dynamic> map) => ProfileModel(
        id: map['id'] as String,
        fullName: map['full_name'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

class DeviceModel {
  const DeviceModel({
    required this.id,
    required this.userId,
    required this.deviceName,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String deviceName;
  final DateTime pairedAt;
  final DateTime lastSeenAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'device_name': deviceName,
        'paired_at': pairedAt.toIso8601String(),
        'last_seen_at': lastSeenAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toSupabaseMap() => toMap();

  factory DeviceModel.fromMap(Map<String, dynamic> map) => DeviceModel(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        deviceName: map['device_name'] as String,
        pairedAt: DateTime.parse(map['paired_at'] as String),
        lastSeenAt: DateTime.parse(map['last_seen_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

class ModeModel {
  const ModeModel({
    required this.id,
    required this.modeName,
    required this.angleThresholdDeg,
    required this.forgivenessTimeSec,
  });

  final int id;
  final String modeName;
  final double angleThresholdDeg;
  final double forgivenessTimeSec;

  static const List<ModeModel> defaultModes = [
    ModeModel(
      id: 1,
      modeName: 'Normal',
      angleThresholdDeg: 15,
      forgivenessTimeSec: 2,
    ),
    ModeModel(
      id: 2,
      modeName: 'Focus',
      angleThresholdDeg: 10,
      forgivenessTimeSec: 1,
    ),
    ModeModel(
      id: 3,
      modeName: 'Leisure',
      angleThresholdDeg: 20,
      forgivenessTimeSec: 3,
    ),
    ModeModel(
      id: 4,
      modeName: 'Commuting',
      angleThresholdDeg: 25,
      forgivenessTimeSec: 5,
    ),
  ];

  static int idForActivityMode(ActivityMode mode) => switch (mode) {
        ActivityMode.normal => 1,
        ActivityMode.focus => 2,
        ActivityMode.leisure => 3,
        ActivityMode.commuting => 4,
      };

  static ActivityMode activityModeFromId(int id) => switch (id) {
        1 => ActivityMode.normal,
        2 => ActivityMode.focus,
        3 => ActivityMode.leisure,
        4 => ActivityMode.commuting,
        _ => ActivityMode.normal,
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'mode_name': modeName,
        'angle_threshold_deg': angleThresholdDeg,
        'forgiveness_time_sec': forgivenessTimeSec,
      };

  factory ModeModel.fromMap(Map<String, dynamic> map) => ModeModel(
        id: (map['id'] as num).toInt(),
        modeName: map['mode_name'] as String,
        angleThresholdDeg: (map['angle_threshold_deg'] as num).toDouble(),
        forgivenessTimeSec: (map['forgiveness_time_sec'] as num).toDouble(),
      );
}

class SessionModel {
  const SessionModel({
    required this.id,
    this.deviceId,
    required this.userId,
    required this.modeId,
    required this.startedAt,
    this.endedAt,
    required this.updatedAt,
    this.synced = false,
  });

  final String id;
  final String? deviceId;
  final String userId;
  final int modeId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime updatedAt;
  final bool synced;

  SessionModel copyWith({
    String? userId,
    String? deviceId,
    DateTime? endedAt,
    DateTime? updatedAt,
    bool? synced,
  }) =>
      SessionModel(
        id: id,
        deviceId: deviceId ?? this.deviceId,
        userId: userId ?? this.userId,
        modeId: modeId,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'device_id': deviceId,
        'user_id': userId,
        'mode_id': modeId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toSupabaseMap() => {
        'id': id,
        'device_id': deviceId,
        'user_id': userId,
        'mode_id': modeId,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory SessionModel.fromMap(Map<String, dynamic> map) => SessionModel(
        id: map['id'] as String,
        deviceId: map['device_id'] as String?,
        userId: map['user_id'] as String,
        modeId: (map['mode_id'] as num).toInt(),
        startedAt: DateTime.parse(map['started_at'] as String),
        endedAt: map['ended_at'] != null
            ? DateTime.parse(map['ended_at'] as String)
            : null,
        updatedAt: DateTime.parse(map['updated_at'] as String),
        synced: map['synced'] == 1 || map['synced'] == true,
      );
}

class PostureEventModel {
  const PostureEventModel({
    required this.id,
    required this.sessionId,
    required this.occurredAt,
    required this.tiltAngle,
    required this.durationSec,
    this.feedbackTriggered = true,
    this.synced = false,
  });

  final String id;
  final String sessionId;
  final DateTime occurredAt;
  final double tiltAngle;
  final double durationSec;
  final bool feedbackTriggered;
  final bool synced;

  PostureEventModel copyWith({bool? synced}) => PostureEventModel(
        id: id,
        sessionId: sessionId,
        occurredAt: occurredAt,
        tiltAngle: tiltAngle,
        durationSec: durationSec,
        feedbackTriggered: feedbackTriggered,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'session_id': sessionId,
        'occurred_at': occurredAt.toIso8601String(),
        'tilt_angle': tiltAngle,
        'duration_sec': durationSec,
        'feedback_triggered': feedbackTriggered ? 1 : 0,
        'synced': synced ? 1 : 0,
      };

  Map<String, dynamic> toSupabaseMap() => {
        'id': id,
        'session_id': sessionId,
        'occurred_at': occurredAt.toIso8601String(),
        'tilt_angle': tiltAngle,
        'duration_sec': durationSec,
        'feedback_triggered': feedbackTriggered,
        'synced': true,
      };

  factory PostureEventModel.fromMap(Map<String, dynamic> map) =>
      PostureEventModel(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        occurredAt: DateTime.parse(map['occurred_at'] as String),
        tiltAngle: (map['tilt_angle'] as num).toDouble(),
        durationSec: (map['duration_sec'] as num).toDouble(),
        feedbackTriggered: map['feedback_triggered'] == 1 ||
            map['feedback_triggered'] == true,
        synced: map['synced'] == 1 || map['synced'] == true,
      );
}
