import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../activity_mode.dart';
import '../widgets/poise_app_bar.dart';
import '../analytics/analytics_data.dart';
import '../analytics/csv_export.dart';

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
  bool _preview = false;
  bool _exporting = false;

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

  Future<void> _export(AnalyticsSummary summary) async {
    if (_exporting || summary.records.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final date = summary.now.toIso8601String().split('T').first;
      final message = await exportCsv(summary.csv(sample: _preview),
          'poise-${_preview ? 'sample-' : ''}${_period.name}-$date.csv');
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
    final effectiveNow = _preview
        ? DateTime(now.year, now.month, now.day, 23, 59, 59)
        : now;
    final summary = AnalyticsSummary(
        _preview ? sampleRecords(now) : widget.records, _period, effectiveNow);
    return DefaultTextStyle(
      style: const TextStyle(color: _ink, fontSize: 12, fontFamily: 'Roboto'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 76),
        child: SingleChildScrollView(
          key: const PageStorageKey('analytics-scroll'),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PoiseHeader(),
          const SizedBox(height: 18),
          const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text('Analysis',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
          const SizedBox(height: 14),
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
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                  color: _panel.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(4)),
              child: Row(children: [
                Expanded(
                    child: Text(
                        _preview
                            ? 'SAMPLE PREVIEW • Not your readings'
                            : widget.records.isEmpty
                                ? 'No recorded sensor data yet'
                                : 'Recorded sensor data',
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w600))),
                TextButton(
                    onPressed: () => setState(() => _preview = !_preview),
                    style: TextButton.styleFrom(
                        foregroundColor: _ink,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    child: Text(_preview ? 'Exit preview' : 'Preview charts',
                        style: const TextStyle(fontSize: 9))),
              ])),
          const SizedBox(height: 9),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _SummaryCard(
                    icon: Icons.timer_outlined,
                    color: const Color(0xFF00C700),
                    title: 'Active Wear Time',
                    value: wearDuration(summary.totalSeconds),
                    subtitle: 'Total duration')),
            const SizedBox(width: 8),
            Expanded(
                child: _SummaryCard(
                    icon: Icons.speed,
                    color: const Color(0xFF388AF6),
                    title: 'Average Correction Speed',
                    value: summary.correctionFor() == null
                        ? '—'
                        : '${summary.correctionFor()!.toStringAsFixed(1)}s',
                    subtitle: 'Average time to correct')),
            const SizedBox(width: 8),
            Expanded(
                child: _SummaryCard(
                    icon: Icons.warning,
                    color: _red,
                    title: 'Fatigue Warnings Triggered',
                    value: '${summary.warnings}',
                    subtitle: 'Total warnings')),
          ]),
          const SizedBox(height: 10),
          _ChartCard(
              letter: 'A',
              title: _period == AnalyticsPeriod.today
                  ? 'Hourly Slouch Frequency'
                  : 'Daily Slouch Frequency',
              child: summary.records.isEmpty
                  ? const _EmptyChart()
                  : _FrequencyChart(summary: summary)),
          const SizedBox(height: 10),
          _ChartCard(
              letter: 'B',
              title: 'Time-in-Zone Ratio',
              child: summary.records.isEmpty
                  ? const _EmptyChart()
                  : _ZoneChart(summary: summary)),
          const SizedBox(height: 10),
          _ChartCard(
              letter: 'C',
              title: 'Posture Degradation Trend',
              child: summary.records.isEmpty
                  ? const _EmptyChart()
                  : _TrendChart(summary: summary)),
          const SizedBox(height: 10),
          _ChartCard(
              letter: 'D',
              title: 'Contextual Mode Analysis',
              child: _ModeChart(summary: summary)),
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
                                  : _preview
                                      ? 'Sample records for the selected period.'
                                      : 'Telemetry and fatigue events for this period.',
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
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        icon: const Icon(Icons.download, size: 16),
                        label: Text(_exporting ? 'Exporting…' : csvActionLabel,
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
      {required this.letter, required this.title, required this.child});
  final String letter, title;
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
FlTitlesData _titles(AnalyticsSummary summary, {bool degrees = false}) =>
    FlTitlesData(
      topTitles: _hiddenAxis,
      rightTitles: _hiddenAxis,
      leftTitles: AxisTitles(
          axisNameWidget: Text(degrees ? 'Average pitch (°)' : 'Total count',
              style: _small),
          axisNameSize: 14,
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: degrees
                  ? 5
                  : math
                      .max(
                          1,
                          (List.generate(summary.bucketCount, summary.eventsAt)
                                      .reduce(math.max) /
                                  5)
                              .ceil())
                      .toDouble(),
              getTitlesWidget: (v, meta) =>
                  Text('${v.toInt()}${degrees ? '°' : ''}', style: _small))),
      bottomTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                if (v != v.roundToDouble() ||
                    v < 0 ||
                    v >= summary.bucketCount) {
                  return const SizedBox.shrink();
                }
                return Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(summary.bucketLabel(v.toInt()),
                        style: const TextStyle(fontSize: 7, color: _ink)));
              })),
    );
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
                '${(seconds / summary.totalSeconds * 100).toStringAsFixed(1)}%',
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
    final max = spots
        .where((s) => !s.isNull())
        .fold(0.0, (value, s) => math.max(value, s.y));
    return Column(children: [
      SizedBox(
          height: 135,
          child: LineChart(LineChartData(
            minX: 0,
            maxX: (summary.bucketCount - 1).toDouble(),
            minY: 0,
            maxY: math.max(5, (max * 1.2 / 5).ceil() * 5).toDouble(),
            titlesData: _titles(summary, degrees: true),
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
                  barWidth: 2,
                  isCurved: false,
                  dotData: const FlDotData(show: true))
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
      const Text('Average Correction Speed (s)', style: _small),
      if (summary.correctionFor() == null)
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No completed corrections in this period.',
                style: _small)),
    ]);
  }
}
