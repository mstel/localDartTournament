import 'package:dart_tournament_manager/features/tournaments/domain/engines/placement_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TournamentPlayer player(String name) =>
      TournamentPlayer(name: name, isGenerated: true);

  List<GroupMatch> round(String label, int count) => [
    for (var index = 0; index < count; index++)
      GroupMatch(
        homePlayer: player('$label-H$index'),
        awayPlayer: player('$label-A$index'),
        round: index + 1,
        label: label,
      ),
  ];

  test('double knockout placement playoffs cover fifth and seventh place', () {
    final rounds = [
      round('Losers Runde 1', 2),
      round('Losers Runde 2', 2),
      round('Losers Runde 3', 1),
      round('Losers Runde 4', 1),
    ];

    final placementMatches = PlacementEngine.buildDoubleElimination(rounds, [
      5,
      7,
    ]);

    expect(placementMatches, hasLength(2));
    expect(placementMatches.map((match) => match.placementRank).toSet(), {
      5,
      7,
    });
    expect(placementMatches.map((match) => match.placementKey).toSet(), {
      'double/L1/0',
      'double/L2/0',
    });
  });

  test('placement rank metadata survives tournament storage', () {
    final players = List.generate(8, (index) => player('Spieler ${index + 1}'));
    final rounds = [
      round('Losers Runde 1', 2),
      round('Losers Runde 2', 2),
      round('Losers Runde 3', 1),
      round('Losers Runde 4', 1),
    ];
    final placements = PlacementEngine.buildDoubleElimination(rounds, [5, 7]);
    final tournament = CreatedTournament(
      name: 'Doppel-KO Platzierungen',
      players: players,
      stages: const [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Doppel-KO',
          rounds: rounds,
          placementMatches: placements,
          eliminationLossLimit: 2,
        ),
      ],
    );
    final restored =
        CreatedTournament.fromJson(tournament.toJson()).runStages.single
            as KnockoutTournamentRunStage;
    expect(
      restored.placementMatches.map((match) => match.placementRank).toSet(),
      {5, 7},
    );
  });

  test('double knockout placement sources follow elimination cohorts', () {
    final rounds = [
      round('Losers Runde 1', 2),
      round('Losers Runde 2', 2),
      round('Losers Runde 3', 1),
      round('Losers Runde 4', 1),
    ];
    for (final match in rounds.expand((matches) => matches)) {
      match.homeLegs = 2;
      match.awayLegs = 0;
    }
    final placements = PlacementEngine.buildDoubleElimination(rounds, [5, 7]);

    PlacementEngine.advanceDoubleElimination(rounds, placements);

    expect(
      placements.map(
        (match) => {match.homePlayer?.name, match.awayPlayer?.name},
      ),
      containsAll([
        {'Losers Runde 1-A0', 'Losers Runde 1-A1'},
        {'Losers Runde 2-A0', 'Losers Runde 2-A1'},
      ]),
    );
    for (final match in placements) {
      match
        ..homeLegs = 2
        ..awayLegs = 1;
    }
    final ranking = PlacementEngine.applyRanking(
      rounds
          .expand((matches) => matches)
          .expand((match) => [match.homePlayer!, match.awayPlayer!])
          .toList(),
      placements,
    );
    final fifthPlace = placements.singleWhere(
      (match) => match.placementRank == 5,
    );
    expect(ranking[4], fifthPlace.winner);
    expect(ranking[5], fifthPlace.loser);
  });

  test('triple knockout playoffs use the final elimination bracket', () {
    final rounds = [
      round('2 Niederlagen Runde 1', 2),
      round('2 Niederlagen Runde 2', 1),
      round('2 Niederlagen Runde 3', 1),
    ];

    final placements = PlacementEngine.buildTripleElimination(rounds, [
      5,
    ], lossLimit: 3);

    expect(placements, hasLength(1));
    expect(placements.single.placementRank, 5);
    expect(placements.single.placementKey, 'triple/L3/R0/0');
  });
}
