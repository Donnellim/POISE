import '../activity_mode.dart';

enum AnalyticsPeriod {
  today('Today'),
  week('7 Days'),
  month('30 Days'),
  year('This Year');

  const AnalyticsPeriod(this.label);
  final String label;
  DateTime start(DateTime now) => switch (this) {
        AnalyticsPeriod.today => DateTime(now.year, now.month, now.day),
        AnalyticsPeriod.week => DateTime(now.year, now.month, now.day - 6),
        AnalyticsPeriod.month => DateTime(now.year, now.month, now.day - 29),
        AnalyticsPeriod.year => DateTime(now.year),
      };
}

/// One measured interval, split by the producer at date/hour or mode changes.
/// Only calibrated, connected sensor intervals belong in this collection.
class PostureRecord {
  const PostureRecord(
      {required this.at,
      required this.seconds,
      required this.pitch,
      required this.mode,
      this.slouchEvents = 0,
      this.warnings = 0,
      this.correctionSeconds,
      this.correctedAt});
  final DateTime at;
  final DateTime? correctedAt;
  final int seconds;
  final double pitch;
  final ActivityMode mode;
  final int slouchEvents;
  final int warnings;
  final double? correctionSeconds;
  bool get slouched => pitch.abs() >= mode.angle;
  bool get valid =>
      seconds > 0 &&
      pitch.isFinite &&
      slouchEvents >= 0 &&
      warnings >= 0 &&
      (correctionSeconds == null ||
          (correctionSeconds!.isFinite && correctionSeconds! >= 0));
}

