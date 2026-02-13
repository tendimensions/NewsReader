import 'package:hive/hive.dart';

part 'app_settings.g.dart';

/// Theme mode persisted in Hive
@HiveType(typeId: 2)
enum ThemePreference {
  @HiveField(0)
  system,

  @HiveField(1)
  light,

  @HiveField(2)
  dark,
}

/// App-wide settings stored in Hive
@HiveType(typeId: 3)
class AppSettings extends HiveObject {
  @HiveField(0)
  ThemePreference themePreference;

  AppSettings({
    this.themePreference = ThemePreference.system,
  });
}
