import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/app/theme_controller.dart';
import 'package:dart_tournament_manager/app/christmas_decorations.dart';
import 'package:dart_tournament_manager/features/settings/presentation/appearance_panel.dart';
import 'package:dart_tournament_manager/shared/theme/tournament_display_palette.dart';
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

  test('club action labels contrast with the restored gold accent', () {
    final theme = buildDartTournamentTheme();
    expect(
      _contrastRatio(theme.colorScheme.onPrimary, theme.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('light filled buttons use a white surface with gold labels', () {
    final light = buildDartTournamentTheme();
    final dark = buildDartTournamentDarkTheme();

    final lightStyle = light.filledButtonTheme.style!;
    expect(
      lightStyle.backgroundColor!.resolve(const <WidgetState>{}),
      light.colorScheme.surface,
    );
    expect(
      lightStyle.foregroundColor!.resolve(const <WidgetState>{}),
      light.colorScheme.primary,
    );

    // Dark design keeps the regular filled-button appearance.
    expect(dark.filledButtonTheme.style!.backgroundColor, isNull);
    expect(dark.filledButtonTheme.style!.foregroundColor, isNull);
  });

  test('Christmas filled buttons use fir green with white labels', () {
    for (final theme in [
      buildDartTournamentTheme(christmas: true),
      buildDartTournamentDarkTheme(christmas: true),
    ]) {
      final style = theme.filledButtonTheme.style!;
      final background = style.backgroundColor!.resolve(const <WidgetState>{});
      final foreground = style.foregroundColor!.resolve(const <WidgetState>{});

      expect(background, theme.colorScheme.primary);
      expect(foreground, theme.colorScheme.onPrimary);
      expect(
        _contrastRatio(foreground!, background!),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('Christmas filled icon buttons use fir green with white icons', (
    tester,
  ) async {
    for (final theme in [
      buildDartTournamentTheme(christmas: true),
      buildDartTournamentDarkTheme(christmas: true),
    ]) {
      ButtonStyle? style;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Theme(
              data: theme,
              child: Builder(
                builder: (context) {
                  style = filledIconButtonStyle(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      expect(style, isNotNull);
      final background = style!.backgroundColor!.resolve(const <WidgetState>{});
      final foreground = style!.foregroundColor!.resolve(const <WidgetState>{});
      expect(background, theme.colorScheme.primary);
      expect(foreground, theme.colorScheme.onPrimary);
      expect(
        _contrastRatio(foreground!, background!),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('club filled icon buttons keep their existing appearance', (
    tester,
  ) async {
    final light = buildDartTournamentTheme();
    final dark = buildDartTournamentDarkTheme();

    ButtonStyle? lightStyle;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Theme(
            data: light,
            child: Builder(
              builder: (context) {
                lightStyle = filledIconButtonStyle(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(
      lightStyle!.backgroundColor!.resolve(const <WidgetState>{}),
      light.colorScheme.surface,
    );
    expect(
      lightStyle!.foregroundColor!.resolve(const <WidgetState>{}),
      light.colorScheme.primary,
    );

    ButtonStyle? darkStyle;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Theme(
            data: dark,
            child: Builder(
              builder: (context) {
                darkStyle = filledIconButtonStyle(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(darkStyle, isNull);
  });

  testWidgets('Christmas second screen uses dark text in light app design', (
    tester,
  ) async {
    ThemeData? wrappedTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDartTournamentTheme(christmas: true),
        home: Scaffold(
          body: ChristmasDecorations(
            child: Builder(
              builder: (context) {
                wrappedTheme = Theme.of(context);
                return const Text('probe');
              },
            ),
          ),
        ),
      ),
    );

    expect(wrappedTheme, isNotNull);
    expect(wrappedTheme!.brightness, Brightness.dark);
    expect(
      wrappedTheme!.colorScheme.onSurface,
      buildDartTournamentDarkTheme(christmas: true).colorScheme.onSurface,
    );
    expect(tester.takeException(), isNull);
  });

  test('run surfaces keep the dark blue palette in dark mode', () {
    final lightScheme = buildDartTournamentTheme().colorScheme;
    final darkScheme = buildDartTournamentDarkTheme().colorScheme;
    final lightPalette = TournamentDisplayPalette.forColorScheme(lightScheme);
    final darkPalette = TournamentDisplayPalette.forColorScheme(darkScheme);

    expect(lightPalette.card, lightScheme.surfaceContainer);
    expect(lightPalette.cardEmphasis, lightScheme.surfaceContainerHigh);
    expect(darkPalette.card, TournamentDisplayPalette.card);
    expect(darkPalette.cardEmphasis, TournamentDisplayPalette.cardEmphasis);
    expect(darkPalette.border, TournamentDisplayPalette.border);
    expect(darkPalette.accent, TournamentDisplayPalette.accent);
    expect(darkPalette.card, isNot(darkScheme.surfaceContainer));
  });

  test(
    'club and Christmas theme styles persist independently of brightness',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = AppThemeController.instance;
      await controller.setThemeStyle(AppThemeStyle.christmas);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_theme_style'), 'christmas');
      expect(controller.themeStyleNotifier.value, AppThemeStyle.christmas);
      expect(
        buildDartTournamentDarkTheme(christmas: true).colorScheme.primary,
        const Color(0xFF183D32),
      );
      expect(
        buildDartTournamentTheme(christmas: true).colorScheme.primary,
        const Color(0xFF183D32),
      );
      expect(
        buildDartTournamentDarkTheme().colorScheme.primary,
        const Color(0xFFD49B44),
      );
      expect(
        buildDartTournamentTheme().colorScheme.primary,
        const Color(0xFFB5811E),
      );
      expect(
        buildDartTournamentDarkTheme(christmas: true).colorScheme.tertiary,
        const Color(0xFF72D58D),
      );

      await controller.setThemeStyle(AppThemeStyle.club);
      expect(preferences.getString('app_theme_style'), isNull);
      expect(controller.themeStyleNotifier.value, AppThemeStyle.club);
    },
  );

  testWidgets('appearance panel uses the short Christmas scheme label', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppearancePanel())),
    );

    await tester.tap(find.byType(DropdownButtonFormField<AppThemeStyle>));
    await tester.pumpAndSettle();

    expect(find.text('Weihnachten'), findsOneWidget);
    expect(find.textContaining('Schnee, Lichter'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Christmas winter background is limited to the Christmas style', (
    tester,
  ) async {
    final styleNotifier = AppThemeController.instance.themeStyleNotifier;
    addTearDown(() => styleNotifier.value = AppThemeStyle.club);
    styleNotifier.value = AppThemeStyle.club;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChristmasSecondScreenBackground(child: Text('Inhalt')),
        ),
      ),
    );

    expect(find.byType(ChristmasDecorations), findsNothing);
    expect(find.text('Inhalt'), findsOneWidget);
    expect(tester.takeException(), isNull);

    styleNotifier.value = AppThemeStyle.christmas;
    await tester.pump();

    expect(find.byType(ChristmasDecorations), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChristmasDecorations),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    final imageAssets = tester
        .widgetList<Image>(
          find.descendant(
            of: find.byType(ChristmasDecorations),
            matching: find.byType(Image),
          ),
        )
        .map((image) => (image.image as AssetImage).assetName)
        .toSet();
    expect(imageAssets, {'assets/images/christmas_theme.png'});
    expect(find.byKey(const ValueKey('christmas-snowfall')), findsOneWidget);
    expect(find.text('🎅'), findsNothing);
    expect(find.text('Inhalt'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
