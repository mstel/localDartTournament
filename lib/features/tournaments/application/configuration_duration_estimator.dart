import '../../../tournament_workspace.dart' show ProductionTournamentRuntime;
import '../domain/tournament_models.dart';
import '../domain/tournament_format_planner.dart';
import '../domain/tournament_planning_parameters.dart';
import '../domain/engines/board_scheduling_engine.dart';

class ConfigurationEstimate {
  const ConfigurationEstimate(
    this.minutes,
    this.totalMatches,
    this.minimumMatches,
    this.variableMatches, [
    this.matchEndSeconds = const [],
    this.waitMinutes = 0,
  ]);
  final int minutes, totalMatches, minimumMatches;
  final bool variableMatches;
  final List<int> matchEndSeconds;
  final double waitMinutes;
}

/// Uses an isolated production runtime; never mutates or saves the draft.
class ConfigurationDurationEstimator {
  const ConfigurationDurationEstimator();

  int? estimate(
    List<TournamentStage> stages,
    int boards,
    TournamentPlanningParameters parameters,
  ) => preview(stages, boards, parameters)?.minutes;

  ConfigurationEstimate? preview(
    List<TournamentStage> stages,
    int boards,
    TournamentPlanningParameters parameters, {
    int? finalQualifiers,
  }) {
    if (stages.isEmpty || boards < 1) return null;
    final tournament = CreatedTournament(
      name: 'Zeitvorschau',
      players: [],
      stages: [
        ...stages,
        if (finalQualifiers != null && finalQualifiers > 1)
          TournamentStage(
            name: 'Folgeetappe',
            type: 'single_knockout',
            knockoutParticipantCount: finalQualifiers,
          ),
      ],
      runStages: [],
    );
    final runtime = ProductionTournamentRuntime(tournament);
    final planner = TournamentFormatPlanner(parameters: parameters);
    var minutes = 0.0;
    var waitMinutes = 0.0;
    final matchEndSeconds = <int>[];
    var totalMatches = 0;
    var minimumMatches = 0;
    var allParticipantsReachStage = true;
    var variableMatches = false;
    var hasScheduledBlocks = false;
    for (var index = 0; index < stages.length; index++) {
      final config = stages[index];
      final count = config.type == 'groups'
          ? config.groupSizes.fold<int>(0, (sum, size) => sum + size)
          : config.knockoutParticipantCount ?? 0;
      if (count < 2) return null;
      final stage = runtime.build(
        config,
        List.generate(count, (i) => TournamentPlayer.generated(i + 1)),
      );
      tournament.runStages.add(stage);
      runtime.activate(index);
      runtime.advance();
      final swissRounds = <int>{};
      if (allParticipantsReachStage) {
        minimumMatches += _minimum(config, stage);
      }
      if (index + 1 < stages.length) {
        final next = stages[index + 1];
        final nextCount = next.type == 'groups'
            ? next.groupSizes.fold<int>(0, (a, b) => a + b)
            : next.knockoutParticipantCount ?? 0;
        allParticipantsReachStage =
            allParticipantsReachStage && nextCount == count;
      }
      variableMatches |=
          config.lossLimit > 1 ||
          (stage is GroupTournamentRunStage &&
              stage.groups.any((g) => g.eliminationLossLimit > 1));
      if (stage is GroupTournamentRunStage &&
          stage.groups.every((group) => group.playType == 'round_robin')) {
        final entries = [
          for (final group in stage.groups)
            for (final match in group.matches)
              PlayEntry(match, index, group.name),
        ];
        final schedule = const BoardSchedulingEngine().schedule(
          all: entries,
          ready: entries,
          boardCount: boards,
        );
        final slots = schedule.isEmpty ? 0 : schedule.last.block + 1;
        final matchMinutes = planner.estimatedMatchMinutes(config.gameFormat);
        if (slots > 0 && hasScheduledBlocks) {
          minutes += parameters.boardIdleMinutes;
          waitMinutes += parameters.boardIdleMinutes;
        }
        for (final assignment in schedule) {
          matchEndSeconds.add(
            ((minutes +
                        (assignment.block + 1) * matchMinutes +
                        assignment.block * parameters.boardIdleMinutes) *
                    60)
                .round(),
          );
        }
        if (slots > 0) {
          final boardWait = (slots - 1) * parameters.boardIdleMinutes;
          minutes += slots * matchMinutes + boardWait;
          waitMinutes += boardWait;
          hasScheduledBlocks = true;
        }
        totalMatches += entries.where((e) => e.match.hasPlayers).length;
        continue;
      }
      var blocks = 0;
      while (runtime.hasOpen(stage)) {
        final all = runtime
            .matches(stage)
            .map((match) => PlayEntry(match, index, config.name))
            .toList();
        final ready = all
            .where((entry) => entry.match.hasPlayers && !entry.match.isResolved)
            .toList();
        if (stage is GroupTournamentRunStage) {
          for (final group in stage.groups.where(
            (g) => g.playType == 'swiss',
          )) {
            for (final match in group.matches.where(
              (m) => m.hasPlayers && !m.isResolved && m.round > 1,
            )) {
              if (swissRounds.add(match.round)) {
                final reserve = parameters.value(
                  PlanningParameter.swissRoundWaitMinutes,
                );
                minutes += reserve;
                waitMinutes += reserve;
              }
            }
          }
        }
        if (ready.isEmpty || blocks > 10000) return null;
        final schedule = const BoardSchedulingEngine().schedule(
          all: all,
          ready: ready,
          finished: all.where((entry) => entry.match.hasResult).toList(),
          boardCount: boards,
        );
        final batch = schedule.where((assignment) => assignment.block == 0);
        if (batch.isEmpty) return null;
        final boardWait = blocks > 0 || hasScheduledBlocks
            ? parameters.boardIdleMinutes
            : 0;
        minutes += boardWait;
        waitMinutes += boardWait;
        final matchMinutes = planner.estimatedMatchMinutes(config.gameFormat);
        minutes += matchMinutes;
        for (final assignment in batch) {
          matchEndSeconds.add((minutes * 60).round());
          totalMatches++;
          final match = assignment.entry.match;
          // Deterministic representative results, not predictions of winners.
          match.homeLegs = config.gameFormat.bestOfLegs ~/ 2 + 1;
          match.awayLegs = 0;
          if (config.gameFormat.bestOfSets > 1) {
            match.homeSets = config.gameFormat.bestOfSets ~/ 2 + 1;
            match.awaySets = 0;
          }
        }
        blocks++;
        runtime.advance();
      }
      hasScheduledBlocks = hasScheduledBlocks || blocks > 0;
    }
    return ConfigurationEstimate(
      (minutes - 1e-9).ceil(),
      totalMatches,
      minimumMatches,
      variableMatches,
      matchEndSeconds..sort(),
      waitMinutes,
    );
  }

