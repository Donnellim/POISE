import 'package:flutter/foundation.dart';

/// Final firmware outbox record. IDs are opaque and are never remapped to UUIDs.
class DevicePostureEvent {
  DevicePostureEvent._(this.data);
  final Map<String, dynamic> data;

  String get eventId => data['event_id']?.toString() ?? '';
  String get sessionId => data['session_id']?.toString() ?? '';
  String get deviceId => data['device_id']?.toString() ?? '';

  static const fields = [
    'schema_version',
    'event_id',
    'device_id',
    'session_id',
    'start_time_ms',
    'end_time_ms',
    'timestamp_status',
    'mode_id',
    'peak_deviation_deg',
    'vibration_count',
    'correction_status',
    'end_reason'
  ];

  static bool _isValidId(dynamic value) {
    if (value == null) return false;
    if (value is int) return true;
    if (value is String) {
      return value.isNotEmpty && !RegExp(r'[\r\n\x00]').hasMatch(value);
    }
    return false;
  }

  static bool _isValidTimestamp(dynamic value) {
    if (value == null) return true;
    if (value is int) {
      return value >= 0 && value <= 8640000000000000;
    }
    if (value is num) {
      final v = value.toInt();
      return v >= 0 && v <= 8640000000000000 && value == v;
    }
    return false;
  }

  factory DevicePostureEvent.parse(Map<String, dynamic> json) {
    void require(bool valid, String reason) {
      if (!valid) {
        debugPrint(
            '[DevicePostureEvent] Validation failed: $reason (payload: $json)');
        throw FormatException('Invalid final posture event: $reason');
      }
    }

    require(json['is_final'] == true, 'is_final must be true');
    require(json['schema_version'] == 1, 'schema_version must be 1');
    require(
        json['device_id'] is String && (json['device_id'] as String).isNotEmpty,
        'device_id must be a non-empty string');
    require(_isValidId(json['event_id']),
        'event_id must be a valid non-empty string or integer');
    require(!RegExp(r'[\r\n\x00]').hasMatch(json['event_id'].toString()),
        'event_id contains invalid control characters');
    require(_isValidId(json['session_id']),
        'session_id must be a valid non-empty string or integer');
    require(
        json['end_reason'] is String && (json['end_reason'] as String).isNotEmpty,
        'end_reason must be a non-empty string');
    require(
        json.containsKey('start_time_ms') &&
            _isValidTimestamp(json['start_time_ms']),
        'start_time_ms must be null or valid 64-bit millisecond timestamp');
    require(
        json.containsKey('end_time_ms') &&
            _isValidTimestamp(json['end_time_ms']),
        'end_time_ms must be null or valid 64-bit millisecond timestamp');
    require(['synced', 'unknown'].contains(json['timestamp_status']),
        'timestamp_status must be "synced" or "unknown"');
    require(
        json['mode_id'] is int &&
            (json['mode_id'] as int) >= 1 &&
            (json['mode_id'] as int) <= 4,
        'mode_id must be an integer between 1 and 4');
    require(
        json['vibration_count'] is int &&
            (json['vibration_count'] as int) >= 0,
        'vibration_count must be a non-negative integer');
    require(
        json['peak_deviation_deg'] is num &&
            (json['peak_deviation_deg'] as num).isFinite,
        'peak_deviation_deg must be a finite number');
    require(['corrected', 'interrupted'].contains(json['correction_status']),
        'correction_status must be "corrected" or "interrupted"');
    if (json['start_time_ms'] != null && json['end_time_ms'] != null) {
      require(
          (json['end_time_ms'] as num) >= (json['start_time_ms'] as num),
          'end_time_ms must be >= start_time_ms');
    }

    return DevicePostureEvent._({for (final key in fields) key: json[key]});
  }

  int? get durationMs =>
      data['start_time_ms'] == null || data['end_time_ms'] == null
          ? null
          : ((data['end_time_ms'] as num).toInt()) -
              ((data['start_time_ms'] as num).toInt());
}
