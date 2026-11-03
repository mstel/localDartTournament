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
    },
  );
}
