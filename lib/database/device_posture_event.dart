/// Final firmware outbox record. IDs are opaque and are never remapped to UUIDs.
class DevicePostureEvent {
  DevicePostureEvent._(this.data);
  final Map<String, dynamic> data;
  String get eventId => data['event_id'] as String;
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
  factory DevicePostureEvent.parse(Map<String, dynamic> json) {
    void require(bool valid) {
      if (!valid) throw const FormatException('Invalid final posture event');
    }

    require(json['is_final'] == true && json['schema_version'] == 1);
    for (final key in ['event_id', 'device_id', 'session_id', 'end_reason']) {
      require(json[key] is String && (json[key] as String).isNotEmpty);
    }
    require(!RegExp(r'[\r\n\x00]').hasMatch(json['event_id'] as String));
    for (final key in ['start_time_ms', 'end_time_ms']) {
      require(json.containsKey(key) &&
          (json[key] == null ||
              (json[key] is int &&
                  json[key] >= 0 &&
                  json[key] <= 8640000000000000)));
    }
    require(['synced', 'unknown'].contains(json['timestamp_status']));
    require(
        json['mode_id'] is int && json['mode_id'] >= 1 && json['mode_id'] <= 4);
    require(json['vibration_count'] is int && json['vibration_count'] >= 0);
    require(json['peak_deviation_deg'] is num &&
        (json['peak_deviation_deg'] as num).isFinite);
    require(['corrected', 'interrupted'].contains(json['correction_status']));
    if (json['start_time_ms'] != null && json['end_time_ms'] != null) {
      require(json['end_time_ms'] >= json['start_time_ms']);
    }
    return DevicePostureEvent._({for (final key in fields) key: json[key]});
  }
  int? get durationMs =>
      data['start_time_ms'] == null || data['end_time_ms'] == null
          ? null
          : (data['end_time_ms'] as int) - (data['start_time_ms'] as int);
}
