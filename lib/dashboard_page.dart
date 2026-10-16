import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bluetooth/poise_ble_service.dart';
import 'notifications/notification_center.dart';
import 'notifications/local_notification_service.dart';
import 'feedback_preferences.dart';
import 'auth/social_auth.dart';
import 'widgets/guest_account_prompt.dart';
import 'tabs/dashboard_tab.dart';
import 'activity_mode.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/controls_tab.dart';
import 'tabs/profile_tab.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.isGuest = false,
    this.requiresAccount = false,
    this.initialBluetoothConnected = true,
    this.bluetoothSearchDuration = const Duration(milliseconds: 1200),
    this.initialNotificationPermissionGranted = true,
    this.initialVibrationEnabled,
    this.initialPhoneNotificationEnabled,
    this.initialActiveMode = ActivityMode.normal,
  });

  final bool isGuest;
  final bool requiresAccount;
  final bool initialBluetoothConnected;
  final Duration bluetoothSearchDuration;
  final bool initialNotificationPermissionGranted;
  final bool? initialVibrationEnabled;
  final bool? initialPhoneNotificationEnabled;
  final ActivityMode initialActiveMode;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  StreamSubscription<bool>? _connectionSubscription;
  int _currentIndex = 0;
  final _notifications = NotificationCenter.preview();

  // A running web session can retain state from before modes were shared.
  // Resolve an absent selection before passing it to either tab.
  late ActivityMode _activeMode;
  bool _isBluetoothConnected = true;
  bool _triggerRecalibration = false;

  bool _notificationPermissionGranted = true;
  bool _vibrationEnabled = true;
  bool _phoneNotificationEnabled = false;

  @override
  void initState() {
    super.initState();
    _connectionSubscription =
        PoiseBleService.instance.isConnectedStream.listen((connected) {
      if (mounted) _handleBluetoothChanged(connected);
    });
    _activeMode = widget.initialActiveMode;
    _isBluetoothConnected = widget.initialBluetoothConnected;
    _notificationPermissionGranted =
        widget.initialNotificationPermissionGranted;
    _vibrationEnabled = widget.initialVibrationEnabled ??
        (widget.initialPhoneNotificationEnabled == null
            ? FeedbackPreferences.vibration
            : !widget.initialPhoneNotificationEnabled!);
    if (!_notificationPermissionGranted) _vibrationEnabled = true;
    _phoneNotificationEnabled = !_vibrationEnabled;

    _notifications.onNoticeAdded = _dispatchLocalNotification;
  }

  void _dispatchLocalNotification(PoiseNoticeType type) {
    if (!_phoneNotificationEnabled || !_notificationPermissionGranted) return;

    if (type == PoiseNoticeType.alert || type == PoiseNoticeType.reminder) {
      LocalNotificationService.instance.showPostureAlert(
        title: type.title,
        body: type.message,
      );
    } else if (type == PoiseNoticeType.disconnected ||
        type == PoiseNoticeType.lowBattery) {
      LocalNotificationService.instance.showDeviceNotice(
        id: type.index,
        title: type.title,
        body: type.message,
      );
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _notifications.dispose();
    super.dispose();
  }

  void _handleBluetoothChanged(bool connected) {
    if (connected != _isBluetoothConnected) {
      _notifications.add(
          connected ? PoiseNoticeType.connected : PoiseNoticeType.disconnected);
    }
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('poise.bluetoothEnabled', connected);
    });
    setState(() {
      _isBluetoothConnected = connected;
      if (!connected) {
        _triggerRecalibration = false;
      }
    });
  }

  void _handleReconnectFromProfile() {
    if (!_isBluetoothConnected) _notifications.add(PoiseNoticeType.connected);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('poise.bluetoothEnabled', true);
    });
    setState(() {
      _isBluetoothConnected = true;
      _currentIndex = 0; // Navigate through the dashboard tab
      _triggerRecalibration = false;
    });
  }

  void _handleNotificationPermissionChanged(bool granted) {
    if (granted) {
      LocalNotificationService.instance.requestPermission();
    }
    setState(() {
      _notificationPermissionGranted = granted;
      if (!granted) {
        // If system permission is disabled, phone notifications cannot alert,
        // so switch phone notification off and ensure vibration feedback is active.
        _phoneNotificationEnabled = false;
        _vibrationEnabled = true;
        FeedbackPreferences.save(true);
      }
    });
  }

  void _handleVibrationChanged(bool enabled) {
    if (!enabled && !_notificationPermissionGranted) return;
    setState(() {
      _vibrationEnabled = enabled;
      _phoneNotificationEnabled = !enabled;
    });
    FeedbackPreferences.save(enabled);
  }

  void _handlePhoneNotificationChanged(bool enabled) =>
      _handleVibrationChanged(!enabled);

  List<Widget> _buildTabs() {
    final activeMode = _activeMode;
    final profile = SocialAuth.instance.user;
    return [
      DashboardTab(
        activeMode: activeMode,
        isBluetoothConnected: _isBluetoothConnected,
        onBluetoothChanged: _handleBluetoothChanged,
        triggerRecalibration: _triggerRecalibration,
        onRecalibrationHandled: () {
          setState(() => _triggerRecalibration = false);
        },
        onBaselineSet: () => setState(() => _currentIndex = 0),
      ),
      const AnalyticsTab(),
      ControlsTab(
        selectedMode: activeMode,
        onModeChanged: (mode) => setState(() => _activeMode = mode),
        vibrationEnabled: _vibrationEnabled,
        onVibrationChanged: _handleVibrationChanged,
        phoneNotificationEnabled: _phoneNotificationEnabled,
        onPhoneNotificationChanged: _handlePhoneNotificationChanged,
        notificationPermissionGranted: _notificationPermissionGranted,
        onRequestNotificationPermission: () {
          LocalNotificationService.instance.requestPermission();
          setState(() {
            _notificationPermissionGranted = true;
            _phoneNotificationEnabled = true;
            _vibrationEnabled = false;
            FeedbackPreferences.save(false);
          });
        },
      ),
      ProfileTab(
        isGuest: widget.isGuest && profile == null,
        initialUserName: profile == null
            ? (widget.isGuest ? 'Guest User' : 'User 1')
            : (profile.displayName ?? 'POISE User'),
        initialEmail: profile == null
            ? (widget.isGuest ? '' : 'user1@gmail.com')
            : (profile.email ?? ''),
        isBluetoothEnabled: _isBluetoothConnected,
        onBluetoothChanged: _handleBluetoothChanged,
        onReconnectSuccess: _handleReconnectFromProfile,
        bluetoothSearchDuration: widget.bluetoothSearchDuration,
        isNotificationPermissionGranted: _notificationPermissionGranted,
        onNotificationPermissionChanged: _handleNotificationPermissionChanged,
      ),
    ];
  }

  Widget _buildNavItem(int index, IconData icon) {
    final bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Icon(
          icon,
          size: 28,
          color: isSelected ? const Color(0xFF1A2633) : const Color(0xFFB2E3F6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationScope(
      center: _notifications,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF20A6D7), // Sky Blue Top
                Color(0xFFC3E6EF), // Soft Ice Blue Bottom
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: 360), // Mobile frame constraint
                child: Stack(
                  children: [
                    // ── Tab Contents (Fills 100% of the screen height) ──
                    Positioned.fill(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: _buildTabs(),
                      ),
                    ),

                    // ── Floating Cyan-Blue Pill Bottom Navigation Bar (Pinned at bottom) ──
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 14,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF30A5DC), // Cyan-blue pill
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNavItem(0, Icons.home_filled),
                            _buildNavItem(1, Icons.bar_chart_rounded),
                            _buildNavItem(2, Icons.tune_rounded),
                            _buildNavItem(3, Icons.person_rounded),
                          ],
                        ),
                      ),
                    ),
                    if (widget.requiresAccount)
                      const Positioned.fill(child: GuestAccountPrompt()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
