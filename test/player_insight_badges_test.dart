import 'package:dart_tournament_manager/features/tournaments/domain/player_insight.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/player_insight_badges.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/recommended_matches_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('badge keeps its name visible and explains itself in a tooltip', (
    tester,
  ) async {
    const insight = PlayerInsight(
      type: PlayerInsightType.hotStreak,
      playerId: 'player',
      explanation: 'Drei Siege in Folge.',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlayerInsightBadgeRow(insights: [insight])),
      ),
    );

    expect(find.text('Hot Streak'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Drei Siege in Folge.',
    );
  });

  test('match insights include only generic and matching-rival badges', () {
    final home = TournamentPlayer(
      profileId: 'home',
      name: 'Home',
      isGenerated: false,
    );
    final away = TournamentPlayer(
      profileId: 'away',
      name: 'Away',
      isGenerated: false,
    );
    final match = GroupMatch(homePlayer: home, awayPlayer: away, round: 1);
    const generic = PlayerInsight(
      type: PlayerInsightType.hotStreak,
      playerId: 'home',
      explanation: 'Streak.',
    );
    const matchingRival = PlayerInsight(
      type: PlayerInsightType.rival,
      playerId: 'home',
      rivalId: 'away',
      explanation: 'Direkte Duelle.',
    );
    const otherRival = PlayerInsight(
      type: PlayerInsightType.rival,
      playerId: 'home',
      rivalId: 'other',
      explanation: 'Andere direkte Duelle.',
    );

    final insights = insightsForMatch(match, {
      'home': [generic, matchingRival, otherRival],
    });

    expect(insights, [generic, matchingRival]);
  });

  testWidgets(
    'badges stay within a narrow second-screen layout at large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final home = TournamentPlayer(
        profileId: 'home',
        name: 'Spieler mit einem sehr langen Namen',
        isGenerated: false,
      );
      final away = TournamentPlayer(
        profileId: 'away',
        name: 'Ein weiterer langer Spielername',
        isGenerated: false,
      );
      final match = GroupMatch(homePlayer: home, awayPlayer: away, round: 1);
      const insight = PlayerInsight(
        type: PlayerInsightType.bogeyOpponent,
        playerId: 'home',
        rivalId: 'away',
        explanation: 'Sieben Niederlagen in zehn direkten Duellen.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: RecommendedMatchesTable(
                groups: [
                  RecommendedMatchGroup(name: 'Gruppe A', matches: [match]),
                ],
                prioritizedMatches: const {},
                dense: true,
                playerInsights: {
                  'home': [insight],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Angstgegner'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
