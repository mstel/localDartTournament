import 'package:dart_tournament_manager/features/achievements/domain/achievement_definition.dart';
import 'package:dart_tournament_manager/features/achievements/domain/achievement_engine.dart';
import 'package:dart_tournament_manager/features/achievements/presentation/ranking_achievement_section.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'achievement summary lays out on narrow, tablet and desktop widths',
    (tester) async {
      const sizes = [Size(360, 800), Size(800, 600), Size(1440, 900)];
      final evaluation = const AchievementEngine().evaluate(
        values: const {},
        rankingCompleted: false,
      );
      final view = RankingAchievementView(
        ranking: const LocalRanking(
          id: 'ranking',
          name: 'Saison 2026',
          achievementsEnabled: true,
        ),
        playerProfileId: 'player',
        evaluation: evaluation,
      );

      for (final size in sizes) {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RankingAchievementSection(achievements: [view]),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Saison 2026'), findsOneWidget);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('achievement menu supports 200 percent text scaling', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    final evaluation = const AchievementEngine().evaluate(
      values: const {},
      rankingCompleted: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RankingAchievementSection(
              achievements: [
                RankingAchievementView(
                  ranking: const LocalRanking(
                    id: 'ranking',
                    name: 'Saison 2026',
                    achievementsEnabled: true,
                  ),
                  playerProfileId: 'player',
                  evaluation: evaluation,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Errungenschaften anzeigen'));
    await tester.tap(find.text('Errungenschaften anzeigen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Turniererfolge'));
    await tester.tap(find.text('Turniererfolge'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Turnierluft geschnuppert I'), findsOneWidget);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('achievement menu filters categories and shows progress tiles', (
    tester,
  ) async {
    final evaluation = const AchievementEngine().evaluate(
      values: const {AchievementMetric.score180Count: 3},
      rankingCompleted: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RankingAchievementSection(
            achievements: [
              RankingAchievementView(
                ranking: const LocalRanking(
                  id: 'ranking',
                  name: 'Saison 2026',
                  achievementsEnabled: true,
                ),
                playerProfileId: 'player',
                evaluation: evaluation,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Errungenschaften anzeigen'));
    await tester.tap(find.text('Errungenschaften anzeigen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(DropdownButtonFormField<AchievementCategory?>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scoring & Specials').last);
    await tester.pumpAndSettle();

    expect(find.text('Turniererfolge'), findsNothing);
    await tester.tap(find.text('Scoring & Specials').last);
    await tester.pumpAndSettle();
    expect(find.text('Maximum I'), findsOneWidget);
    expect(find.textContaining('3 / 3'), findsOneWidget);
    expect(find.textContaining('Nächste Stufe:'), findsNothing);
  });

  testWidgets('ranking awards category is summarized as one possible award', (
    tester,
  ) async {
    final evaluation = const AchievementEngine().evaluate(
      values: const {AchievementMetric.rankingGold: 1},
      rankingCompleted: true,
    );
    final view = RankingAchievementView(
      ranking: const LocalRanking(
        id: 'ranking',
        name: 'Saison 2026',
        achievementsEnabled: true,
      ),
      playerProfileId: 'player',
      evaluation: evaluation,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RankingAchievementSection(achievements: [view])),
      ),
    );
    await tester.ensureVisible(find.text('Errungenschaften anzeigen'));
    await tester.tap(find.text('Errungenschaften anzeigen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ranglisten-Achievements'));
    await tester.tap(find.text('Ranglisten-Achievements'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 1 abgeschlossen'), findsOneWidget);
  });
}
