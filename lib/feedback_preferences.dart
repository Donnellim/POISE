import 'package:shared_preferences/shared_preferences.dart';

/// A local preference only; no database or account data is stored here.
class FeedbackPreferences {
  static bool vibration = true;
  static SharedPreferences? _preferences;
  static Future<void> load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      vibration = _preferences?.getBool('poise.vibration') ?? true;
    } catch (_) {
      // Storage unavailable: retain the safe vibration default for this session.
    }
  }

  static Future<void> save(bool value) async {
    vibration = value;
    try {
      await _preferences?.setBool('poise.vibration', value);
    } catch (_) {
      // The selection still applies to the current session.
    }
  }
}
