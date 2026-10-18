import 'package:shared_preferences/shared_preferences.dart';
import 'activity_mode.dart';
import 'database/models.dart';

/// Manages local persistent storage on the phone for the user's selected posture mode preference.
///
/// Under Rev 9 firmware specifications:
/// - Defaults to Normal (ID 1) on first launch.
/// - Persists across app restarts, disconnects, and reconnects.
/// - Is never overwritten when the hardware disconnects and reverts to its default fallback mode (Normal).
class ModePreferences {
  static const String key = 'poise.mode';
  static ActivityMode savedMode = ActivityMode.normal;
  static SharedPreferences? _preferences;

  /// Loads the saved mode from local persistent storage on the phone.
  /// Defaults to ActivityMode.normal on first launch when no mode preference has been saved.
  static Future<ActivityMode> load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final modeId = _preferences?.getInt(key);
      if (modeId != null) {
        savedMode = ModeModel.activityModeFromId(modeId);
      } else {
        final modeStr = _preferences?.getString(key);
        if (modeStr != null) {
          final id = int.tryParse(modeStr);
          if (id != null) {
            savedMode = ModeModel.activityModeFromId(id);
          }
        } else {
          savedMode = ActivityMode.normal;
        }
      }
    } catch (_) {
      savedMode = ActivityMode.normal;
    }
    return savedMode;
  }

  /// Returns the cached saved mode, or loads it if not yet loaded.
  static Future<ActivityMode> getSavedMode() async {
    if (_preferences == null) {
      return await load();
    }
    final modeId = _preferences?.getInt(key);
    if (modeId != null) {
      savedMode = ModeModel.activityModeFromId(modeId);
    }
    return savedMode;
  }

  /// Saves the user's selected mode preference to local storage on the phone.
  /// Never overwritten merely because the hardware changes active mode or disconnects.
  static Future<void> saveMode(ActivityMode mode) async {
    savedMode = mode;
    try {
      _preferences ??= await SharedPreferences.getInstance();
      await _preferences?.setInt(key, ModeModel.idForActivityMode(mode));
    } catch (_) {}
  }

  /// Resets cached mode for testing
  static void resetForTesting() {
    savedMode = ActivityMode.normal;
    _preferences = null;
  }
}
