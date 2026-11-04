import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/app/theme_controller.dart';
import 'package:dart_tournament_manager/app/christmas_decorations.dart';
import 'package:dart_tournament_manager/shared/widgets/app_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('brand mark uses golden fallback and accepts transparent logos', (
    tester,
  ) async {
    final logoNotifier = AppThemeController.instance.logoBytesNotifier;
    addTearDown(() => logoNotifier.value = null);

    logoNotifier.value = null;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppBrandMark(size: 40))),
    );
    final fallback = tester.widget<Image>(find.byType(Image).first);
    expect(
      (fallback.image as AssetImage).assetName,
      'assets/images/app_brand_mark.png',
    );

    logoNotifier.value = await tester.runAsync(_transparentPixelPng);
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('light and dark snackbars have accessible text contrast', () {
    for (final theme in [
      buildDartTournamentTheme(),
      buildDartTournamentDarkTheme(),
    ]) {
      final snackBar = theme.snackBarTheme;
      final background = snackBar.backgroundColor!;
      final foreground = snackBar.contentTextStyle!.color!;
      expect(_contrastRatio(foreground, background), greaterThanOrEqualTo(4.5));
      expect(
        _contrastRatio(snackBar.actionTextColor!, background),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test(
    'blue and Christmas theme styles persist independently of brightness',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = AppThemeController.instance;
      await controller.setThemeStyle(AppThemeStyle.christmas);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_theme_style'), 'christmas');
      expect(controller.themeStyleNotifier.value, AppThemeStyle.christmas);
      expect(
        buildDartTournamentDarkTheme(christmas: true).colorScheme.primary,
        const Color(0xFFF0808B),
      );
      expect(
        buildDartTournamentDarkTheme().colorScheme.primary,
        const Color(0xFF70C4E8),
      );

      await controller.setThemeStyle(AppThemeStyle.club);
      expect(preferences.getString('app_theme_style'), isNull);
      expect(controller.themeStyleNotifier.value, AppThemeStyle.club);
    },
  );

  testWidgets(
    'Christmas decorations show a Santa and allow the app to render',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChristmasDecorations(child: Scaffold(body: Text('Inhalt'))),
        ),
      );

      expect(find.text('🎅'), findsOneWidget);
      expect(find.text('Inhalt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Future<Uint8List> _transparentPixelPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0x00000000), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
