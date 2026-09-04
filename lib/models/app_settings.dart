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

  /// Push bookmarks to the mcp-vault server as well as storing them locally.
  /// Off until the user supplies a token — see [VaultTokenStore].
  ///
  /// `defaultValue` is required, not decorative: settings records written before
  /// these fields existed have no bytes for them, and without a default the
  /// generated adapter does `fields[1] as bool` on a null and throws. main.dart
  /// would then treat the box as corrupt and delete it, silently resetting the
  /// user's theme.
  @HiveField(1, defaultValue: false)
  bool vaultSyncEnabled;

  /// Streamable HTTP endpoint of the mcp-vault server.
  @HiveField(2, defaultValue: defaultVaultServerUrl)
  String vaultServerUrl;

  AppSettings({
    this.themePreference = ThemePreference.system,
    this.vaultSyncEnabled = false,
    this.vaultServerUrl = defaultVaultServerUrl,
  });

  static const String defaultVaultServerUrl = 'https://mcp.tendimensions.com/mcp';
}
