import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/recent_match_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'recent match shows achievement notice with explanation tooltip',
    (tester) async {
      final home = TournamentPlayer(
        profileId: 'player-1',
        name: 'Alex',
        isGenerated: false,
      );
      final away = TournamentPlayer(
        profileId: 'player-2',
        name: 'Sam',
        isGenerated: false,
      );
      final match = GroupMatch(
        homePlayer: home,
        awayPlayer: away,
        round: 1,
        homeLegs: 3,
        awayLegs: 1,
        achievementNotifications: const [
          TournamentAchievementNotice(
            playerProfileId: 'player-1',
            playerName: 'Alex',
            achievementName: 'Maximum',
            explanation: 'Du hast eine 180 geworfen.',
            rankingName: 'Saison 2026',
          ),
        ],
      );
      final tournament = CreatedTournament(
        name: 'Test',
        players: [home, away],
        stages: const [],
        runStages: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentMatchResultLogEntry(
              tournament: tournament,
              match: match,
              eloChanges: const [],
            ),
          ),
        ),
      );

      expect(
        find.text('Alex hat „Maximum“ erzielt! · Saison 2026'),
        findsOneWidget,
      );
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Du hast eine 180 geworfen.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled tournament notices hide achievement text only', (
    tester,
  ) async {
    final player = TournamentPlayer(
      profileId: 'player-1',
      name: 'Alex',
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      name: 'Test',
      players: [player],
      stages: const [],
      runStages: const [],
    )..showAchievementNotifications = false;
    final match = GroupMatch(
      round: 1,
      achievementNotifications: const [
        TournamentAchievementNotice(
          playerProfileId: 'player-1',
          playerName: 'Alex',
          achievementName: 'Maximum',
          explanation: 'Du hast eine 180 geworfen.',
          rankingName: 'Saison 2026',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentMatchResultLogEntry(
            tournament: tournament,
            match: match,
            eloChanges: const [],
          ),
        ),
      ),
    );

    expect(find.textContaining('Maximum'), findsNothing);
    expect(match.achievementNotifications, hasLength(1));
  });
}