  // A safe lower bound, including the shortest winning path with byes.
  // Later stages only contribute when every initial entrant reaches them.
  int _eliminationMinimum(
    int players,
    int qualifiers,
    int lives,
    bool finalEnds,
  ) {
    if (players <= qualifiers || players < 2) return 0;
    var rounds = 0;
    var remaining = players;
    while (remaining >= 2 * qualifiers) {
      rounds++;
      remaining ~/= 2;
    }
    return rounds < lives ? rounds : lives;
  }

  int _minimum(TournamentStage config, TournamentRunStage stage) {
    if (stage is GroupTournamentRunStage) {
      var minimum = 1 << 30;
      for (var i = 0; i < stage.groups.length; i++) {
        final group = stage.groups[i];
        final games = group.playType == 'swiss'
            ? group.matches.map((m) => m.round).toSet().length -
                  (group.players.length.isOdd ? 1 : 0)
            : group.playType == 'round_robin'
            ? group.players
                  .map(
                    (p) => group.matches
                        .where(
                          (m) =>
                              m.hasPlayers &&
                              (m.homePlayer == p || m.awayPlayer == p),
                        )
                        .length,
                  )
                  .fold<int>(1 << 30, (a, b) => a < b ? a : b)
            : _eliminationMinimum(
                group.players.length,
                i < config.fixedQualifiersByGroup.length
                    ? config.fixedQualifiersByGroup[i].clamp(
                        1,
                        group.players.length,
                      )
                    : 1,
                group.eliminationLossLimit,
                group.finalEndsTournament,
              );
        if (games < minimum) minimum = games;
      }
      return minimum == 1 << 30 ? 0 : minimum;
    }
    return _eliminationMinimum(
      config.knockoutParticipantCount ?? 0,
      (config.qualifiedParticipantCount ?? 1).clamp(1, 1000000),
      config.lossLimit,
      config.finalEndsTournament,
    );
  }
}
