import 'package:flutter/material.dart';
import 'bluetooth/poise_ble_service.dart';
import 'calibration_page.dart';
import 'dashboard_page.dart';
import 'device_check_page.dart';
import 'device_session.dart';
import 'auth/social_auth.dart';
import 'sign_in_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionEntryPage extends StatefulWidget {
  const SessionEntryPage({super.key});

  @override
  State<SessionEntryPage> createState() => _SessionEntryPageState();
}

class _SessionEntryPageState extends State<SessionEntryPage> {
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    // If returning from OAuth on web with an error, show it on SignInPage:
    if (SocialAuth.hasOAuthError) {
      final error = SocialAuth.oAuthErrorDescription ?? 'Sign-in failed.';
      SocialAuth.instance.lastError.value = error;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const SignInPage(),
      ));
      return;
    }

    // If returning from OAuth on web and auth is still resolving, wait briefly:
    if (SocialAuth.isOAuthRedirect && SocialAuth.instance.user == null) {
      try {
        await SocialAuth.instance.incomingSignIns.first
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    final ble = PoiseBleService.instance;
    final adapterOn = await ble.isBluetoothAdapterOn();
    final resume = await DeviceSession.shouldResume(adapterOn: adapterOn);
    await DeviceSession.signedIn();
    if (resume && adapterOn) {
      await ble.restoreConnection();
    }

    final prefs = await SharedPreferences.getInstance();
    final bool bluetoothEnabled =
        prefs.getBool('poise.bluetoothEnabled') ?? true;

    // Check if device is connected / synced via Quick Settings or system Bluetooth
    final isQuickSettingsSynced = adapterOn &&
        bluetoothEnabled &&
        await ble.checkAndConnectSystemDevice();

    if (!mounted) return;

    if (resume) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => DashboardPage(
          initialBluetoothConnected: ble.isConnected,
          initialNotificationPermissionGranted:
              prefs.getBool('poise.notificationPermission') ?? false,
        ),
      ));
    } else if (isQuickSettingsSynced) {
      // User connected via Quick Settings panel outside the app without in-app device check.
      // Auto-detected and synced -> Go directly to CalibrationPage.
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const CalibrationPage(isGuest: false),
      ));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const DeviceCheckPage(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
