import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service responsible for dispatching OS-level local notifications to the
/// system tray, lock screen, and notification banner on Android and iOS.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Track last alert timestamp to prevent notification spamming
  DateTime? _lastPostureAlertTime;
  Duration _cooldownDuration = const Duration(seconds: 15);

  /// Allows configuring the alert cooldown (default: 15 seconds).
  void setAlertCooldown(Duration duration) {
    _cooldownDuration = duration;
  }

  static const String _channelId = 'poise_posture_alerts';
  static const String _channelName = 'POISE Posture Alerts';
  static const String _channelDescription =
      'Real-time posture adjustment alerts and device status notifications';

  /// Initialize local notification plugin and configure notification channels.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      final success = await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          debugPrint(
              '[LocalNotificationService] User tapped notification: ${response.payload}');
        },
      );

      // Create Android Notification Channel
      final androidImplementation =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );
        await androidImplementation.createNotificationChannel(channel);
      }

      _isInitialized = success ?? true;
      return _isInitialized;
    } catch (e) {
      if (!e.toString().contains('LateInitializationError')) {
        debugPrint('[LocalNotificationService] Failed to initialize: $e');
      }
      return false;
    }
  }

  /// Checks whether system notification permissions are currently enabled.
  Future<bool> isPermissionGranted() async {
    if (kIsWeb) return true;
    try {
      if (!_isInitialized) {
        await initialize();
      }

      final androidImplementation =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final enabled = await androidImplementation.areNotificationsEnabled();
        return enabled ?? false;
      }

      final iosImplementation =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        final settings = await iosImplementation.checkPermissions();
        return settings?.isEnabled ?? false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Called upon app launch: checks if notification permission is allowed,
  /// and if not allowed, immediately prompts the OS permission request dialog.
  Future<bool> ensurePermissionOnAppOpen() async {
    if (kIsWeb) return true;
    try {
      final granted = await isPermissionGranted();
      if (!granted) {
        return await requestPermission();
      }
      return true;
    } catch (_) {
      return await requestPermission();
    }
  }

  /// Request system notification permissions on Android 13+ and iOS.
  Future<bool> requestPermission() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // 1. Android 13+ (POST_NOTIFICATIONS)
      final androidImplementation =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final granted =
            await androidImplementation.requestNotificationsPermission();
        return granted ?? false;
      }

      // 2. iOS
      final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        final granted = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      return true;
    } catch (e) {
      if (!e.toString().contains('LateInitializationError')) {
        debugPrint('[LocalNotificationService] requestPermission error: $e');
      }
      return kIsWeb ||
          (defaultTargetPlatform != TargetPlatform.android &&
              defaultTargetPlatform != TargetPlatform.iOS);
    }
  }

  /// Triggers a high-priority posture reminder/alert to the user's phone.
  /// Enforces a cooldown to prevent rapid-fire notification spamming.
  Future<void> showPostureAlert({
    required String title,
    required String body,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force && _lastPostureAlertTime != null) {
      final elapsed = now.difference(_lastPostureAlertTime!);
      if (elapsed < _cooldownDuration) {
        // Suppress notification until cooldown expires
        return;
      }
    }
    _lastPostureAlertTime = now;

    await _showNotification(
      id: 1001,
      title: title,
      body: body,
      payload: 'poise://posture_alert',
    );
  }

  /// Triggers a device status notification (e.g. Disconnected, Low Battery).
  Future<void> showDeviceNotice({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _showNotification(
      id: id,
      title: title,
      body: body,
      payload: payload ?? 'poise://device_notice',
    );
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      // In widget testing or desktop runners without native notification services,
      // silently ignore uninitialized mock platform.
      if (!e.toString().contains('LateInitializationError')) {
        debugPrint('[LocalNotificationService] showNotification error: $e');
      }
    }
  }

  /// Cancels all active notifications.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
