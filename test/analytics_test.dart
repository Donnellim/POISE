import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/activity_mode.dart';
import 'package:flutter_application_1/analytics/analytics_data.dart';
import 'package:flutter_application_1/tabs/analytics_tab.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  final now = DateTime(2026, 10, 10, 23);
  final records = [
    PostureRecord(
        at: DateTime(2026, 10, 10, 8),
        seconds: 600,
        pitch: 5,
        mode: ActivityMode.study),
    PostureRecord(
        at: DateTime(2026, 10, 10, 8, 10),
        seconds: 300,
        pitch: -15,
        mode: ActivityMode.study,
        slouchEvents: 1,
        warnings: 1,
        correctionSeconds: 4),
    PostureRecord(
        at: DateTime(2026, 10, 9, 8),
        seconds: 900,
        pitch: 22,
        mode: ActivityMode.leisure,
        slouchEvents: 2,
        warnings: 1,
        correctionSeconds: 6),
    PostureRecord(
        at: DateTime(2026, 10, 3, 23),
        seconds: 600,
        pitch: 0,
        mode: ActivityMode.study),
    PostureRecord(
        at: DateTime(2026, 10, 11),
        seconds: 100,
        pitch: 0,
        mode: ActivityMode.study),
    PostureRecord(
        at: DateTime(2026, 10, 10),
        seconds: 100,
        pitch: double.nan,
        mode: ActivityMode.study),
  ];
  test('Filters, durations, correction means and chart buckets agree', () {
    final today = AnalyticsSummary(records, AnalyticsPeriod.today, now);
    expect(today.totalSeconds, 900);
    expect(today.neutralSeconds, 600);
    expect(today.slouchedSeconds, 300);
    expect(today.warnings, 1);
    expect(today.correctionFor(), 4);
    expect(today.correctionFor(ActivityMode.leisure), isNull);
    expect(today.eventsAt(4), 1);
    expect(today.pitchAt(4), closeTo(8.3333, 0.001));
    expect(today.pitchAt(0), isNull);
    final week = AnalyticsSummary(records, AnalyticsPeriod.week, now);
    expect(week.totalSeconds, 1800);
    expect(week.correctionFor(), 5);
    expect(week.eventsAt(5), 2);
    expect(week.eventsAt(6), 1);
    expect(week.records.length, 3);
    expect(week.neutralSeconds + week.slouchedSeconds, week.totalSeconds);
  });
  test('CSV uses only selected records and marks preview data', () {
    final summary = AnalyticsSummary(records, AnalyticsPeriod.today, now);
    final csv = summary.csv(sample: false);
    expect(csv.split('\r\n').length, 4);
    expect(csv, contains('"measured"'));
    expect(csv, contains('"-15.0"'));
    expect(csv, isNot(contains('2026-10-09')));
    expect(summary.csv(sample: true), contains('"sample"'));
    expect(AnalyticsSummary([], AnalyticsPeriod.today, now).correctionFor(),
        isNull);
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('Analytics filters, preview, notice and export work at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copiedCsv;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedCsv = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
          home:
              Scaffold(body: AnalyticsTab(records: records, now: () => now))));
      await tester.pumpAndSettle();
      expect(find.text('15m'), findsWidgets);
      await tester.tap(find.text('7 Days'));
      await tester.pumpAndSettle();
      expect(find.text('30m'), findsWidgets);
      expect(find.text('Daily Slouch Frequency'), findsOneWidget);
      await tester.tap(find.text('30 Days'));
      await tester.pumpAndSettle();
      expect(find.text('Long-term history'), findsNothing);
      await tester.tap(find.text('7 Days'));
      await tester.pumpAndSettle();
      expect(find.text('Daily Slouch Frequency'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss history notice'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Dismiss history notice'), findsNothing);
      await tester.tap(find.text('Preview charts'));
      await tester.pumpAndSettle();
      expect(find.text('SAMPLE PREVIEW • Not your readings'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('export-csv')), 250);
      await tester.tap(find.byKey(const ValueKey('export-csv')));
      await tester.pumpAndSettle();
      expect(copiedCsv, contains('"sample"'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('No records means empty charts and shows overlay on export tap',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AnalyticsTab(now: () => now))));
    expect(find.text('No recorded sensor data yet'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
    final button = find.byKey(const ValueKey('export-csv'));
    expect(button, findsOneWidget);
    expect(
        find.text(
            'Note: You cannot download or export analytics into CSV without any data or readings.'),
        findsOneWidget);
    await tester.scrollUntilVisible(button, 250);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Cannot Export CSV'), findsOneWidget);
    expect(
        find.text(
            'You cannot download the analytics to convert it into a CSV because it has no data or readings at all.'),
        findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot Export CSV'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today preview mode generates and displays charts',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AnalyticsTab(now: () => now))));
    expect(find.byType(BarChart), findsNothing);
    await tester.tap(find.text('Preview charts'));
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Centidegree raw pitch and baseline angles normalize to realistic physical bounds', () {
    final testNow = DateTime(2026, 10, 19, 12);
    // Simulating legacy/centidegree records: 565.7 baseline and 3141.0 peak slouch
    final unscaledRecords = [
      PostureRecord(
        at: testNow.subtract(const Duration(minutes: 2)),
        seconds: 120,
        pitch: 565.7, // Centidegrees -> 5.66°
        baselineAngle: 565.7,
        mode: ActivityMode.normal,
      ),
      PostureRecord(
        at: testNow.subtract(const Duration(seconds: 40)),
        seconds: 40,
        pitch: 3141.0, // Centidegrees -> 31.41°
        mode: ActivityMode.normal,
        slouchEvents: 1,
      ),
    ];

    final summary = AnalyticsSummary(unscaledRecords, AnalyticsPeriod.today, testNow);

    // Mean absolute deviation must reflect physical angle (~12.1°), NOT 565.7°!
    expect(summary.averageAbsoluteDeviation, closeTo(12.1, 0.5));
    expect(summary.averageAbsoluteDeviation, lessThanOrEqualTo(60.0));

    // Peak deviation must reflect physical peak (31.4°), NOT 3141.0°!
    expect(summary.maxAbsoluteDeviation, closeTo(31.41, 0.1));
    expect(summary.maxAbsoluteDeviation, lessThanOrEqualTo(60.0));
  });

  test('Short wear duration event frequency avoids astronomical rates', () {
    final testNow = DateTime(2026, 10, 19, 12);
    // Simulating 32 events in a 167-second test session
    final shortSessionRecords = [
      for (int i = 0; i < 32; i++)
        PostureRecord(
          at: testNow.subtract(Duration(seconds: 167 - i * 5)),
          seconds: 5,
          pitch: 20.0,
          mode: ActivityMode.normal,
          slouchEvents: 1,
        ),
    ];

    final summary = AnalyticsSummary(shortSessionRecords, AnalyticsPeriod.today, testNow);
    expect(summary.totalSeconds, 160);
    expect(summary.totalSlouchEvents, 32);

    // Prior formula gave 32 / (160/3600) = 720.0/hr!
    // With normalization against at least 1 hr, rate is 32.0/hr (capped <= 60.0/hr).
    expect(summary.hourlyEventFrequency, closeTo(32.0, 0.1));
    expect(summary.hourlyEventFrequency, lessThanOrEqualTo(60.0));
  });
}
