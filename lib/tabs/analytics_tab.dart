import '../auth/social_auth.dart';
import '../database/sync_service.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../activity_mode.dart';
import '../widgets/poise_app_bar.dart';
import '../analytics/analytics_data.dart';
import '../analytics/csv_export.dart';
import '../database/local_database.dart';
import '../database/models.dart';

const _ink = Color(0xFF073344);
const _blue = Color(0xFF009CE5);
const _panel = Color(0xFFB5E9F9);
const _green = Color(0xFF509E2F);
const _red = Color(0xFFE41528);
const _small = TextStyle(fontSize: 8, color: _ink);

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key, this.records = const [], this.now});
  final List<PostureRecord> records;
  final DateTime Function()? now;
  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  AnalyticsPeriod _period = AnalyticsPeriod.today;
  bool _showInfo = true;
  bool _exporting = false;
  List<PostureRecord> _localRecords = [];
  List<Map<String, dynamic>> _deviceEvents = [];
  List<SessionModel> _localSessions = [];
  bool _isLoadingDb = false;
  bool _hasPendingReload = false;

  @override
  void initState() {
    super.initState();
    if (widget.records.isEmpty) {
      _loadLocalRecords();
      PoiseLocalDatabase.instance.onDatabaseChanged
          .addListener(_onDatabaseChanged);
    }
  }

  @override
  void didUpdateWidget(AnalyticsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.records.isNotEmpty) {
      PoiseLocalDatabase.instance.onDatabaseChanged
          .removeListener(_onDatabaseChanged);
    } else if (oldWidget.records.isNotEmpty && widget.records.isEmpty) {
      _loadLocalRecords();
      PoiseLocalDatabase.instance.onDatabaseChanged
          .addListener(_onDatabaseChanged);
    }
  }

  @override
  void dispose() {
    PoiseLocalDatabase.instance.onDatabaseChanged
        .removeListener(_onDatabaseChanged);
    super.dispose();
  }

  void _onDatabaseChanged() {
    _loadLocalRecords();
  }

  Future<void> _loadLocalRecords() async {
    if (_isLoadingDb) {
      _hasPendingReload = true;
      return;
    }
    _isLoadingDb = true;
    try {
      final imported = await PoiseLocalDatabase.instance.getDeviceEvents();
      final records = await PoiseLocalDatabase.instance.getAllPostureRecords();
      final sessions =
          await PoiseLocalDatabase.instance.getAllSessions(limit: 20);
      if (mounted) {
        setState(() {
          _deviceEvents = imported;
          _localRecords = records;
          _localSessions = sessions;
        });
      }
    } catch (_) {
    } finally {
      _isLoadingDb = false;
      if (_hasPendingReload) {
        _hasPendingReload = false;
        _loadLocalRecords();
      }
    }
  }

  List<SessionModel> _getEffectiveSessions(DateTime now) {
    return _localSessions.where((s) {
      final diff = now.difference(s.startedAt);
      switch (_period) {
        case AnalyticsPeriod.today:
          return s.startedAt.year == now.year &&
              s.startedAt.month == now.month &&
              s.startedAt.day == now.day;
        case AnalyticsPeriod.week:
          return diff.inDays < 7 && !diff.isNegative;
        case AnalyticsPeriod.month:
          return diff.inDays < 30 && !diff.isNegative;
        case AnalyticsPeriod.year:
          return diff.inDays < 365 && !diff.isNegative;
      }
    }).toList();
  }

  void _selectPeriod(AnalyticsPeriod period) {
    if (period == AnalyticsPeriod.month || period == AnalyticsPeriod.year) {
      showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                backgroundColor: _panel,
                title: const Text('Long-term history',
                    style: TextStyle(color: _ink)),
                content: const Text(
                    '30 Days and This Year require a free account and connected cloud history. Cloud history is not connected in this build. You can view available records using Today or 7 Days.',
                    style: TextStyle(color: _ink)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'))
                ],
              ));
      return;
    }
    setState(() => _period = period);
  }

  List<PostureRecord> _getCombinedRecords(DateTime now) {
    final list = <PostureRecord>[];

    // When finalized device events exist, keep only neutral wear records from local sessions
    // so diagnostic/warning records do not inflate the finalized posture event count or duration.
    if (_deviceEvents.isNotEmpty) {
      for (final r in _localRecords) {
        if (r.slouchEvents == 0) {
          list.add(r);
        }
      }
    } else {
      list.addAll(_localRecords);
    }

    final seen = <String>{};
    for (final e in _deviceEvents) {
      final deviceId = e['device_id']?.toString() ?? '';
      final eventId = e['event_id']?.toString() ?? '';
      final dedupeKey = '$deviceId/$eventId';
      if (seen.contains(dedupeKey)) {
        continue;
      }
      seen.add(dedupeKey);

      final startMs = e['start_time_ms'] as num?;
      final endMs = e['end_time_ms'] as num?;
      final at = (startMs != null && startMs > 100000000000)
          ? DateTime.fromMillisecondsSinceEpoch(startMs.toInt(), isUtc: true)
              .toLocal()
          : (endMs != null && endMs > 100000000000
              ? DateTime.fromMillisecondsSinceEpoch(endMs.toInt(), isUtc: true)
                  .toLocal()
              : now);
      final correctedAt = endMs != null
          ? DateTime.fromMillisecondsSinceEpoch(endMs.toInt(), isUtc: true)
              .toLocal()
          : null;
      final correctionStatus = e['correction_status']?.toString();
      final endReason = e['end_reason']?.toString();
      final isCorrected = correctionStatus == 'corrected' ||
          endReason == 'posture_corrected';
      final corrSec = (isCorrected && startMs != null && endMs != null && endMs >= startMs)
          ? (endMs - startMs) / 1000.0
          : null;
      final modeId = (e['mode_id'] as num?)?.toInt() ?? 1;
      final mode = ModeModel.activityModeFromId(modeId);
      final peakDev = (e['peak_deviation_deg'] as num?)?.toDouble() ?? 0.0;
      final vibCount = (e['vibration_count'] as num?)?.toInt() ?? 0;
      final feedback = (endReason == 'posture_corrected') || vibCount > 0;

      list.add(PostureRecord(
        at: at,
        correctedAt: correctedAt,
        seconds: 0,
        pitch: peakDev,
        mode: mode,
        slouchEvents: 1,
        warnings: vibCount,
        correctionSeconds: corrSec,
        eventId: eventId,
        sessionId: e['session_id']?.toString(),
        userId: e['owner_id']?.toString(),
        feedbackTriggered: feedback,
        endReason: endReason,
        correctionStatus: correctionStatus,
      ));
    }
    list.sort((a, b) => a.at.compareTo(b.at));
    return list;
  }

  Future<void> _syncImportedHistory() async {
    final user = SocialAuth.instance.user;
    if (user == null) return;
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Sync local posture history?'),
                content: const Text(
                    'Link imported history on this phone to your account and sync it with Supabase?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Later')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sync history'))
                ]));
    if (approved != true || SocialAuth.instance.user?.id != user.id) return;
    try {
      await SyncService.instance.approveDeviceHistory(user.id);
      final success = await SyncService.instance.syncToCloud();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(success
                ? 'History synced.'
                : SyncService.instance.lastError.value ??
                    'Sync failed. Local history is retained.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sync failed: $error')));
      }
    }
  }

  Future<void> _export(AnalyticsSummary summary) async {
    if (_exporting || summary.records.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final date = summary.now.toIso8601String().split('T').first;
      final message = await exportCsv(summary.csv(sample: false),
          'poise-${_period.name}-$date.csv');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 86)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not export CSV. Please try again.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 86)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showNoDataExportDialog() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
            color: const Color(0xFF45A6B8),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.file_download_off_rounded,
                  color: Color(0xFF0F1E29),
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Cannot Export CSV',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F1E29),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You cannot download the analytics to convert it into a CSV because it has no data or readings at all.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF132F3D),
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF388AF6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now?.call() ?? DateTime.now();
    final activeRecords = widget.records.isNotEmpty
        ? widget.records
        : _getCombinedRecords(now);
    final summary = AnalyticsSummary(activeRecords, _period, now);
    return DefaultTextStyle(
      style: const TextStyle(color: _ink, fontSize: 12, fontFamily: 'Roboto'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 76),
        child: SingleChildScrollView(
          key: const PageStorageKey('analytics-scroll'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PoiseHeader(),
            const SizedBox(height: 12),
            const Text('Analysis',
                style: TextStyle(
                  color: Color(0xFF0F1E29),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                  color: _panel, borderRadius: BorderRadius.circular(5)),
              child: Row(children: [
                for (final period in AnalyticsPeriod.values)
                  Expanded(
                      child: Semantics(
                    selected: period == _period,
                    button: true,
                    child: InkWell(
                        onTap: () => _selectPeriod(period),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 2),
                          decoration: BoxDecoration(
                              color: period == _period
                                  ? const Color(0xFF00BED6)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4)),
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(period.label,
                                        style: const TextStyle(fontSize: 10)),
                                    if (period == AnalyticsPeriod.month ||
                                        period == AnalyticsPeriod.year) ...[
                                      const SizedBox(width: 2),
                                      const Icon(Icons.lock,
                                          size: 12, color: _ink)
                                    ],
                                  ])),
                        )),
                  )),
              ]),
            ),
            const SizedBox(height: 9),
            if (_showInfo) ...[
              Container(
                  padding: const EdgeInsets.only(left: 9),
                  decoration: BoxDecoration(
                      color: _panel, borderRadius: BorderRadius.circular(4)),
                  child: Row(children: [
                    const Icon(Icons.info, color: Color(0xFF388AF6), size: 20),
                    const SizedBox(width: 7),
                    const Expanded(
                        child: Text(
                            '30 Days and This Year require a free account to unlock long-term cloud history.',
                            style: TextStyle(fontSize: 8))),
                    IconButton(
                        tooltip: 'Dismiss history notice',
                        onPressed: () => setState(() => _showInfo = false),
                        icon: const Icon(Icons.close, color: _ink, size: 18)),
                  ])),
              const SizedBox(height: 9),
            ],
            if (activeRecords.isEmpty) ...[
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                      color: _panel.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4)),
                  child: Row(children: const [
                    Icon(Icons.info_outline, size: 14, color: _ink),
                    SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            'No recorded sensor data yet',
                            style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w600))),
                  ])),
              const SizedBox(height: 9),
            ],
            const SizedBox(height: 9),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: _SummaryCard(
                      icon: Icons.timer_outlined,
                      color: const Color(0xFF00C700),
                      title: 'Active Monitoring Time',
                      value: wearDuration(summary.totalSeconds),
                      subtitle: 'Total duration')),
              const SizedBox(width: 8),
              Expanded(
                  child: _SummaryCard(
                      icon: Icons.speed,
                      color: const Color(0xFF388AF6),
                      title: 'Average Time to Correction',
                      value: summary.correctionFor() == null
                          ? '—'
                          : '${summary.correctionFor()!.toStringAsFixed(1)}s',
                      subtitle: 'Average time to correct')),
              const SizedBox(width: 8),
              Expanded(
                  child: _SummaryCard(
                      icon: Icons.airline_seat_recline_extra_rounded,
                      color: const Color(0xFFFF7043),
                      title: 'Total Posture Events',
                      value: '${summary.totalSlouchEvents}',
                      subtitle: 'Total corrected events')),
            ]),
            const SizedBox(height: 10),

            // ── Data Continuity Notice ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF388AF6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFF388AF6).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.sensors_rounded, size: 14, color: _ink),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Data Continuity: Sensor intervals reflect active, connected monitoring. Bluetooth disconnections and dropouts are excluded from posture calculations.',
                      style: TextStyle(
                        fontSize: 8.5,
                        color: _ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Detailed Session Summary Card ──
            _SessionSummaryCard(summary: summary),
            const SizedBox(height: 10),

            _ChartCard(
                letter: 'A',
                title: _period == AnalyticsPeriod.today
                    ? 'Hourly Posture Event Frequency'
                    : 'Daily Posture Event Frequency',
                subtitle: _period == AnalyticsPeriod.today
                    ? 'Hourly Slouch Frequency'
                    : 'Daily Slouch Frequency',
                child: summary.records.isEmpty
                    ? const _EmptyChart()
                    : _FrequencyChart(summary: summary)),
            const SizedBox(height: 10),
            _ChartCard(
                letter: 'B',
                title: 'Time-in-Zone Ratio',
                child: summary.records.isEmpty || summary.totalSeconds == 0
                    ? const _EmptyChart()
                    : _ZoneChart(summary: summary)),
            const SizedBox(height: 10),
            _ChartCard(
                letter: 'C',
                title: 'Posture Deviation Trend',
                child: summary.records.isEmpty || summary.totalSeconds == 0
                    ? const _EmptyChart()
                    : _TrendChart(summary: summary)),
            const SizedBox(height: 10),
            _ChartCard(
                letter: 'D',
                title: 'Mode Comparison',
                child: _ModeChart(summary: summary)),
            const SizedBox(height: 10),

            // ── Session History ──
            _SessionHistoryCard(
              sessions: _getEffectiveSessions(now),
              period: _period,
              now: now,
            ),
            const SizedBox(height: 10),

            // ── Event Timeline ──
            _EventTimelineCard(
              records: summary.records,
            ),
            const SizedBox(height: 18),
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFF55BCE0),
                    borderRadius: BorderRadius.circular(5)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.description, color: _ink, size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('Export Your Data',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold)),
                            Text(
                                summary.records.isEmpty
                                    ? 'No sensor readings recorded for this period.'
                                    : 'Telemetry and posture events for this period.',
                                style: const TextStyle(fontSize: 9)),
                          ])),
                      const SizedBox(width: 6),
                      TextButton.icon(
                          key: const ValueKey('export-csv'),
                          onPressed: _exporting
                              ? null
                              : () {
                                  if (summary.records.isEmpty) {
                                    _showNoDataExportDialog();
                                  } else {
                                    _export(summary);
                                  }
                                },
                          style: TextButton.styleFrom(
                              backgroundColor: _panel,
                              foregroundColor: _ink,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8)),
                          icon: const Icon(Icons.download, size: 16),
                          label: Text(
                              _exporting ? 'Exporting…' : csvActionLabel,
                              style: const TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold))),
                    ]),
                    if (summary.records.isEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.info_outline, size: 14, color: _ink),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Note: You cannot download or export analytics into CSV without any data or readings.',
                                style: TextStyle(
                                    fontSize: 8.5,
                                    color: _ink,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                )),
            if (_deviceEvents.isNotEmpty && SocialAuth.instance.user != null) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _syncImportedHistory,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                  label: const Text('Sync imported history to cloud'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.value,
      required this.subtitle});
  final IconData icon;
  final Color color;
  final String title, value, subtitle;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
            color: _panel, borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              height: 25,
              child: Row(children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 3),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(fontSize: 7, height: 1.1)))
              ])),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold))),
          Text(subtitle, style: const TextStyle(fontSize: 7)),
        ]),
      );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard(
      {required this.letter,
      required this.title,
      this.subtitle,
      required this.child});
  final String letter, title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _panel.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CHART $letter',
              style: const TextStyle(
                  fontSize: 8, color: _blue, fontWeight: FontWeight.bold)),
          Text(title,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: const TextStyle(fontSize: 8.5, color: Colors.black54)),
          ],
          const SizedBox(height: 18),
          child,
        ]),
      );
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 130,
      child: Center(
          child: Text(
              'No calibrated readings in this period.\nCharts appear when sensor records are available.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: _ink))));
}

const _hiddenAxis = AxisTitles(sideTitles: SideTitles(showTitles: false));
FlTitlesData _titles(AnalyticsSummary summary,
    {bool degrees = false, double? maxY}) {
  final double interval;
  if (degrees) {
    final effectiveMax = maxY ?? 20.0;
    if (effectiveMax <= 15.0) {
      interval = 5.0;
    } else if (effectiveMax <= 30.0) {
      interval = 10.0;
    } else {
      interval = 15.0;
    }
  } else {
    interval = math
        .max(
            1,
            (List.generate(summary.bucketCount, summary.eventsAt)
                        .reduce(math.max) /
                    5)
                .ceil())
        .toDouble();
  }

  return FlTitlesData(
    topTitles: _hiddenAxis,
    rightTitles: _hiddenAxis,
    leftTitles: AxisTitles(
        axisNameWidget:
            Text(degrees ? 'Average pitch (°)' : 'Total count', style: _small),
        axisNameSize: 16,
        sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: interval,
            getTitlesWidget: (v, meta) {
              if (v < 0 || (meta.max > 0 && v > meta.max)) {
                return const SizedBox.shrink();
              }
              if (v != v.roundToDouble() && v % interval != 0) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 4,
                child: Text('${v.toInt()}${degrees ? '°' : ''}', style: _small),
              );
            })),
    bottomTitles: AxisTitles(
        sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 24,
            getTitlesWidget: (v, meta) {
              if (v != v.roundToDouble() || v < 0 || v >= summary.bucketCount) {
                return const SizedBox.shrink();
              }
              return Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(summary.bucketLabel(v.toInt()),
                      style: const TextStyle(fontSize: 7, color: _ink)));
            })),
  );
}

