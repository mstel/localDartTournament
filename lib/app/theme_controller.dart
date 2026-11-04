import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeStyle { club, christmas }

/// Manages and persists the app's ThemeMode (system, light, dark).
class AppThemeController {
  AppThemeController._();
  static final AppThemeController instance = AppThemeController._();

  static const _prefKey = 'app_theme_mode';
  static const _stylePrefKey = 'app_theme_style';
  static const _logoPrefKey = 'app_brand_logo';
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );
  final ValueNotifier<Uint8List?> logoBytesNotifier = ValueNotifier<Uint8List?>(
    null,
  );
  final ValueNotifier<AppThemeStyle> themeStyleNotifier =
      ValueNotifier<AppThemeStyle>(AppThemeStyle.club);

  ThemeMode get themeMode => themeModeNotifier.value;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      final savedStyle = prefs.getString(_stylePrefKey);
      final logo = prefs.getString(_logoPrefKey);
      if (saved == 'dark') {
        themeModeNotifier.value = ThemeMode.dark;
      } else if (saved == 'light') {
        themeModeNotifier.value = ThemeMode.light;
      } else {
        themeModeNotifier.value = ThemeMode.system;
      }
      themeStyleNotifier.value = savedStyle == 'christmas'
          ? AppThemeStyle.christmas
          : AppThemeStyle.club;
      if (logo != null) logoBytesNotifier.value = base64Decode(logo);
    } catch (_) {}
  }

  Future<void> setBrandLogo(Uint8List? bytes) async {
    if (bytes != null && bytes.lengthInBytes > 512 * 1024) {
      throw ArgumentError('Das Logo darf höchstens 512 KB groß sein.');
    }
    final prefs = await SharedPreferences.getInstance();
    if (bytes == null) {
      await prefs.remove(_logoPrefKey);
    } else {
      await prefs.setString(_logoPrefKey, base64Encode(bytes));
    }
    logoBytesNotifier.value = bytes;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mode == ThemeMode.dark) {
        await prefs.setString(_prefKey, 'dark');
      } else if (mode == ThemeMode.light) {
        await prefs.setString(_prefKey, 'light');
      } else {
        await prefs.remove(_prefKey);
      }
    } catch (_) {}
  }

  Future<void> setThemeStyle(AppThemeStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    if (style == AppThemeStyle.christmas) {
      await prefs.setString(_stylePrefKey, 'christmas');
    } else {
      await prefs.remove(_stylePrefKey);
    }
    themeStyleNotifier.value = style;
  }
}
