import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/dio_client.dart';

const _kDarkModeKey = 'dark_mode';

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final Ref _ref;

  ThemeModeNotifier(this._ref) : super(ThemeMode.light) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final raw =
          await _ref.read(secureStorageProvider).read(key: _kDarkModeKey);
      if (raw != null) {
        state = raw == 'true' ? ThemeMode.dark : ThemeMode.light;
      }
    } catch (_) {
      // Keep light theme default if secure storage read fails
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    try {
      await _ref
          .read(secureStorageProvider)
          .write(key: _kDarkModeKey, value: isDark.toString());
    } catch (_) {
      // Ignore storage write failure; in-memory state is already updated
    }
  }
}