FlBorderData get _border => FlBorderData(
    show: true,
    border: const Border(
        left: BorderSide(color: Color(0xFF70ADC1), width: 0.7),
        bottom: BorderSide(color: Color(0xFF70ADC1), width: 0.7)));

class _Legend extends StatelessWidget {
  const _Legend(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.circle, size: 8, color: _blue),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: _small, textAlign: TextAlign.center))
      ]));
}

class _FrequencyChart extends StatelessWidget {
  const _FrequencyChart({required this.summary});
  final AnalyticsSummary summary;
  @override
  Widget build(BuildContext context) {
    final max =
        List.generate(summary.bucketCount, summary.eventsAt).reduce(math.max);
    return Column(children: [
      SizedBox(
          height: 130,
          child: BarChart(BarChartData(
            minY: 0,
            maxY: math.max(5, (max * 1.3).ceil()).toDouble(),
            titlesData: _titles(summary),
            borderData: _border,
            gridData: const FlGridData(show: false),
            barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Colors.transparent,
                    tooltipPadding: EdgeInsets.zero,
                    tooltipMargin: 3,
                    getTooltipItem: (group, index, rod, rodIndex) =>
                        BarTooltipItem('${rod.toY.toInt()}',
                            const TextStyle(color: _ink, fontSize: 8)))),
            barGroups: [
              for (var i = 0; i < summary.bucketCount; i++)
                BarChartGroupData(
                    x: i,
                    showingTooltipIndicators:
                        summary.eventsAt(i) > 0 ? [0] : [],
                    barRods: [
                      BarChartRodData(
                          toY: summary.eventsAt(i).toDouble(),
                          color: _blue,
                          width: summary.bucketCount == 12 ? 10 : 18,
                          borderRadius: BorderRadius.zero)
                    ])
            ],
          ))),
      const _Legend('Slouch events'),
    ]);
  }
}

