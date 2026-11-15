import 'dart:convert';

import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_simulation.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;
import 'package:flutter_test/flutter_test.dart';

void main() {
  CreatedTournament fixture({int boards = 1}) {
    final players = [
      for (var index = 1; index <= 4; index++)
        TournamentPlayer.generated(index),
    ];
    final matches = [
      GroupMatch(homePlayer: players[0], awayPlayer: players[1], round: 1),
      GroupMatch(homePlayer: players[2], awayPlayer: players[3], round: 1),
    ];
    return CreatedTournament(
      id: 'simulation-test',
      name: 'Simulationstest',
      players: players,
      boardCount: boards,
      stages: const [
        TournamentStage(
          name: 'Gruppenphase',
          type: 'groups',
          groupCount: 1,
          groupSizes: [4],
          groupPlayType: 'round_robin',
          qualifiedParticipantCount: 4,
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          qualificationPlan: null,
          tieBreakers: const [],
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: players,
              matches: matches,
            ),
          ],
        ),
      ],
    );
  }

  TournamentRunSimulation simulation(
    CreatedTournament source,
    int seed, {
    TournamentPlanningParameters planningParameters =
        const TournamentPlanningParameters(),
    TournamentSimulationMode mode = TournamentSimulationMode.randomStep,
    int minimumMinutes = 1,
    int maximumMinutes = 5,
  }) => TournamentRunSimulation(
    source: source,
    planningParameters: planningParameters,
    seed: seed,
    mode: mode,
    minimumMinutes: minimumMinutes,
    maximumMinutes: maximumMinutes,
    runtimeFactory: ProductionTournamentRuntime.new,
  );

  test(
    'random boards advance independently and undo restores the full state',
    () {
      final source = fixture(boards: 2);
      final sourceJson = jsonEncode(source.toJson());
      final run = simulation(source, 42);

      expect(run.nextStep(), isTrue);
      final firstStep = jsonEncode(run.tournament.toJson());
      final matches =
          (run.tournament.runStages.single as GroupTournamentRunStage)
              .groups
              .single
              .matches;
      expect(matches.where((match) => match.hasResult), hasLength(1));
      expect(matches.where((match) => match.startedAt != null), hasLength(2));
      expect(run.elapsed.inMinutes, greaterThan(0));
      expect(jsonEncode(source.toJson()), sourceJson);

      expect(run.undoLastStep(), isTrue);
      expect(run.elapsed, Duration.zero);
      final restored =
          (run.tournament.runStages.single as GroupTournamentRunStage)
              .groups
              .single
              .matches;
      expect(
        restored,
        everyElement(
          predicate<GroupMatch>(
            (match) =>
                !match.hasResult &&
                match.startedAt == null &&
                match.finishedAt == null &&
                match.boardNumber == null,
          ),
        ),
      );
      expect(run.nextStep(), isTrue);
      expect(jsonEncode(run.tournament.toJson()), firstStep);
    },
  );

  test('fixed matches honor the configured board idle time', () {
    final source = fixture();
    final parameters = TournamentPlanningParameters.fromValues({
      PlanningParameter.minutes501DoubleOut: 1,
      PlanningParameter.boardIdleMinutes: 2,
    });
    final run = simulation(
      source,
      42,
      planningParameters: parameters,
      mode: TournamentSimulationMode.fixedStep,
    );

    expect(run.nextStep(), isTrue);
    final matches = (run.tournament.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches;
    final finished = matches.singleWhere((match) => match.hasResult);
    final running = matches.singleWhere(
      (match) => !match.hasResult && match.startedAt != null,
    );

    expect(
      running.startedAt!.difference(finished.finishedAt!),
      Duration(minutes: parameters.boardIdleMinutes),
    );
    expect(source.runStages.single, isA<GroupTournamentRunStage>());
    expect(
      (source.runStages.single as GroupTournamentRunStage)
          .groups
          .single
          .matches,
      everyElement(
        predicate<GroupMatch>(
          (match) => !match.hasResult && match.startedAt == null,
        ),
      ),
    );
  });

  test('random durations include seeded seconds within minute bounds', () {
    final run = simulation(
      fixture(),
      42,
      minimumMinutes: 4,
      maximumMinutes: 15,
    );
    final match = (run.tournament.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches
        .first;

    expect(run.startMatch(match, 1), isTrue);
    expect(run.nextStep(), isTrue);

    final completed =
        (run.tournament.runStages.single as GroupTournamentRunStage)
            .groups
            .single
            .matches
            .singleWhere((match) => match.hasResult);
    final duration = completed.finishedAt!.difference(completed.startedAt!);
    expect(duration.inSeconds, inInclusiveRange(240, 900));
    expect(duration.inSeconds % 60, isNot(0));
  });

  test('a free board can start another match while other boards stay busy', () {
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index),
    ];
    final matches = [
      for (var home = 0; home < players.length; home++)
        for (var away = home + 1; away < players.length; away++)
          GroupMatch(
            homePlayer: players[home],
            awayPlayer: players[away],
            round: 1,
          ),
    ];
    final tournament = CreatedTournament(
      id: 'simulation-availability-test',
      name: 'Simulation Verfügbarkeit',
      players: players,
      boardCount: 4,
      stages: const [
        TournamentStage(
          name: 'Gruppenphase',
          type: 'groups',
          groupCount: 1,
          groupSizes: [8],
          groupPlayType: 'round_robin',
          qualifiedParticipantCount: 8,
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          qualificationPlan: null,
          tieBreakers: const [],
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: players,
              matches: matches,
            ),
          ],
        ),
      ],
    );
    final run = simulation(tournament, 42)..setAutoStartMatches(false);
    final simulatedMatches =
        (run.tournament.runStages.single as GroupTournamentRunStage)
            .groups
            .single
            .matches;

    expect(run.startMatch(simulatedMatches.first, 1), isTrue);
    expect(run.startMatch(simulatedMatches[13], 2), isTrue);
    expect(run.nextStep(), isTrue);

    final running = (run.tournament.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches
        .where((match) => match.startedAt != null && !match.isResolved);
    expect(running, hasLength(1));
    final availableBoards = run.availableBoardsFor(simulatedMatches[22]);
    expect(availableBoards, isNotEmpty);
    expect(run.startMatch(simulatedMatches[22], availableBoards.first), isTrue);
    expect(
      (run.tournament.runStages.single as GroupTournamentRunStage)
          .groups
          .single
          .matches
          .where((match) => match.startedAt != null && !match.isResolved),
      hasLength(2),
    );
  });

  test('manual starts work without automatic starts and are undoable', () {
    final source = fixture(boards: 2);
    final sourceJson = jsonEncode(source.toJson());
    final run = simulation(source, 42)..setAutoStartMatches(false);
    final matches = (run.tournament.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches;

    expect(run.autoStartMatches, isFalse);
    expect(run.nextStep(), isFalse);
    expect(
      matches,
      everyElement(predicate<GroupMatch>((m) => m.startedAt == null)),
    );
    expect(run.availableBoardsFor(matches[1]), contains(1));
    expect(run.startMatch(matches[1], 1), isTrue);
    expect(matches[1].startedAt, isNotNull);
    expect(matches[0].startedAt, isNull);
    expect(jsonEncode(source.toJson()), sourceJson);
    expect(run.eventLog.last, contains('manuell gestartet'));

    expect(run.undoLastStep(), isTrue);
    final restoredMatches =
        (run.tournament.runStages.single as GroupTournamentRunStage)
            .groups
            .single
            .matches;
    expect(restoredMatches[1].startedAt, isNull);
    expect(run.eventLog.last, contains('rückgängig gemacht'));
  });

  test('reset restores the beginning while preserving simulation options', () {
    final run = simulation(fixture(), 42)..setAutoStartMatches(false);
    expect(run.nextStep(), isFalse);
    final match = (run.tournament.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches
        .first;
    expect(run.startMatch(match, 1), isTrue);
    run.reset();

    expect(run.elapsed, Duration.zero);
    expect(run.stepCount, 0);
    expect(run.autoStartMatches, isFalse);
    expect(run.canUndo, isFalse);
    expect(run.eventLog.last, contains('zurückgesetzt'));
    expect(
      (run.tournament.runStages.single as GroupTournamentRunStage)
          .groups
          .single
          .matches,
      everyElement(predicate<GroupMatch>((m) => m.startedAt == null)),
    );
  });
}
