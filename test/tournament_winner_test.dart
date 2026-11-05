import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_winner.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CreatedTournament completedKratzerTournament() {
    final players = [
      for (var index = 1; index <= 3; index++)
        TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
    ];
    final tournament = CreatedTournament(
      name: 'Kratzer',
      players: players,
      stages: const [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Kratzer',
          rounds: [
            [
              GroupMatch(
                isKratzer: true,
                players: players,
                scratchEligiblePlayers: players,
                scratchedPlayer: players[0],
                round: 1,
              ),
            ],
            [
              GroupMatch(
                isKratzer: true,
                players: players,
                scratchEligiblePlayers: players,
                scratchedPlayer: players[0],
                round: 2,
              ),
            ],
            [
              GroupMatch(
                isKratzer: true,
                players: players,
                scratchEligiblePlayers: players,
                scratchedPlayer: players[1],
                round: 3,
              ),
            ],
            [
              GroupMatch(
                isKratzer: true,
                players: players,
                scratchEligiblePlayers: players,
                scratchedPlayer: players[1],
                round: 4,
              ),
            ],
          ],
          isKratzer: true,
          eliminationLossLimit: 2,
          participants: players,
        ),
      ],
      completedStageIndexes: {0},
      finishedAt: DateTime.utc(2026, 1, 1),
    );
    return tournament;
  }

  test('completed Kratzer tournaments report the sole surviving player', () {
    final tournament = completedKratzerTournament();
    expect(TournamentWinner.name(tournament), tournament.players[2].name);
  });

  testWidgets('completed Kratzer results page renders without crashing', (
    tester,
  ) async {
    final tournament = completedKratzerTournament();

    await tester.pumpWidget(
      MaterialApp(home: TournamentResultsPage(tournament: tournament)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