class _ZoneChart extends StatelessWidget {
  const _ZoneChart({required this.summary});
  final AnalyticsSummary summary;
  Widget _label(String text, int seconds, Color color) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            Text(
                summary.totalSeconds == 0
                    ? '0.0%'
                    : '${(seconds / summary.totalSeconds * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 20, color: color, fontWeight: FontWeight.bold)),
            Text('(${wearDuration(seconds)})',
                style: TextStyle(fontSize: 11, color: color)),
          ]);
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 145,
      width: double.infinity,
      child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
              width: 310,
              height: 145,
              child: Row(children: [
                SizedBox(
                    width: 80,
                    child: _label(
                        'Neutral\nPosture', summary.neutralSeconds, _green)),
                SizedBox(
                    width: 150,
                    height: 145,
                    child: Stack(alignment: Alignment.center, children: [
                      PieChart(PieChartData(
                          startDegreeOffset: -90,
                          sectionsSpace: 0,
                          centerSpaceRadius: 48,
                          sections: [
                            if (summary.slouchedSeconds > 0)
                              PieChartSectionData(
                                  value: summary.slouchedSeconds.toDouble(),
                                  color: _red,
                                  radius: 22,
                                  showTitle: false),
                            if (summary.neutralSeconds > 0)
                              PieChartSectionData(
                                  value: summary.neutralSeconds.toDouble(),
                                  color: _green,
                                  radius: 22,
                                  showTitle: false),
                          ])),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Total\nWear Time',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10)),
                        Text(wearDuration(summary.totalSeconds),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        const Text('(100%)', style: TextStyle(fontSize: 10))
                      ]),
                    ])),
                SizedBox(
                    width: 80,
                    child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _label(
                            'Slouched\nTime', summary.slouchedSeconds, _red))),
              ]))));
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.summary});
  final AnalyticsSummary summary;
  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < summary.bucketCount; i++)
        if (summary.pitchAt(i) != null)
          FlSpot(i.toDouble(), summary.pitchAt(i)!)
        else
          FlSpot.nullSpot
    ];
    final validSpots = spots.where((s) => !s.isNull()).toList();
    final max = validSpots.fold(0.0, (value, s) => math.max(value, s.y));
    final calculatedMaxY =
        max <= 0 ? 20.0 : math.max(20.0, (max * 1.25 / 5).ceil() * 5.0);

    return Column(children: [
      SizedBox(
          height: 135,
          child: LineChart(LineChartData(
            minX: 0,
            maxX: (summary.bucketCount - 1).toDouble(),
            minY: 0,
            maxY: calculatedMaxY,
            titlesData: _titles(summary, degrees: true, maxY: calculatedMaxY),
            borderData: _border,
            gridData: const FlGridData(show: false),
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(
                  y: 0, color: _blue, dashArray: [4, 4], strokeWidth: 1)
            ]),
            lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _ink,
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                            '${summary.bucketLabel(s.x.toInt())}\n${s.y.toStringAsFixed(1)}°',
                            const TextStyle(fontSize: 10, color: Colors.white)))
                        .toList())),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: _blue,
                barWidth: 2.5,
                isCurved: false,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                    radius: 3.5,
                    color: _blue,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  ),
                ),
              )
            ],
          ))),
      const _Legend('Average pitch magnitude • Baseline 0°'),
    ]);
  }
}

