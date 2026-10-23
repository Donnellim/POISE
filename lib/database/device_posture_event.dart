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

  factory DevicePostureEvent.parse(Map<String, dynamic> json,
      {String? rawPayload}) {
    final rawText = rawPayload ?? json.toString();

    void require(bool valid, String field, String expected, dynamic actual) {
      if (!valid) {
        final diagnostic =
            'Invalid final posture event: field "$field" failed validation. Expected $expected, but got: $actual (${actual?.runtimeType}). Raw payload: $rawText';
        debugPrint('[DevicePostureEvent] $diagnostic');
        throw FormatException(diagnostic);
      }
    }

    final isFinal = json['is_final'] == true || json['is_final'] == 'true';
    require(isFinal, 'is_final', 'true (boolean)', json['is_final']);

    final rawSchema = json['schema_version'];
    final schemaVersion = rawSchema is int
        ? rawSchema
        : int.tryParse(rawSchema?.toString() ?? '');
    require(schemaVersion == 1, 'schema_version', '1 (integer)', rawSchema);

    final rawDeviceId = json['device_id'];
    final deviceId = rawDeviceId?.toString() ?? '';
    require(rawDeviceId != null && deviceId.isNotEmpty, 'device_id',
        'non-empty string', rawDeviceId);

    final rawEventId = json['event_id'];
    final isValidEventId = rawEventId != null &&
        rawEventId.toString().isNotEmpty &&
        !RegExp(r'[\r\n\x00]').hasMatch(rawEventId.toString());
    require(isValidEventId, 'event_id',
        'non-empty string or integer without control characters', rawEventId);

    final rawSessionId = json['session_id'];
    final isValidSessionId = rawSessionId != null &&
        rawSessionId.toString().isNotEmpty &&
        !RegExp(r'[\r\n\x00]').hasMatch(rawSessionId.toString());
    require(isValidSessionId, 'session_id', 'non-empty string or integer',
        rawSessionId);

    require(
        json.containsKey('start_time_ms'),
        'start_time_ms',
        'key must exist in payload (nullable UTC milliseconds)',
        json['start_time_ms']);
    final rawStartTime = json['start_time_ms'];
    final int? startTime = rawStartTime == null
        ? null
        : (rawStartTime is int
            ? rawStartTime
            : int.tryParse(rawStartTime.toString()));
    require(
        rawStartTime == null ||
            (startTime != null &&
                startTime >= 0 &&
                startTime <= 8640000000000000),
        'start_time_ms',
        'null or valid 64-bit UTC millisecond timestamp (0 to 8640000000000000)',
        rawStartTime);

    require(
        json.containsKey('end_time_ms'),
        'end_time_ms',
        'key must exist in payload (nullable UTC milliseconds)',
        json['end_time_ms']);
    final rawEndTime = json['end_time_ms'];
    final int? endTime = rawEndTime == null
        ? null
        : (rawEndTime is int
            ? rawEndTime
            : int.tryParse(rawEndTime.toString()));
    require(
        rawEndTime == null ||
            (endTime != null && endTime >= 0 && endTime <= 8640000000000000),
        'end_time_ms',
        'null or valid 64-bit UTC millisecond timestamp (0 to 8640000000000000)',
        rawEndTime);

    if (startTime != null && endTime != null) {
      require(endTime >= startTime, 'end_time_ms', '>= start_time_ms ($startTime)',
          endTime);
    }

    final rawTsStatus = json['timestamp_status'];
    final tsStatus = rawTsStatus?.toString();
    require(tsStatus == 'synced' || tsStatus == 'unknown', 'timestamp_status',
        '"synced" or "unknown"', rawTsStatus);

    final rawModeId = json['mode_id'];
    final modeId = rawModeId is int
        ? rawModeId
        : int.tryParse(rawModeId?.toString() ?? '');
    require(modeId != null && modeId >= 1 && modeId <= 4, 'mode_id',
        'integer between 1 and 4', rawModeId);

    final rawPeak = json['peak_deviation_deg'];
    final num? peak = rawPeak is num
        ? rawPeak
        : num.tryParse(rawPeak?.toString() ?? '');
    require(peak != null && peak.isFinite, 'peak_deviation_deg',
        'finite number (double or int)', rawPeak);

    final rawVib = json['vibration_count'];
    final vib = rawVib is int
        ? rawVib
        : int.tryParse(rawVib?.toString() ?? '');
    require(vib != null && vib >= 0, 'vibration_count', 'non-negative integer',
        rawVib);

    final rawCorrStatus = json['correction_status'];
    final corrStatus = rawCorrStatus?.toString();
    require(corrStatus == 'corrected' || corrStatus == 'interrupted',
        'correction_status', '"corrected" or "interrupted"', rawCorrStatus);

    final rawEndReason = json['end_reason'];
    final endReason = rawEndReason?.toString() ?? '';
    require(rawEndReason != null && endReason.isNotEmpty, 'end_reason',
        'non-empty string (e.g. "posture_corrected")', rawEndReason);

    final map = <String, dynamic>{
      'schema_version': schemaVersion,
      'event_id': rawEventId,
      'device_id': deviceId,
      'session_id': rawSessionId,
      'start_time_ms': startTime,
      'end_time_ms': endTime,
      'timestamp_status': tsStatus,
      'mode_id': modeId,
      'peak_deviation_deg': peak is double ? peak : peak!.toDouble(),
      'vibration_count': vib,
      'correction_status': corrStatus,
      'end_reason': endReason,
    };

    return DevicePostureEvent._(map);
  }

  int? get durationMs =>
      data['start_time_ms'] == null || data['end_time_ms'] == null
          ? null
          : ((data['end_time_ms'] as num).toInt()) -
              ((data['start_time_ms'] as num).toInt());
}
