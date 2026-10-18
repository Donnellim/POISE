import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/calibration_page.dart';
import 'package:flutter_application_1/get_started_page.dart';
import 'package:flutter_application_1/session_entry_page.dart';
import 'package:flutter_application_1/device_check_page.dart';
import 'package:flutter_application_1/dashboard_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/device_session.dart';
import 'package:flutter_application_1/bluetooth/poise_ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PoiseBleService.instance.resetForTesting();
  });
  tearDown(() {
    PoiseBleService.instance.resetForTesting();
    PoiseBleService.instance.simulateForTesting = false;
  });

  testWidgets('first login opens device setup', (tester) async {
    PoiseBleService.instance.simulateForTesting = true;
    await tester.pumpWidget(const MaterialApp(home: SessionEntryPage()));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceCheckPage), findsOneWidget);
  });

  testWidgets('completed setup restores saved device and opens dashboard',
      (tester) async {
    final ble = PoiseBleService.instance;
    ble.simulateForTesting = true;
    await ble.connect(const PoiseDiscoveredDevice(
      id: 'SIMULATED-SAVED',
      name: 'POISE saved',
      rssi: -60,
    ));
    await ble.setZeroBaseline(baselinePitch: 7);
    await DeviceSession.completeSetup();
    ble.resetForTesting();
    await tester.pumpWidget(const MaterialApp(home: SessionEntryPage()));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(DeviceCheckPage), findsNothing);
    expect(ble.isConnected, true);
    expect(ble.connectedDeviceName, 'POISE saved');
    expect(ble.zeroBaselineOffset, 7);
    await tester.pumpWidget(const SizedBox());
  });

  test('first use requires setup', () async {
    expect(await DeviceSession.shouldResume(adapterOn: true), false);
  });

  test('setup survives restart and accidental adapter loss while signed in',
      () async {
    await DeviceSession.completeSetup();
    expect(await DeviceSession.shouldResume(adapterOn: true), true);
    expect(await DeviceSession.shouldResume(adapterOn: false), true);
  });

  test('logout with Bluetooth on preserves setup for next login', () async {
    await DeviceSession.completeSetup();
    await DeviceSession.signedOut(adapterOn: true);
    expect(await DeviceSession.shouldResume(adapterOn: true), true);
    await DeviceSession.signedIn();
    expect(await DeviceSession.shouldResume(adapterOn: false), true);
  });

  test('logout with Bluetooth off resets setup', () async {
    await DeviceSession.completeSetup();
    await DeviceSession.signedOut(adapterOn: false);
    expect(await DeviceSession.shouldResume(adapterOn: true), false);
  });

  test('logout with bluetoothEnabled false resets setup even if adapter is on',
      () async {
    await DeviceSession.completeSetup();
    await DeviceSession.signedOut(adapterOn: true, bluetoothEnabled: false);
    expect(await DeviceSession.shouldResume(adapterOn: true), false);
  });

  test('Bluetooth turned off after logout also resets setup', () async {
    await DeviceSession.completeSetup();
    await DeviceSession.signedOut(adapterOn: true);
    expect(await DeviceSession.shouldResume(adapterOn: false), false);
    expect(await DeviceSession.shouldResume(adapterOn: true), false);
  });

  testWidgets(
      'logging out after turning off Bluetooth routes next login to DeviceCheckPage',
      (tester) async {
    final ble = PoiseBleService.instance;
    ble.simulateForTesting = true;
    await ble.connect(const PoiseDiscoveredDevice(
      id: 'SIMULATED-SAVED',
      name: 'POISE saved',
      rssi: -60,
    ));
    await DeviceSession.completeSetup();
    // Simulate turning off Bluetooth before logout
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('poise.bluetoothEnabled', false);
    await DeviceSession.signedOut(adapterOn: true, bluetoothEnabled: false);

    // Next login via SessionEntryPage
    await tester.pumpWidget(const MaterialApp(home: SessionEntryPage()));
    await tester.pumpAndSettle();

    // Must route to DeviceCheckPage, NOT DashboardPage
    expect(find.byType(DeviceCheckPage), findsOneWidget);
    expect(find.byType(DashboardPage), findsNothing);
  });

  test('mobile refuses fabricated device connections', () async {
    expect(
        await PoiseBleService.instance.connect(const PoiseDiscoveredDevice(
          id: 'SIMULATED-001',
          name: 'POISE',
          rssi: -60,
        )),
        false);
    expect(PoiseBleService.instance.isConnected, false);
  });

  testWidgets(
      'connecting via Quick Settings panel routes directly to CalibrationPage upon login',
      (tester) async {
    final ble = PoiseBleService.instance;
    ble.simulateForTesting = true;
    ble.simulateQuickSettingsSynced = true;

    // User signs in without previous app setup, but device was connected in Quick Settings
    await tester.pumpWidget(const MaterialApp(home: SessionEntryPage()));
    await tester.pumpAndSettle();

    // Must route straight to CalibrationPage, bypassing DeviceCheckPage
    expect(find.byType(CalibrationPage), findsOneWidget);
    expect(find.byType(DeviceCheckPage), findsNothing);
    expect(find.byType(DashboardPage), findsNothing);
    expect(ble.isConnected, true);
  });

  test('requestEnableBluetooth returns true immediately if adapter is already on',
      () async {
    final ble = PoiseBleService.instance;
    ble.simulateForTesting = true;
    // When adapter is already on, requestEnableBluetooth resolves true without throwing/prompting
    final result = await ble.requestEnableBluetooth();
    expect(result, true);
  });

  testWidgets(
      'GetStartedPage Connect to Bluetooth automatically finds and connects POISE device, navigating to CalibrationPage',
      (tester) async {
    final ble = PoiseBleService.instance;
    ble.simulateForTesting = true;

    await tester.pumpWidget(const MaterialApp(home: GetStartedPage()));
    await tester.pumpAndSettle();

    expect(find.text("Let's Get Started"), findsOneWidget);
    expect(find.text('Connect to Bluetooth'), findsOneWidget);

    // Tap Connect to Bluetooth
    await tester.tap(find.text('Connect to Bluetooth'));
    await tester.pump(const Duration(milliseconds: 500));

    // Simulated scan automatically discovers POISE device and triggers connection
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Connected modal appears
    expect(find.text('Proceed to Calibration'), findsOneWidget);
    expect(ble.isConnected, true);

    // Tap Proceed to Calibration
    await tester.tap(find.text('Proceed to Calibration'));
    await tester.pumpAndSettle();

    expect(find.byType(CalibrationPage), findsOneWidget);

    // Tapping Cancel on CalibrationPage returns back to GetStartedPage
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(GetStartedPage), findsOneWidget);
    expect(find.byType(CalibrationPage), findsNothing);
  });
}