class _ModeChart extends StatelessWidget {
  const _ModeChart({required this.summary});
  final AnalyticsSummary summary;
  @override
  Widget build(BuildContext context) {
    final max = math
        .max(
            7.0,
            ActivityMode.values.fold(
                0.0,
                (value, mode) =>
                    math.max(value, summary.correctionFor(mode) ?? 0)))
        .ceilToDouble();
    return Column(children: [
      for (final mode in ActivityMode.values)
        Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(children: [
              SizedBox(
                  width: 64,
                  child:
                      Text(mode.label, style: const TextStyle(fontSize: 10))),
              Expanded(
                  child: Tooltip(
                      message: summary.correctionFor(mode) == null
                          ? 'No completed corrections'
                          : '${mode.label}: ${summary.correctionFor(mode)!.toStringAsFixed(1)} seconds',
                      child: Row(children: [
                        Expanded(
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                    widthFactor:
                                        (summary.correctionFor(mode) ?? 0) /
                                            max,
                                    child:
                                        Container(height: 16, color: _blue)))),
                        SizedBox(
                            width: 36,
                            child: Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                    summary.correctionFor(mode) == null
                                        ? '—'
                                        : '${summary.correctionFor(mode)!.toStringAsFixed(1)}s',
                                    style: const TextStyle(fontSize: 10)))),
                      ]))),
            ])),
      Padding(
          padding: const EdgeInsets.only(left: 64, right: 36),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i <= 7; i++)
              Text((max * i / 7).toStringAsFixed(0), style: _small)
          ])),
      const SizedBox(height: 8),
      const Text('Average Time to Correction (s)', style: _small),
      if (summary.correctionFor() == null)
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No completed corrections in this period.',
                style: _small)),
    ]);
  }
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final avgDev = summary.averageAbsoluteDeviation;
    final maxDev = summary.maxAbsoluteDeviation;
    final inZone = summary.timeInZonePercentage;
    final freq = summary.hourlyEventFrequency;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SESSION SUMMARY METRICS',
            style: TextStyle(
                fontSize: 8, color: _blue, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Posture Performance Overview',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: _ink),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricItem(
                  label: 'Average Deviation',
                  value: summary.records.isEmpty || summary.totalSeconds == 0
                      ? '—'
                      : '${avgDev.toStringAsFixed(1)}°',
                  caption: 'Mean absolute tilt',
                ),
              ),
              Expanded(
                child: _MetricItem(
                  label: 'Peak Deviation',
                  value: summary.records.isEmpty
                      ? '—'
                      : '${maxDev.toStringAsFixed(1)}°',
                  caption: 'Maximum recorded tilt',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricItem(
                  label: 'Time-in-Zone',
                  value: summary.records.isEmpty || summary.totalSeconds == 0
                      ? '—'
                      : '${inZone.toStringAsFixed(1)}%',
                  caption: 'Time within threshold',
                ),
              ),
              Expanded(
                child: _MetricItem(
                  label: 'Event Frequency',
                  value: summary.records.isEmpty || summary.totalSeconds == 0
                      ? '—'
                      : '${freq.toStringAsFixed(1)}/hr',
                  caption: 'Warning events per hour',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem(
      {required this.label, required this.value, required this.caption});
  final String label, value, caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 8,
                color: Colors.black54,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 1),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
        Text(caption,
            style: const TextStyle(fontSize: 7, color: Colors.black45)),
      ],
    );
  }
}

