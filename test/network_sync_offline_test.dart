import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/database/network_service.dart';
import 'package:flutter_application_1/database/sync_service.dart';
import 'package:flutter_application_1/tabs/dashboard_tab.dart';
import 'package:flutter_application_1/activity_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NetworkService.instance.mockIsConnectedForTesting = null;
  });

  tearDown(() {
    NetworkService.instance.mockIsConnectedForTesting = null;
  });

  group('NetworkService & SyncService Offline-First Architecture', () {
    test('NetworkService detects offline state and prevents cloud sync', () async {
      NetworkService.instance.mockIsConnectedForTesting = false;
      expect(NetworkService.instance.isConnected, isFalse);

      final result = await SyncService.instance.syncToCloud();
      expect(result, isFalse);
      expect(
        SyncService.instance.lastError.value,
        contains('No internet connection'),
      );
    });

    test('NetworkService triggers auto-sync callback when connection is restored', () async {
      bool autoSyncTriggered = false;
      NetworkService.instance.mockIsConnectedForTesting = false;
      NetworkService.instance.setOnConnectionRestored(() {
        autoSyncTriggered = true;
      });

      // Simulate connection restored
      NetworkService.instance.mockIsConnectedForTesting = true;
      await NetworkService.instance.checkConnectivity();

      expect(autoSyncTriggered, isTrue);
      expect(NetworkService.instance.isConnected, isTrue);
    });

    testWidgets('Dashboard status pill and modal reflect Offline when internet is disconnected',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      NetworkService.instance.mockIsConnectedForTesting = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardTab(
              activeMode: ActivityMode.study,
              isBluetoothConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dashboard status pill shows "Offline"
      expect(find.text('Offline'), findsOneWidget);

      // Tap on Cloud Sync area in status pill
      await tester.tap(find.text('Offline'));
      await tester.pumpAndSettle();

      // Modal bottom sheet opens showing Offline status
      expect(find.text('Cloud Sync: Offline'), findsOneWidget);
      expect(
        find.textContaining('No internet connection'),
        findsOneWidget,
      );

      // Tap "Sync Posture Data Now" while offline
      await tester.tap(find.text('Sync Posture Data Now'));
      await tester.pumpAndSettle();

      // SnackBar alerts user that sync cannot be performed while offline
      expect(
        find.text('Cannot sync while offline. Please connect to Wi-Fi or mobile data.'),
        findsOneWidget,
      );
    });
  });
}
