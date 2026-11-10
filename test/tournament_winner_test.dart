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

  CreatedTournament knockoutTournament({required bool thirdPlacePlayed}) {
    final players = [
      for (var index = 1; index <= 4; index++)
        TournamentPlayer.generated(index).copyWith(name: 'KO Spieler $index'),
    ];
    final thirdPlaceMatch = GroupMatch(
      homePlayer: players[1],
      awayPlayer: players[3],
      round: 3,
      label: 'Spiel um Platz 3',
      placementRank: 3,
      homeLegs: thirdPlacePlayed ? 3 : null,
      awayLegs: thirdPlacePlayed ? 1 : null,
    );
    return CreatedTournament(
      name: 'KO Turnier',
      players: players,
      stages: const [
        TournamentStage(
          name: 'KO',
          type: 'single_knockout',
          placementPlaces: [3],
        ),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'KO',
          rounds: [
            [
              GroupMatch(
                homePlayer: players[0],
                awayPlayer: players[1],
                round: 1,
                homeLegs: 3,
                awayLegs: 0,
              ),
              GroupMatch(
                homePlayer: players[2],
                awayPlayer: players[3],
                round: 1,
                homeLegs: 3,
                awayLegs: 0,
              ),
            ],
            [
              GroupMatch(
                homePlayer: players[0],
                awayPlayer: players[2],
                round: 2,
                homeLegs: 3,
                awayLegs: 0,
              ),
            ],
          ],
          placementMatches: [thirdPlaceMatch],
        ),
      ],
      completedStageIndexes: {0},
      finishedAt: DateTime.utc(2026, 1, 1),
    );
  }

  testWidgets('KO podium omits third place when it was not played', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TournamentResultsPage(
          tournament: knockoutTournament(thirdPlacePlayed: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Podium'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3. Platz'), findsNothing);
  });

  testWidgets('KO podium includes third place after a played placement match', (
    tester,
  ) async {
    final tournament = knockoutTournament(thirdPlacePlayed: true);
    final thirdMatch =
        (tournament.runStages.single as KnockoutTournamentRunStage)
            .placementMatches
            .single;
    expect(thirdMatch.hasResult, isTrue);

    await tester.pumpWidget(
      MaterialApp(home: TournamentResultsPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Podium'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3. Platz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
