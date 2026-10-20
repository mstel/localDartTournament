import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/app/theme_controller.dart';

void main() {
  test('brand logos are persisted byte-for-byte with alpha intact', () async {
    SharedPreferences.setMockInitialValues({});
    final image = img.Image(width: 1, height: 1, numChannels: 4);
    image.setPixelRgba(0, 0, 120, 90, 60, 0);
    final bytes = Uint8List.fromList(img.encodePng(image));
    expect(img.decodePng(bytes)!.getPixel(0, 0).a, 0);

    await AppThemeController.instance.setBrandLogo(bytes);

    expect(AppThemeController.instance.logoBytesNotifier.value, bytes);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_brand_logo'), base64Encode(bytes));
    await AppThemeController.instance.setBrandLogo(null);
  });

  test('snackbar text uses high-contrast light foreground in both themes', () {
    for (final theme in [
      buildDartTournamentTheme(),
      buildDartTournamentDarkTheme(),
    ]) {
      expect(
        theme.snackBarTheme.contentTextStyle?.color,
        const Color(0xFFFFFFFF),
      );
      expect(
        theme.snackBarTheme.backgroundColor,
        isNot(theme.colorScheme.surface),
      );
      expect(
        _contrastRatio(
          theme.snackBarTheme.contentTextStyle!.color!,
          theme.snackBarTheme.backgroundColor!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(theme.colorScheme.primary, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
