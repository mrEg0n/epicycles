// User options persisted across app launches.

import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  static SharedPreferences? _p;

  /// Call once at startup. If storage is unavailable the app runs with default values.
  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      // Keep _p null: getters return defaults and setters do nothing.
    }
  }

  static bool flag(String key, bool or) => _p?.getBool(key) ?? or;
  static int integer(String key, int or) => _p?.getInt(key) ?? or;
  static double number(String key, double or) => _p?.getDouble(key) ?? or;
  static String? text(String key) => _p?.getString(key);

  static void setFlag(String key, bool v) => _p?.setBool(key, v);
  static void setInteger(String key, int v) => _p?.setInt(key, v);
  static void setNumber(String key, double v) => _p?.setDouble(key, v);
  static void setText(String key, String v) => _p?.setString(key, v);
}
