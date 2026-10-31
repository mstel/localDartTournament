import 'package:dart_tournament_manager/features/settings/presentation/priority_notice_settings_panel.dart';
import 'package:dart_tournament_manager/features/settings/presentation/tie_breaker_defaults_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('hint settings fit $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: PriorityNoticeSettingsPanel()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hinweiseinstellungen'), findsOneWidget);
      expect(
        find.text('Prioritätshinweis pro Spieler ab Verzug von'),
        findsOneWidget,
      );
      expect(
        find.text('Prioritätshinweis pro Gruppe ab Verzug von'),
        findsOneWidget,
      );
      expect(find.text('Prozentuale Berechnung verwenden'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tie-breaker defaults fit $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: TieBreakerDefaultsPanel()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tie Breaker Standardwerte'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
