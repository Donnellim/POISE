import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/notifications/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalNotificationService Tests', () {
    test('Singleton instance is non-null and default state is valid', () {
      final service = LocalNotificationService.instance;
      expect(service, isNotNull);
      expect(service.isInitialized, isFalse);
    });

    test('Alert cooldown can be configured', () {
      final service = LocalNotificationService.instance;
      service.setAlertCooldown(const Duration(seconds: 5));
      // Should execute without throwing
    });

    test('showPostureAlert and showDeviceNotice execute safely without crashing in test', () async {
      final service = LocalNotificationService.instance;
      await service.showPostureAlert(
        title: 'Posture Alert',
        body: 'Please adjust your posture.',
        force: true,
      );
      await service.showDeviceNotice(
        id: 101,
        title: 'Device Disconnected',
        body: 'Check Bluetooth connection.',
      );
      await service.cancelAll();
    });

    test('requestPermission runs safely in test environment', () async {
      final service = LocalNotificationService.instance;
      final result = await service.requestPermission();
      expect(result, isTrue);
    });
  });
}
