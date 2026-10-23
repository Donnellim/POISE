import 'package:shared_preferences/shared_preferences.dart';

/// A local preference only; manages independent feedback routing preferences.
class FeedbackPreferences {
  static bool vibration = true;
  static bool phoneNotification = false;
  static bool hasExplicitVibrationPreference = false;
  static SharedPreferences? _preferences;

  static Future<void> load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      hasExplicitVibrationPreference =
          _preferences?.containsKey('poise.vibration') ?? false;
      vibration = _preferences?.getBool('poise.vibration') ?? true;
      phoneNotification =
          _preferences?.getBool('poise.phoneNotification') ?? false;
    } catch (_) {
      // Storage unavailable: retain safe defaults for this session.
    }
  }

  static Future<void> save(bool value) async {
    await saveVibration(value);
  }

  static Future<void> saveVibration(bool value) async {
    vibration = value;
    hasExplicitVibrationPreference = true;
    try {
      await _preferences?.setBool('poise.vibration', value);
    } catch (_) {}
  }

  static Future<void> savePhoneNotification(bool value) async {
    phoneNotification = value;
    try {
      await _preferences?.setBool('poise.phoneNotification', value);
    } catch (_) {}
  }
}