class AnalyticsSummary {
  AnalyticsSummary(Iterable<PostureRecord> source, this.period, this.now)
      : records = source
            .where((r) =>
                r.valid &&
                !r.at.isBefore(period.start(now)) &&
                !r.at.isAfter(now))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
  final List<PostureRecord> records;
  final AnalyticsPeriod period;
  final DateTime now;
  int get totalSeconds => records.fold(0, (sum, r) => sum + r.seconds);
  int get slouchedSeconds =>
      records.where((r) => r.slouched).fold(0, (sum, r) => sum + r.seconds);
  int get neutralSeconds => totalSeconds - slouchedSeconds;
  int get warnings => records.fold(0, (sum, r) => sum + r.warnings);
  double? correctionFor([ActivityMode? mode]) {
    final values = records
        .where((r) =>
            r.correctionSeconds != null && (mode == null || r.mode == mode))
        .map((r) => r.correctionSeconds!)
        .toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  int get bucketCount => period == AnalyticsPeriod.today ? 12 : 7;
  int bucket(PostureRecord record) => period == AnalyticsPeriod.today
      ? record.at.hour ~/ 2
      : DateTime(record.at.year, record.at.month, record.at.day)
          .difference(period.start(now))
          .inDays;
  String bucketLabel(int index) {
    if (period == AnalyticsPeriod.today) {
      final hour = index * 2;
      return '${hour % 12 == 0 ? 12 : hour % 12}${hour < 12 ? 'a' : 'p'}';
    }
    final day = DateTime(now.year, now.month, now.day - 6 + index);
    return '${day.month}/${day.day}';
  }

  int eventsAt(int index) => records
      .where((r) => bucket(r) == index)
      .fold(0, (sum, r) => sum + r.slouchEvents);
  double? pitchAt(int index) {
    final items = records.where((r) => bucket(r) == index);
    final seconds = items.fold(0, (sum, r) => sum + r.seconds);
    return seconds == 0
        ? null
        : items.fold(0.0, (sum, r) => sum + r.pitch.abs() * r.seconds) /
            seconds;
  }

  String csv({required bool sample}) {
    final rows = <List<Object>>[
      [
        'source',
        'slouched_at',
        'corrected_at',
        'correction_time_seconds',
        'pitch_degrees',
        'mode',
        'angle_threshold_degrees',
        'time_threshold_seconds',
        'zone',
        'slouch_events',
        'fatigue_warnings',
      ],
      for (final r in records)
        [
          sample ? 'sample' : 'measured',
          r.at.toIso8601String(),
          (r.slouched || r.slouchEvents > 0)
              ? (r.correctedAt?.toIso8601String() ??
                  r.at
                      .add(Duration(
                          milliseconds:
                              ((r.correctionSeconds ?? (r.seconds > 0 ? r.seconds.toDouble() : 3.0)) * 1000).round()))
                      .toIso8601String())
              : '',
          (r.slouched || r.slouchEvents > 0)
              ? (r.correctionSeconds != null
                  ? r.correctionSeconds!.toStringAsFixed(1)
                  : '${r.seconds > 0 ? r.seconds : 3}.0')
              : '',
          r.pitch,
          r.mode.label,
          r.mode.angle,
          r.mode.seconds,
          r.slouched ? 'slouched' : 'neutral',
          r.slouchEvents,
          r.warnings,
        ],
    ];
    final body = rows
        .map((row) =>
            row.map((v) => '"${v.toString().replaceAll('"', '""')}"').join(','))
        .join('\r\n');
    return '$body\r\n';
  }
}

String wearDuration(int seconds) {
  final minutes = seconds ~/ 60;
  return minutes >= 60
      ? '${minutes ~/ 60}h ${minutes % 60}m'
      : minutes > 0
          ? '${minutes}m'
          : '${seconds}s';
}

/// Explicit opt-in preview data; never mixed into measured records.
List<PostureRecord> sampleRecords(DateTime now) {
  final ref = DateTime(now.year, now.month, now.day, 23, 59, 59);
  // Realistic hourly telemetry matching the Today Analysis design mockups
  final todayData = <int, ({int slouch, double pitch, int seconds, int warnings})>{
    6: (slouch: 5, pitch: 18.6, seconds: 1200, warnings: 1),
    8: (slouch: 18, pitch: 18.6, seconds: 1800, warnings: 1),
    10: (slouch: 32, pitch: 16.2, seconds: 2400, warnings: 1),
    12: (slouch: 54, pitch: 13.8, seconds: 2700, warnings: 1),
    14: (slouch: 41, pitch: 11.4, seconds: 2400, warnings: 1),
    16: (slouch: 28, pitch: 9.6, seconds: 2100, warnings: 1),
    18: (slouch: 22, pitch: 7.8, seconds: 1800, warnings: 1),
    20: (slouch: 15, pitch: 6.5, seconds: 1500, warnings: 0),
    22: (slouch: 7, pitch: 5.0, seconds: 900, warnings: 0),
  };

  return [
    // Days 6 down to 1 (for 7-day history)
    for (var day = 6; day >= 1; day--)
      for (var hour = 6; hour <= 22; hour += 2)
        PostureRecord(
          at: DateTime(ref.year, ref.month, ref.day - day, hour),
          seconds: 900 + (hour % 3) * 300,
          pitch: (hour % 4 == 0 ? 22.0 : 6.0) + day * 0.5,
          mode: ActivityMode
              .values[(hour ~/ 2 + day) % ActivityMode.values.length],
          slouchEvents: hour % 4 == 0 ? 2 + day : (hour % 3 == 0 ? 1 : 0),
          warnings: hour % 4 == 0 ? 1 : 0,
          correctionSeconds:
              hour % 4 == 0 ? 2.5 + day * 0.3 + hour / 20 : null,
        ),

    // Day 0 (Today - guaranteed sample preview data regardless of time of day)
    for (final entry in todayData.entries)
      PostureRecord(
        at: DateTime(ref.year, ref.month, ref.day, entry.key),
        seconds: entry.value.seconds,
        pitch: entry.value.pitch,
        mode: ActivityMode
            .values[(entry.key ~/ 2) % ActivityMode.values.length],
        slouchEvents: entry.value.slouch,
        warnings: entry.value.warnings,
        correctionSeconds: 3.2,
      ),
  ];
}
