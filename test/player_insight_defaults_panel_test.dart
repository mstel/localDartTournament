import 'package:dart_tournament_manager/features/settings/presentation/player_insight_defaults_panel.dart';
import 'package:dart_tournament_manager/features/tournaments/application/player_insight_preferences.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/player_insight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'insight preferences default to all enabled and persist changes',
    () async {
      final storage = PlayerInsightPreferencesStorage();
      final initial = await storage.load();
      expect(initial.enabledTypes, PlayerInsightType.values.toSet());

      await storage.save(
        initial.withEnabled(PlayerInsightType.unstoppable, false),
      );

      final loaded = await storage.load();
      expect(loaded.isEnabled(PlayerInsightType.unstoppable), isFalse);
      expect(loaded.isEnabled(PlayerInsightType.hotStreak), isTrue);
      expect(PlayerInsightType.momentum.hasThreshold, isFalse);
      expect(initial.thresholds.containsKey(PlayerInsightType.momentum), isFalse);
    },
  );

  testWidgets(
    'defaults are in a collapsed section with one switch per insight',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: const [PlayerInsightDefaultsPanel()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Insights Standardwerte'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);

      await tester.tap(find.text('Insights Standardwerte'));
      await tester.pumpAndSettle();

      expect(
        find.byType(SwitchListTile),
        findsNWidgets(PlayerInsightType.values.length),
      );
      expect(
        find.byKey(const ValueKey('insight-threshold-momentum')),
        findsNothing,
      );
      expect(
        find.textContaining('erste abgeschlossene Partie'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Elo thresholds accept hundreds in numeric fields', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: const [PlayerInsightDefaultsPanel()]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insights Standardwerte'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    final eloField = find.byKey(
      const ValueKey('insight-threshold-giantKiller'),
    );
    await tester.ensureVisible(eloField);
    await tester.enterText(eloField, '850');
    final saveButton = find.byKey(
      const ValueKey('save-insight-giantKiller'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(
      (await PlayerInsightPreferencesStorage().load())
          .thresholdFor(PlayerInsightType.giantKiller),
      850,
    );
    expect(find.textContaining('mindestens 850 ELO-Punkten mehr'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
