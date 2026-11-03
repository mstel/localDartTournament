import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/tournament_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows tournament type and completed winner name', (
    tester,
  ) async {
    const anna = TournamentPlayer(name: 'Anna', isGenerated: false);
    const ben = TournamentPlayer(name: 'Ben', isGenerated: false);
    final tournament = CreatedTournament(
      name: 'Finale',
      players: const [anna, ben],
      stages: const [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'K.-o.',
          rounds: [
            [
              GroupMatch(
                homePlayer: anna,
                awayPlayer: ben,
                round: 1,
                homeLegs: 3,
                awayLegs: 1,
              ),
            ],
          ],
        ),
      ],
      countsForRanking: true,
      completedStageIndexes: {0},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSummaryCard(
            tournament: tournament,
            onOpen: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('Ranglistenturnier'), findsOneWidget);
    expect(find.text('Sieger: Anna'), findsOneWidget);
  });

  testWidgets('shows the winning team for a completed league match', (
    tester,
  ) async {
    final league = LeagueMatch(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: const ['Heim 1'],
      awayPlayers: const ['Gast 1'],
      games: [
        LeagueGame(home: [0], away: [0], homeLegs: 3, awayLegs: 1),
      ],
    );
    final tournament = CreatedTournament(
      name: 'Ligaspiel',
      players: const [
        TournamentPlayer(name: 'Heim 1', isGenerated: false),
        TournamentPlayer(name: 'Gast 1', isGenerated: false),
      ],
      stages: const [],
      runStages: const [],
      leagueMatch: league,
      finishedAt: DateTime.utc(2026, 11, 3),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSummaryCard(
            tournament: tournament,
            onOpen: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('Ligaspiel'), findsWidgets);
    expect(find.text('Sieger: Heim'), findsOneWidget);
  });

  testWidgets('labels adjusted friendship tournaments', (tester) async {
    final tournament = CreatedTournament(
      name: 'Freundschaftsspiel',
      players: const [],
      stages: const [],
      runStages: const [],
      leagueMatch: LeagueMatch.adjusted(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: const ['Heim 1'],
        awayPlayers: const ['Gast 1'],
        singlesPerPlayer: 1,
        doublesCount: 0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSummaryCard(
            tournament: tournament,
            onOpen: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('Angepasstes/Freundschaftsspiel'), findsOneWidget);
  });
}
