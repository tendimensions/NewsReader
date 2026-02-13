import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../repositories/settings_repository.dart';
import 'repositories_provider.dart';

/// Provides the current ThemeMode based on user preference
final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return ThemeNotifier(repo);
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  final SettingsRepository _repo;

  ThemeNotifier(SettingsRepository repo)
      : _repo = repo,
        super(_toThemeMode(repo.settings.themePreference));

  static ThemeMode _toThemeMode(ThemePreference pref) {
    switch (pref) {
      case ThemePreference.system:
        return ThemeMode.system;
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  Future<void> setTheme(ThemePreference pref) async {
    await _repo.setThemePreference(pref);
    state = _toThemeMode(pref);
  }

  ThemePreference get currentPreference => _repo.settings.themePreference;
}
