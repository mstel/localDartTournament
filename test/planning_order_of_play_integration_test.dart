import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/tournament_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/planning_duration.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  test(
    'suggestion duration equals live Order of Play for identical groups and boards',
    () {
      for (final sizes in [
        [7, 6],
        [5, 4, 4],
        [3, 3],
        [8],
        [2, 2, 2, 2],
      ]) {
        for (final boards in [1, 2, 3, 4, 5]) {
          final groups = [
            for (var g = 0; g < sizes.length; g++) buildGroup(g, sizes[g]),
          ];
          final tournament = CreatedTournament(
            name: 'Test',
            players: [for (final g in groups) ...g.players],
            stages: [],
            boardCount: boards,
            runStages: [
              GroupTournamentRunStage(
                name: 'Gruppen',
                groupPlayType: 'round_robin',
                groups: groups,
                qualificationPlan: null,
                tieBreakers: defaultGroupTieBreakers,
              ),
            ],
          );
          final live = const OrderOfPlayController().plan(tournament, 0);
          final estimate = PlanningDuration.calculate(
            groupSizes: sizes,
            qualifiers: 0,
            boards: boards,
            matchMinutes: 25,
            strategy: tournament.directorSchedulingStrategy,
          );
          expect(
            estimate.groupSlots,
            live.planned.last.block + 1,
            reason: '$sizes on $boards boards',
          );
          expect(estimate.groupMinutes, (live.planned.last.block + 1) * 25);
        }
      }
    },
  );
}

TournamentGroup buildGroup(int group, int size) {
  final players = [
    for (var i = 0; i < size; i++)
      TournamentPlayer(name: '$group/$i', isGenerated: true),
  ];
  return TournamentGroup(
    name: '$group',
    playType: 'round_robin',
    players: players,
    matches: tournamentEngine.buildRoundRobinMatches(players),
  );
}
