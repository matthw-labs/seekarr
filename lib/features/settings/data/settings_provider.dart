import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seekarr/features/settings/data/settings_service.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize this in main.dart');
});

final secureSettingsStoreProvider = Provider<SecureSettingsStore>((ref) {
  return createSecureSettingsStore();
});

final initialSettingsProvider = Provider<SettingsModel>((ref) {
  throw UnimplementedError('Initialize this in main.dart');
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final secureStore = ref.watch(secureSettingsStoreProvider);
  return SettingsService(prefs, secureStore);
});

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsModel>(
  SettingsNotifier.new,
);

final currentSettingsProvider = Provider<SettingsModel>((ref) {
  return ref.watch(settingsProvider);
});

final regionProvider = Provider<String>((ref) {
  return ref.watch(currentSettingsProvider).region;
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(currentSettingsProvider).resolvedThemeMode;
});

class SettingsNotifier extends Notifier<SettingsModel> {
  late final SettingsService _service;

  @override
  SettingsModel build() {
    _service = ref.watch(settingsServiceProvider);
    return ref.watch(initialSettingsProvider);
  }

  Future<void> updateSettings(SettingsModel newSettings) async {
    await _service.saveSettings(newSettings);
    state = newSettings;
  }

  Future<void> resetSettings() async {
    await _service.clearAll();
    state = const SettingsModel();
  }
}
