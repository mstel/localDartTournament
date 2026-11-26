import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/director_schedule_modes.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;

void main() {
  test('helper keeps group assignment only in group phases', () {
    expect(
      DirectorScheduleModes.strategyForStage(
        DirectorScheduleModes.group,
        DirectorScheduleModes.fixedSchedule,
        'groups',
      ),
      DirectorScheduleModes.group,
    );
    for (final type in [
      'single_knockout',
      'double_knockout',
      'triple_knockout',
    ]) {
      expect(
        DirectorScheduleModes.strategyForStage(
          DirectorScheduleModes.group,
          DirectorScheduleModes.fixedSchedule,
          type,
        ),
        DirectorScheduleModes.global,
      );
      expect(DirectorScheduleModes.allowsGroupBoardAssignment(type), isFalse);
    }
  });

  test('production runtime switches group assignment when KO is activated', () {
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index),
    ];
    final stages = [
      TournamentStage(
        name: 'Gruppe',
        type: 'groups',
        groupSizes: const [4, 4],
        qualifiedParticipantCount: 4,
        fixedQualifiersByGroup: const [2, 2],
        qualificationAutoAdjust: true,
      ),
      TournamentStage(
        name: 'KO',
        type: 'single_knockout',
        knockoutParticipantCount: 4,
      ),
    ];
    final tournament = CreatedTournament(
      name: 'Boardwechsel',
      players: players,
      stages: stages,
      runStages: <TournamentRunStage>[],
      directorPlayOrderMode: DirectorScheduleModes.fixedSchedule,
      directorSchedulingStrategy: DirectorScheduleModes.group,
    );
    final runtime = ProductionTournamentRuntime(tournament);
    tournament.runStages.add(runtime.build(stages.first, players));
    tournament.runStages.add(
      runtime.build(stages.last, players.take(4).toList()),
    );

    runtime.activate(0);
    expect(tournament.directorSchedulingStrategy, DirectorScheduleModes.group);

    runtime.activate(1);
    expect(tournament.directorSchedulingStrategy, DirectorScheduleModes.global);
    expect(
      tournament.directorPlayOrderMode,
      DirectorScheduleModes.fixedSchedule,
    );
  });
}
