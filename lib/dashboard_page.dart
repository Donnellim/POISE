import 'database/sync_service.dart';
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
import 'mode_preferences.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/controls_tab.dart';
import 'tabs/profile_tab.dart';
import 'database/local_database.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.isGuest = false,
    this.requiresAccount = false,
    this.initialBluetoothConnected = true,
    this.bluetoothSearchDuration = const Duration(seconds: 8),
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
  StreamSubscription<ActivityMode>? _modeSubscription;
  StreamSubscription<bool>? _modeSyncSubscription;
  int _currentIndex = 0;
  int? _promptedConnection;
  bool _historyDialogOpen = false;
  bool _cloudHistoryChecked = false;
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
    _modeSubscription = PoiseBleService.instance.modeStream.listen((mode) {
      if (mounted && _activeMode != mode) {
        setState(() {
          _activeMode = mode;
        });
      }
    });
    _modeSyncSubscription = PoiseBleService.instance.modeSyncStream.listen((_) {
      if (mounted) setState(() {});
    });

    PoiseBleService.instance.protocolChanges.addListener(_protocolChanged);
    _activeMode = PoiseBleService.instance.phoneSavedMode;
    ModePreferences.getSavedMode().then((mode) {
      if (mounted &&
          !PoiseBleService.instance.isModeSynchronized &&
          widget.initialActiveMode == ActivityMode.normal &&
          mode != _activeMode) {
        setState(() {
          _activeMode = mode;
        });
      }
    });

    _isBluetoothConnected = widget.initialBluetoothConnected &&
        PoiseBleService.instance.isConnected;
    _notificationPermissionGranted =
        widget.initialNotificationPermissionGranted;
    _vibrationEnabled = PoiseBleService.instance.isModeSynchronized
        ? PoiseBleService.instance.vibrationEnabled
        : (widget.initialVibrationEnabled ?? FeedbackPreferences.vibration);
    _phoneNotificationEnabled = widget.initialPhoneNotificationEnabled ??
        FeedbackPreferences.phoneNotification;

    _notifications.onNoticeAdded = _dispatchLocalNotification;
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerHistory());
  }

  Future<void> _offerHistory() async {
    if (!mounted || _historyDialogOpen) return;
    final ble = PoiseBleService.instance;
    if (ble.isConnected &&
        ble.pendingEventCount > 0 &&
        _promptedConnection != ble.connectionGeneration &&
        !ble.importAuthorized) {
      final generation = ble.connectionGeneration;
      _promptedConnection = generation;
      _historyDialogOpen = true;
      final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Import stored posture history?'),
                  content: Text(
                      'P.O.I.S.E. has ${ble.pendingEventCount} saved posture events. Importing copies them into local history on this phone. You can import now or later.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Later')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Import'))
                  ]));
      _historyDialogOpen = false;
      if (approved == true &&
          ble.connectionGeneration == generation &&
          ble.isConnected) {
        await ble.importStoredEvents();
        if (mounted && ble.importError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(ble.importError!)));
        }
      }
    }
    final user = SocialAuth.instance.user;
    if (!mounted || _cloudHistoryChecked || user == null) return;
    _cloudHistoryChecked = true;
    try {
      final rows = await PoiseLocalDatabase.instance.getDeviceEvents();
      if (!mounted || !rows.any((row) => row['owner_id'] == null)) {
        _cloudHistoryChecked = false;
        return;
      }
      _historyDialogOpen = true;
      final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Sync local posture history?'),
                  content: const Text(
                      'Link imported history on this phone to your account and upload it to Supabase? Local copies stay available if upload fails.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Later')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sync history'))
                  ]));
      if (approved == true && SocialAuth.instance.user?.id == user.id) {
        await SyncService.instance.approveDeviceHistory(user.id);
        await SyncService.instance.syncToCloud();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Local history: $error')));
      }
    } finally {
      _historyDialogOpen = false;
    }
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
    PoiseBleService.instance.protocolChanges.removeListener(_protocolChanged);
    _connectionSubscription?.cancel();
    _modeSubscription?.cancel();
    _modeSyncSubscription?.cancel();
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
        _phoneNotificationEnabled = false;
        FeedbackPreferences.savePhoneNotification(false);
      }
    });
  }

  void _protocolChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerHistory());
    setState(() {
      _activeMode = PoiseBleService.instance.phoneSavedMode;
      _vibrationEnabled = PoiseBleService.instance.vibrationEnabled;
      _isBluetoothConnected = PoiseBleService.instance.isConnected;
    });
  }

  Future<void> _handleVibrationChanged(bool enabled) async {
    final accepted =
        await PoiseBleService.instance.sendVibrationCommand(enabled);
    if (!mounted || !accepted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(enabled
            ? 'Device vibration feedback enabled.'
            : 'Device vibration feedback disabled.')));
  }

  void _handlePhoneNotificationChanged(bool enabled) {
    if (enabled && !_notificationPermissionGranted) {
      _handleNotificationPermissionChanged(true);
      return;
    }
    setState(() {
      _phoneNotificationEnabled = enabled;
    });
    FeedbackPreferences.savePhoneNotification(enabled);
  }

  List<Widget> _buildTabs() {
    final activeMode = _activeMode;
    final profile = SocialAuth.instance.user;
    return [
      DashboardTab(
        activeMode: activeMode,
        isBluetoothConnected: _isBluetoothConnected,
        onBluetoothChanged: _handleBluetoothChanged,
        bluetoothSearchDuration: widget.bluetoothSearchDuration,
        triggerRecalibration: _triggerRecalibration,
        onRecalibrationHandled: () {
          setState(() => _triggerRecalibration = false);
        },
        onBaselineSet: () => setState(() => _currentIndex = 0),
      ),
      const AnalyticsTab(),
      ControlsTab(
        selectedMode: activeMode,
        isBluetoothConnected: _isBluetoothConnected,
        onModeChanged: (mode) {
          PoiseBleService.instance.sendModeCommand(mode);
        },
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
            FeedbackPreferences.savePhoneNotification(true);
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
      onTap: () {
        ScaffoldMessenger.of(context).clearSnackBars();
        setState(() => _currentIndex = index);
        if (index == 1) {
          PoiseLocalDatabase.instance.notifyDatabaseChanged();
        }
      },
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
                    if (widget.requiresAccount && _currentIndex != 1)
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
