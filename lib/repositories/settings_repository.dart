import 'package:hive/hive.dart';
import '../models/app_settings.dart';

/// Manages app settings in Hive storage
class SettingsRepository {
  static const String _boxName = 'settings';
  static const String _settingsKey = 'app_settings';
  late Box<AppSettings> _box;

  Future<void> init() async {
    _box = await Hive.openBox<AppSettings>(_boxName);
    if (!_box.containsKey(_settingsKey)) {
      await _box.put(_settingsKey, AppSettings());
    }
  }

  AppSettings get settings =>
      _box.get(_settingsKey) ?? AppSettings();

  Future<void> setThemePreference(ThemePreference pref) async {
    final s = settings;
    s.themePreference = pref;
    await _box.put(_settingsKey, s);
  }
}
