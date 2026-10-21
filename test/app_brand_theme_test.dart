import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/app/theme_controller.dart';
import 'package:dart_tournament_manager/shared/widgets/app_brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand mark uses fallback icon and accepts transparent logos', (
    tester,
  ) async {
    final logoNotifier = AppThemeController.instance.logoBytesNotifier;
    addTearDown(() => logoNotifier.value = null);

    const brandColor = Color(0xffa75e12);
    logoNotifier.value = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.light(primary: brandColor)),
        home: const Scaffold(body: AppBrandMark(size: 40)),
      ),
    );
    expect(find.byIcon(Icons.sports_score), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.sports_score)).color,
      brandColor,
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