class _SessionHistoryCard extends StatelessWidget {
  const _SessionHistoryCard({
    required this.sessions,
    required this.period,
    required this.now,
  });

  final List<SessionModel> sessions;
  final AnalyticsPeriod period;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final filtered = sessions.where((s) {
      return !s.startedAt.isBefore(period.start(now)) &&
          !s.startedAt.isAfter(now);
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECORDED SESSIONS',
            style: TextStyle(
                fontSize: 8, color: _blue, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Session History',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: _ink),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No monitoring sessions recorded in this period.',
                style: TextStyle(fontSize: 9, color: Colors.black54),
              ),
            )
          else
            for (final s in filtered.take(5)) _buildSessionRow(s),
        ],
      ),
    );
  }

  Widget _buildSessionRow(SessionModel s) {
    final mode = ModeModel.activityModeFromId(s.modeId);
    final durationSec = s.endedAt != null
        ? s.endedAt!.difference(s.startedAt).inSeconds
        : s.updatedAt.difference(s.startedAt).inSeconds;
    final dur = durationSec > 0 ? wearDuration(durationSec) : 'Active';
    final startTimeStr =
        '${s.startedAt.hour.toString().padLeft(2, '0')}:${s.startedAt.minute.toString().padLeft(2, '0')}';
    final endTimeStr = s.endedAt != null
        ? '${s.endedAt!.hour.toString().padLeft(2, '0')}:${s.endedAt!.minute.toString().padLeft(2, '0')}'
        : 'In progress';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(mode.icon, size: 16, color: _ink),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${mode.label} Mode',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: _ink),
                ),
                Text(
                  '$startTimeStr – $endTimeStr',
                  style: const TextStyle(fontSize: 8, color: Colors.black54),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00BED6).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              dur,
              style: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.bold, color: _ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTimelineCard extends StatelessWidget {
  const _EventTimelineCard({required this.records});
  final List<PostureRecord> records;

  @override
  Widget build(BuildContext context) {
    final events =
        records.where((r) => r.slouched || r.slouchEvents > 0).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'POSTURE EVENT STREAM',
            style: TextStyle(
                fontSize: 8, color: _blue, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Event Timeline',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: _ink),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No posture warning events recorded in this period.',
                style: TextStyle(fontSize: 9, color: Colors.black54),
              ),
            )
          else
            for (final e in events.reversed.take(6)) _buildEventRow(e),
        ],
      ),
    );
  }

  Widget _buildEventRow(PostureRecord e) {
    final timeStr =
        '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}:${e.at.second.toString().padLeft(2, '0')}';
    final corrSec =
        e.correctionSeconds ?? (e.seconds > 0 ? e.seconds.toDouble() : null);

    final durText = corrSec != null
        ? '${corrSec.toStringAsFixed(corrSec % 1 == 0 ? 0 : (corrSec * 10 % 1 == 0 ? 1 : 3))}s'
        : 'Duration unknown';
    final rawStatus = e.correctionStatus ??
        ((e.slouched || e.slouchEvents > 0) ? 'Corrected' : 'Normal');
    final statusText = rawStatus.isNotEmpty
        ? '${rawStatus[0].toUpperCase()}${rawStatus.substring(1)}'
        : 'Corrected';
    final reasonText = e.endReason != null && e.endReason!.isNotEmpty
        ? ' (${e.endReason})'
        : '';
    final vibCount = e.warnings;
    final vibText = vibCount > 0
        ? ' • $vibCount commanded vibration pulse${vibCount == 1 ? '' : 's'}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFE41528),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Warning: ${e.pitch.abs().toStringAsFixed(1)}° (${e.mode.label})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: _ink),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(timeStr,
                        style: const TextStyle(
                            fontSize: 8, color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  '$statusText in $durText$reasonText$vibText',
                  style: const TextStyle(
                      fontSize: 8,
                      color: Color(0xFF509E2F),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
