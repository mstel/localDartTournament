import 'package:dart_tournament_manager/features/settings/presentation/priority_notice_settings_panel.dart';
import 'package:dart_tournament_manager/features/settings/presentation/tie_breaker_defaults_panel.dart';
import 'package:dart_tournament_manager/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('administration settings expand inline', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.tap(find.byType(ChoiceChip).last);
    await tester.pumpAndSettle();
    expect(find.text('Sonstige Einstellungen'), findsNWidgets(2));

    await tester.scrollUntilVisible(
      find.text('Tie Breaker Standardwerte'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Tie Breaker Standardwerte'));
    await tester.pumpAndSettle();
    expect(find.text('Tie Breaker Standardwerte'), findsOneWidget);
    expect(find.textContaining('Diese Reihenfolge wird'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Hinweiseinstellungen'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Hinweiseinstellungen'));
    await tester.pumpAndSettle();
    expect(
      find.text('Prioritätshinweis pro Spieler ab Verzug von'),
      findsOneWidget,
    );
    expect(find.text('Prozentuale Berechnung verwenden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: PriorityNoticeSettingsPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hinweiseinstellungen'), findsOneWidget);
      await tester.tap(find.text('Hinweiseinstellungen'));
      await tester.pumpAndSettle();
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
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: TieBreakerDefaultsPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tie Breaker Standardwerte'), findsOneWidget);
      await tester.tap(find.text('Tie Breaker Standardwerte'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Diese Reihenfolge wird'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
