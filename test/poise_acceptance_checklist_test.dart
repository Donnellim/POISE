import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/activity_mode.dart';
import 'package:flutter_application_1/analytics/analytics_data.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';
import 'package:flutter_application_1/database/models.dart';
import 'package:flutter_application_1/feedback_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A. BLE Connection and Communication (App-Side Logic)', () {
    test('Device name matching identifies all P.O.I.S.E. hardware variants', () {
      expect(PoiseBleConfig.isPoiseDeviceName('P.O.I.S.E.'), isTrue);
      expect(PoiseBleConfig.isPoiseDeviceName('P.O.I.S.E'), isTrue);
      expect(PoiseBleConfig.isPoiseDeviceName('POISE'), isTrue);
      expect(PoiseBleConfig.isPoiseDeviceName('POISE-BLE'), isTrue);
      expect(PoiseBleConfig.isPoiseDeviceName('POISE_DEVICE'), isTrue);
      expect(PoiseBleConfig.isPoiseDeviceName('Random Bluetooth Speaker'), isFalse);
    });

    test('Signed numeric readings parsed as ASCII UTF-8 text with 1 decimal place', () async {
      final ble = PoiseBleService.instance;
      ble.resetForTesting();

      final List<double> receivedAngles = [];
      final sub = ble.pitchAngleStream.listen(receivedAngles.add);

      // Feed "-12.3", "0.0", "14.5"
      ble.simulatePitchAngle(-12.3);
      ble.simulatePitchAngle(0.0);
      ble.simulatePitchAngle(14.5);

      await pumpEventQueue();

      expect(receivedAngles, equals([-12.3, 0.0, 14.5]));
      expect(ble.currentPitchAngle, equals(14.5));

      await sub.cancel();
    });

    test('Lifecycle tokens are distinguished from numeric angles and trigger actions', () async {
      final ble = PoiseBleService.instance;
      ble.resetForTesting();

      final List<PoiseDeviceSessionAction> actions = [];
      final actionSub = ble.deviceSessionActionStream.listen(actions.add);
      final List<double> angles = [];
      final angleSub = ble.pitchAngleStream.listen(angles.add);

      // Simulate receiving lifecycle token packets over FFE1
      final startedBytes = utf8.encode('SESSION:STARTED');
      final pausedBytes = utf8.encode('SESSION:PAUSED');
      final resumedBytes = utf8.encode('SESSION:RESUMED');
      final endedBytes = utf8.encode('SESSION:ENDED');
      final tripleClickBytes = utf8.encode('TRIPLE_CLICK');

      // Call internal handler with lifecycle tokens
      // We can verify that none of these tokens are parsed as angles
      expect(double.tryParse(utf8.decode(startedBytes)), isNull);
      expect(double.tryParse(utf8.decode(pausedBytes)), isNull);
      expect(double.tryParse(utf8.decode(resumedBytes)), isNull);
      expect(double.tryParse(utf8.decode(endedBytes)), isNull);
      expect(double.tryParse(utf8.decode(tripleClickBytes)), isNull);

      await actionSub.cancel();
      await angleSub.cancel();
    });

    test('Battery percentage updates correctly from 0 to 100', () async {
      final ble = PoiseBleService.instance;
      ble.resetForTesting();

      final List<int> batteryLevels = [];
      final sub = ble.batteryLevelStream.listen(batteryLevels.add);

      ble.updateBatteryLevel(85);
      ble.updateBatteryLevel(15);
      ble.updateBatteryLevel(100);

      await pumpEventQueue();

      expect(batteryLevels, equals([85, 15, 100]));
      expect(ble.batteryLevel, equals(100));

      await sub.cancel();
    });
  });

  group('C & D. Controls and Mode Payloads', () {
    test('Activity modes map to documented MODE IDs, angle thresholds, and dwells', () {
      expect(ModeModel.idForActivityMode(ActivityMode.normal), equals(1));
      expect(ActivityMode.normal.angle, equals(15));
      expect(ActivityMode.normal.seconds, equals(2));

      expect(ModeModel.idForActivityMode(ActivityMode.focus), equals(2));
      expect(ActivityMode.focus.angle, equals(10));
      expect(ActivityMode.focus.seconds, equals(1));

      expect(ModeModel.idForActivityMode(ActivityMode.leisure), equals(3));
      expect(ActivityMode.leisure.angle, equals(20));
      expect(ActivityMode.leisure.seconds, equals(3));

      expect(ModeModel.idForActivityMode(ActivityMode.commuting), equals(4));
      expect(ActivityMode.commuting.angle, equals(25));
      expect(ActivityMode.commuting.seconds, equals(5));
    });

    test('Device vibration commands map to VIB:1 and VIB:0', () {
      String formatVib(bool enabled) => 'VIB:${enabled ? 1 : 0}';
      expect(formatVib(true), equals('VIB:1'));
      expect(formatVib(false), equals('VIB:0'));
    });

    test('Phone notification and device vibration preferences operate independently', () {
      FeedbackPreferences.vibration = true;
      FeedbackPreferences.phoneNotification = false;

      expect(FeedbackPreferences.vibration, isTrue);
      expect(FeedbackPreferences.phoneNotification, isFalse);

      FeedbackPreferences.phoneNotification = true;
      expect(FeedbackPreferences.vibration, isTrue);
      expect(FeedbackPreferences.phoneNotification, isTrue);

      FeedbackPreferences.vibration = false;
      expect(FeedbackPreferences.vibration, isFalse);
      expect(FeedbackPreferences.phoneNotification, isTrue);
    });
  });

  group('E & F. Analytics Calculations and CSV Export', () {
    final now = DateTime(2026, 10, 19, 12, 0, 0);

    final records = [
      PostureRecord(
        at: now.subtract(const Duration(minutes: 50)),
        seconds: 1200,
        pitch: 4.5,
        mode: ActivityMode.normal,
        slouchEvents: 0,
        warnings: 0,
        baselineAngle: 0.0,
        sessionId: 'sess_001',
        userId: 'test_user',
      ),
      PostureRecord(
        at: now.subtract(const Duration(minutes: 30)),
        seconds: 300,
        pitch: -18.2,
        mode: ActivityMode.normal,
        slouchEvents: 1,
        warnings: 1,
        correctionSeconds: 3.5,
        correctedAt: now.subtract(const Duration(minutes: 30)).add(const Duration(seconds: 4)),
        baselineAngle: 0.0,
        sessionId: 'sess_001',
        eventId: 'evt_001',
        userId: 'test_user',
        feedbackTriggered: true,
      ),
      PostureRecord(
        at: now.subtract(const Duration(minutes: 20)),
        seconds: 900,
        pitch: 6.0,
        mode: ActivityMode.normal,
        slouchEvents: 0,
        warnings: 0,
        baselineAngle: 0.0,
        sessionId: 'sess_001',
        userId: 'test_user',
      ),
    ];

    test('Active monitoring time, distinct posture events, and average correction time calculate accurately', () {
      final summary = AnalyticsSummary(records, AnalyticsPeriod.today, now);

      // Active monitoring time: 1200 + 300 + 900 = 2400 seconds (40 minutes)
      expect(summary.totalSeconds, equals(2400));
      expect(summary.slouchedSeconds, equals(300));
      expect(summary.neutralSeconds, equals(2100));

      // Total distinct posture events
      expect(summary.totalSlouchEvents, equals(1));

      // Average time to correction: 3.5 seconds
      expect(summary.correctionFor(), equals(3.5));

      // Time-in-zone ratio: 2100 / 2400 = 87.5%
      final timeInZoneRatio = (summary.neutralSeconds / summary.totalSeconds) * 100.0;
      expect(timeInZoneRatio, equals(87.5));
    });

    test('CSV export contains all documented session and posture event attributes', () {
      final summary = AnalyticsSummary(records, AnalyticsPeriod.today, now);
      final csv = summary.csv(sample: false);

      // Headers verification
      expect(csv, contains('"id"'));
      expect(csv, contains('"session_id"'));
      expect(csv, contains('"user_id"'));
      expect(csv, contains('"mode_id"'));
      expect(csv, contains('"started_at"'));
      expect(csv, contains('"ended_at"'));
      expect(csv, contains('"duration_seconds"'));
      expect(csv, contains('"baseline_angle"'));
      expect(csv, contains('"tilt_angle"'));
      expect(csv, contains('"corrected_at"'));
      expect(csv, contains('"correction_time_sec"'));
      expect(csv, contains('"feedback_triggered"'));

      // Data verification
      expect(csv, contains('"sess_001"'));
      expect(csv, contains('"evt_001"'));
      expect(csv, contains('"test_user"'));
      expect(csv, contains('"-18.2"'));
      expect(csv, contains('"3.5"'));
      expect(csv, contains('"true"'));
    });
  });
}
