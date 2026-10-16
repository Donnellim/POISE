import 'package:shared_preferences/shared_preferences.dart';

/// Device setup survives app restarts and transient Bluetooth interruptions,
/// but must be re-verified if Bluetooth is turned off before logging out.
class DeviceSession {
  static Future<bool> shouldResume({required bool adapterOn}) async {
    final prefs = await SharedPreferences.getInstance();
    final bool bluetoothEnabled =
        prefs.getBool('poise.bluetoothEnabled') ?? true;
    if ((!adapterOn || !bluetoothEnabled) &&
        (prefs.getBool('poise.loggedOut') ?? false)) {
      await prefs.setBool('poise.setupComplete', false);
      await prefs.remove('poise.deviceId');
      await prefs.remove('poise.deviceName');
      await prefs.remove('poise.baseline');
    }
    return prefs.getBool('poise.setupComplete') ?? false;
  }

  static Future<void> completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('poise.setupComplete', true);
    await prefs.setBool('poise.loggedOut', false);
    await prefs.setBool('poise.bluetoothEnabled', true);
  }

  static Future<void> signedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('poise.loggedOut', false);
  }

  static Future<void> signedOut({
    required bool adapterOn,
    bool? bluetoothEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('poise.loggedOut', true);
    final bool isBleActive = adapterOn &&
        (bluetoothEnabled ?? (prefs.getBool('poise.bluetoothEnabled') ?? true));
    if (!isBleActive) {
      await prefs.setBool('poise.setupComplete', false);
      await prefs.setBool('poise.bluetoothEnabled', false);
      await prefs.remove('poise.deviceId');
      await prefs.remove('poise.deviceName');
      await prefs.remove('poise.baseline');
    }
  }
}
