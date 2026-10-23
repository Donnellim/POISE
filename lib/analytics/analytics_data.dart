import 'dart:math' as math;
import '../activity_mode.dart';
import '../database/models.dart';

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
  const PostureRecord({
    required this.at,
    required this.seconds,
    required double pitch,
    required this.mode,
    this.slouchEvents = 0,
    this.warnings = 0,
    this.correctionSeconds,
    this.correctedAt,
    this.eventId,
    this.sessionId,
    this.userId,
    double? baselineAngle,
    this.feedbackTriggered,
    this.endReason,
    this.correctionStatus,
  })  : pitch = (pitch > 180.0 || pitch < -180.0)
            ? ((pitch / 100.0) > 60.0
                ? 60.0
                : ((pitch / 100.0) < -60.0 ? -60.0 : (pitch / 100.0)))
            : (pitch > 60.0 ? 60.0 : (pitch < -60.0 ? -60.0 : pitch)),
        baselineAngle = baselineAngle == null
            ? null
            : ((baselineAngle > 180.0 || baselineAngle < -180.0)
                ? ((baselineAngle / 100.0) > 60.0
                    ? 60.0
                    : ((baselineAngle / 100.0) < -60.0
                        ? -60.0
                        : (baselineAngle / 100.0)))
                : (baselineAngle > 60.0
                    ? 60.0
                    : (baselineAngle < -60.0 ? -60.0 : baselineAngle)));

  final DateTime at;
  final DateTime? correctedAt;
  final int seconds;
  final double pitch;
  final ActivityMode mode;
  final int slouchEvents;
  final int warnings;
  final double? correctionSeconds;
  final String? eventId;
  final String? sessionId;
  final String? userId;
  final double? baselineAngle;
  final bool? feedbackTriggered;
  final String? endReason;
  final String? correctionStatus;

  static double sanitizeAngle(double raw) {
    if (!raw.isFinite) return 0.0;
    var a = raw;
    // Normalize centidegrees (e.g. 3141.0 -> 31.41°, 565.7 -> 5.66°)
    if (a.abs() > 180.0) {
      a /= 100.0;
    }
    // Clamp to physiological cervical/sagittal posture range [-60.0, 60.0]
    return a.clamp(-60.0, 60.0);
  }

  bool get slouched => pitch.abs() >= mode.angle;
  bool get valid =>
      seconds >= 0 &&
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
                !r.at.isAfter(now.add(const Duration(minutes: 5))))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
  final List<PostureRecord> records;
  final AnalyticsPeriod period;
  final DateTime now;
  int get totalSeconds => records.fold(0, (sum, r) => sum + r.seconds);
  int get slouchedSeconds =>
      records.where((r) => r.slouched).fold(0, (sum, r) => sum + r.seconds);
  int get neutralSeconds => totalSeconds - slouchedSeconds;
  int get totalSlouchEvents => records.fold(0, (sum, r) => sum + r.slouchEvents);
  int get warnings => totalSlouchEvents;
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

  double get averageAbsoluteDeviation {
    final secs = records.fold(0, (sum, r) => sum + r.seconds);
    if (secs == 0) return 0.0;
    final weightedSum = records.fold(
        0.0,
        (sum, r) =>
            sum + PostureRecord.sanitizeAngle(r.pitch).abs() * r.seconds);
    return (weightedSum / secs).clamp(0.0, 60.0);
  }

  double get maxAbsoluteDeviation {
    if (records.isEmpty) return 0.0;
    final maxVal = records
        .map((r) => PostureRecord.sanitizeAngle(r.pitch).abs())
        .reduce(math.max);
    return maxVal.clamp(0.0, 60.0);
  }

  double get timeInZonePercentage {
    if (totalSeconds == 0) return 100.0;
    return ((neutralSeconds / totalSeconds) * 100.0).clamp(0.0, 100.0);
  }

  double get hourlyEventFrequency {
    if (totalSeconds == 0) return 0.0;
    // Guard against small-sample duration explosion (e.g. 32 events in 2 minutes producing 689.8/hr).
    // Bound the normalizing window to at least 1 hour (3600 seconds) if wear duration is under 1 hr,
    // and clamp to a physiologically realistic upper bound of 60.0 events per hour.
    final effectiveHours = math.max(totalSeconds / 3600.0, 1.0);
    final rate = totalSlouchEvents / effectiveHours;
    return rate.clamp(0.0, 60.0);
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
        : (items.fold(
                    0.0,
                    (sum, r) =>
                        sum +
                        PostureRecord.sanitizeAngle(r.pitch).abs() * r.seconds) /
                seconds)
            .clamp(0.0, 60.0);
  }

  String csv({required bool sample}) {
    final rows = <List<Object>>[
      [
        'source',
        'id',
        'session_id',
        'user_id',
        'mode_id',
        'mode',
        'started_at',
        'ended_at',
        'duration_seconds',
        'baseline_angle',
        'tilt_angle',
        'corrected_at',
        'correction_time_sec',
        'feedback_triggered',
        'angle_threshold_degrees',
        'time_threshold_seconds',
        'zone',
        'slouch_events',
      ],
      for (final r in records)
        [
          sample ? 'sample' : 'measured',
          r.eventId ?? (sample ? 'sample_evt' : ''),
          r.sessionId ?? (sample ? 'sample_sess' : ''),
          r.userId ?? (sample ? 'sample_user' : 'local_user'),
          ModeModel.idForActivityMode(r.mode),
          r.mode.label,
          r.at.toIso8601String(),
          (r.slouched || r.slouchEvents > 0)
              ? (r.correctedAt?.toIso8601String() ??
                  r.at
                      .add(Duration(
                          milliseconds:
                              ((r.correctionSeconds ?? (r.seconds > 0 ? r.seconds.toDouble() : 3.0)) * 1000).round()))
                      .toIso8601String())
              : r.at.add(Duration(seconds: r.seconds)).toIso8601String(),
          r.seconds,
          r.baselineAngle != null ? r.baselineAngle!.toStringAsFixed(1) : '0.0',
          r.pitch,
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
          r.feedbackTriggered ?? (r.slouched || r.slouchEvents > 0),
          r.mode.angle,
          r.mode.seconds,
          r.slouched ? 'slouched' : 'neutral',
          r.slouchEvents,
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

  // Diverse hourly telemetry matching realistic daily posture progression
  final todayData = <int, ({
    int slouch,
    double pitch,
    int seconds,
    int warnings,
    ActivityMode mode,
    double? correctionSec,
  })>{
    6: (
      slouch: 0,
      pitch: 7.5,
      seconds: 1200,
      warnings: 0,
      mode: ActivityMode.normal,
      correctionSec: null,
    ),
    8: (
      slouch: 2,
      pitch: 19.4,
      seconds: 1800,
      warnings: 0,
      mode: ActivityMode.commuting,
      correctionSec: 2.1,
    ),
    10: (
      slouch: 6,
      pitch: 16.8,
      seconds: 2400,
      warnings: 1,
      mode: ActivityMode.focus,
      correctionSec: 1.9,
    ),
    12: (
      slouch: 11,
      pitch: 21.6,
      seconds: 2700,
      warnings: 2,
      mode: ActivityMode.normal,
      correctionSec: 3.8,
    ),
    14: (
      slouch: 7,
      pitch: 14.5,
      seconds: 2400,
      warnings: 1,
      mode: ActivityMode.focus,
      correctionSec: 2.3,
    ),
    16: (
      slouch: 3,
      pitch: 11.2,
      seconds: 2100,
      warnings: 0,
      mode: ActivityMode.normal,
      correctionSec: 2.8,
    ),
    18: (
      slouch: 2,
      pitch: 22.5,
      seconds: 1800,
      warnings: 0,
      mode: ActivityMode.commuting,
      correctionSec: 3.1,
    ),
    20: (
      slouch: 5,
      pitch: 24.8,
      seconds: 1500,
      warnings: 1,
      mode: ActivityMode.leisure,
      correctionSec: 4.5,
    ),
    22: (
      slouch: 1,
      pitch: 13.0,
      seconds: 900,
      warnings: 0,
      mode: ActivityMode.leisure,
      correctionSec: 2.0,
    ),
  };

  // Distinct day-by-day profiles for past 6 days
  final pastDaysData = <int, List<({
    int hour,
    int seconds,
    double pitch,
    ActivityMode mode,
    int slouch,
    int warnings,
    double? correctionSec,
  })>>{
    // 6 days ago (Intensive Focus & Desk Work)
    6: [
      (hour: 8, seconds: 1500, pitch: 18.2, mode: ActivityMode.commuting, slouch: 1, warnings: 0, correctionSec: 2.2),
      (hour: 11, seconds: 2700, pitch: 15.6, mode: ActivityMode.focus, slouch: 8, warnings: 1, correctionSec: 2.5),
      (hour: 14, seconds: 2400, pitch: 21.0, mode: ActivityMode.normal, slouch: 12, warnings: 2, correctionSec: 3.9),
      (hour: 17, seconds: 1800, pitch: 12.0, mode: ActivityMode.normal, slouch: 2, warnings: 0, correctionSec: 2.1),
      (hour: 20, seconds: 1800, pitch: 24.2, mode: ActivityMode.leisure, slouch: 6, warnings: 1, correctionSec: 4.8),
    ],
    // 5 days ago (Light Study & Leisure)
    5: [
      (hour: 9, seconds: 2100, pitch: 12.5, mode: ActivityMode.focus, slouch: 4, warnings: 0, correctionSec: 1.8),
      (hour: 13, seconds: 1800, pitch: 10.4, mode: ActivityMode.normal, slouch: 1, warnings: 0, correctionSec: 1.6),
      (hour: 16, seconds: 2400, pitch: 19.5, mode: ActivityMode.leisure, slouch: 2, warnings: 0, correctionSec: 3.2),
      (hour: 19, seconds: 1500, pitch: 22.8, mode: ActivityMode.leisure, slouch: 5, warnings: 1, correctionSec: 4.1),
    ],
    // 4 days ago (Heavy Technical Sprint)
    4: [
      (hour: 8, seconds: 1800, pitch: 21.5, mode: ActivityMode.commuting, slouch: 2, warnings: 0, correctionSec: 2.8),
      (hour: 10, seconds: 3000, pitch: 17.8, mode: ActivityMode.focus, slouch: 9, warnings: 1, correctionSec: 2.0),
      (hour: 13, seconds: 2700, pitch: 23.5, mode: ActivityMode.normal, slouch: 14, warnings: 2, correctionSec: 4.4),
      (hour: 15, seconds: 2100, pitch: 14.8, mode: ActivityMode.focus, slouch: 6, warnings: 0, correctionSec: 2.2),
      (hour: 18, seconds: 1500, pitch: 17.0, mode: ActivityMode.commuting, slouch: 0, warnings: 0, correctionSec: null),
      (hour: 21, seconds: 1800, pitch: 25.0, mode: ActivityMode.leisure, slouch: 7, warnings: 1, correctionSec: 5.2),
    ],
    // 3 days ago (High Posture Discipline)
    3: [
      (hour: 9, seconds: 2400, pitch: 9.8, mode: ActivityMode.focus, slouch: 1, warnings: 0, correctionSec: 1.3),
      (hour: 11, seconds: 2700, pitch: 11.2, mode: ActivityMode.focus, slouch: 2, warnings: 0, correctionSec: 1.5),
      (hour: 14, seconds: 2100, pitch: 13.8, mode: ActivityMode.normal, slouch: 2, warnings: 0, correctionSec: 2.0),
      (hour: 17, seconds: 1800, pitch: 11.0, mode: ActivityMode.normal, slouch: 0, warnings: 0, correctionSec: null),
      (hour: 20, seconds: 1500, pitch: 18.0, mode: ActivityMode.leisure, slouch: 1, warnings: 0, correctionSec: 2.4),
    ],
    // 2 days ago (Commuting & Mobile Work)
    2: [
      (hour: 8, seconds: 1800, pitch: 23.0, mode: ActivityMode.commuting, slouch: 1, warnings: 0, correctionSec: 2.6),
      (hour: 11, seconds: 2400, pitch: 19.4, mode: ActivityMode.normal, slouch: 7, warnings: 1, correctionSec: 3.4),
      (hour: 15, seconds: 2100, pitch: 16.0, mode: ActivityMode.focus, slouch: 5, warnings: 0, correctionSec: 2.1),
      (hour: 18, seconds: 1500, pitch: 20.8, mode: ActivityMode.commuting, slouch: 2, warnings: 0, correctionSec: 3.0),
      (hour: 21, seconds: 1800, pitch: 22.0, mode: ActivityMode.leisure, slouch: 4, warnings: 0, correctionSec: 3.6),
    ],
    // 1 day ago (Yesterday: Afternoon Slouch Trends)
    1: [
      (hour: 9, seconds: 2400, pitch: 10.5, mode: ActivityMode.focus, slouch: 2, warnings: 0, correctionSec: 1.7),
      (hour: 11, seconds: 2700, pitch: 13.8, mode: ActivityMode.focus, slouch: 5, warnings: 0, correctionSec: 2.3),
      (hour: 14, seconds: 2400, pitch: 17.5, mode: ActivityMode.normal, slouch: 8, warnings: 1, correctionSec: 3.2),
      (hour: 16, seconds: 2100, pitch: 22.2, mode: ActivityMode.normal, slouch: 11, warnings: 2, correctionSec: 4.0),
      (hour: 19, seconds: 1800, pitch: 23.8, mode: ActivityMode.leisure, slouch: 6, warnings: 1, correctionSec: 4.6),
    ],
  };

  return [
    // Days 6 down to 1 (for 7-day history)
    for (final dayEntry in pastDaysData.entries)
      for (final rec in dayEntry.value)
        PostureRecord(
          at: DateTime(ref.year, ref.month, ref.day - dayEntry.key, rec.hour),
          seconds: rec.seconds,
          pitch: rec.pitch,
          mode: rec.mode,
          slouchEvents: rec.slouch,
          warnings: rec.warnings,
          correctionSeconds: rec.correctionSec,
          correctedAt: (rec.correctionSec != null && rec.slouch > 0)
              ? DateTime(ref.year, ref.month, ref.day - dayEntry.key, rec.hour)
                  .add(Duration(milliseconds: (rec.correctionSec! * 1000).round()))
              : null,
        ),

    // Day 0 (Today - guaranteed sample preview data regardless of current hour)
    for (final entry in todayData.entries)
      PostureRecord(
        at: DateTime(ref.year, ref.month, ref.day, entry.key),
        seconds: entry.value.seconds,
        pitch: entry.value.pitch,
        mode: entry.value.mode,
        slouchEvents: entry.value.slouch,
        warnings: entry.value.warnings,
        correctionSeconds: entry.value.correctionSec,
        correctedAt: (entry.value.correctionSec != null && entry.value.slouch > 0)
            ? DateTime(ref.year, ref.month, ref.day, entry.key)
                .add(Duration(milliseconds: (entry.value.correctionSec! * 1000).round()))
            : null,
      ),
  ];
}
