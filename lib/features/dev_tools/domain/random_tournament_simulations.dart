import '../../tournaments/domain/group_size_rules.dart';
import 'dart:math';
import 'simulation_summary.dart';
import '../../tournaments/domain/tournament_models.dart';
import 'tournament_simulation_engine.dart';
import 'tournament_simulation_report.dart';

class RandomSimulationRequest {
  const RandomSimulationRequest({required this.seed, this.count = 20});
  final int seed;
  final int count;
}

/// Stable seeds reproduce both the layout and independent match outcomes.
TournamentSimulationScenario randomTournamentScenario(int seed) {
  final random = Random(seed);
  final players = 2 + random.nextInt(31);
  final drawsRandom = Random(seed ^ 0x5a17);
  TournamentGameFormat format({bool group = false}) {
    final value = TournamentGameFormat(
      x01Score: random.nextBool() ? 301 : 501,
      bestOfLegs: [1, 3, 5, 7][random.nextInt(4)],
      bestOfSets: [1, 1, 1, 3, 5][random.nextInt(5)],
    );
    if (group && value.bestOfSets == 1 && drawsRandom.nextBool()) {
      return TournamentGameFormat(
        x01Score: value.x01Score,
        bestOfLegs: value.bestOfLegs + 1,
      );
    }
    return value;
  }

  final stages = <SimulationStageSpec>[];
  var remaining = players;
  if (random.nextBool() && players >= minimumPlayersPerGroup * 2) {
    final groups =
        2 + random.nextInt(min(4, players ~/ minimumPlayersPerGroup) - 1);
    final sizes = List.generate(
      groups,
      (i) => players ~/ groups + (i < players % groups ? 1 : 0),
    );
    final perGroup = 1 + random.nextInt(min(2, sizes.last));
    remaining = perGroup * groups;
    stages.add(
      SimulationGroupStageSpec(
        name: 'Gruppenphase',
        qualifiers: remaining,
        groupSizes: sizes,
        fixedPerGroup: perGroup,
        gameFormat: format(group: true),
        roundRobinRepeats: List.generate(groups, (_) => 1 + random.nextInt(2)),
      ),
    );
  }
  if (remaining > 4 && random.nextBool()) {
    final qualifiers = 2 + random.nextInt(remaining - 2);
    stages.add(
      SimulationEliminationStageSpec(
        name: 'Zwischenrunde',
        qualifiers: qualifiers,
        lossLimit: 1 + random.nextInt(3),
        gameFormat: format(),
      ),
    );
    remaining = qualifiers;
  }
  stages.add(
    SimulationEliminationStageSpec(
      name: 'Finalrunde',
      qualifiers: 1,
      lossLimit: 1 + random.nextInt(3),
      gameFormat: format(),
    ),
  );
  return TournamentSimulationScenario(
    name: 'Zufall · $players Teilnehmer · Seed $seed',
    playerCount: players,
    stages: stages,
  );
}

List<Map<String, Object>> runRandomSimulations(
  RandomSimulationRequest request,
) {
  if (request.count < 1 ||
      request.count > 100 ||
      request.seed < 0 ||
      request.seed > 0x7fffffff) {
    throw ArgumentError(
      '1–100 Turniere und Seed von 0 bis 2147483647 erforderlich.',
    );
  }
  return [
    for (var i = 0; i < request.count; i++)
      _run((request.seed + i) & 0x7fffffff),
  ];
}

Map<String, Object> _run(int seed) {
  final scenario = randomTournamentScenario(seed);
  final setup = StringBuffer(
    'Seed: $seed (mit Anzahl 1 einzeln wiederholbar)\n',
  );
  for (final stage in scenario.stages) {
    final mode = stage is SimulationGroupStageSpec
        ? 'Gruppen ${stage.groupSizes.join('/')} · Begegnungen ${stage.roundRobinRepeats.join('/')}'
        : '${(stage as SimulationEliminationStageSpec).lossLimit}-KO';
    setup.writeln(
      '${stage.name}: $mode · ${stage.gameFormat.label} · ${stage.qualifiers} weiter',
    );
  }
  try {
    final report = TournamentSimulationEngine().run(
      scenario,
      seed: seed,
      randomResults: true,
    );
    if (report.finalPlayers.length != 1) {
      throw StateError('Kein eindeutiger Sieger');
    }
    for (var index = 0; index < report.stageReports.length; index++) {
      final stage = report.stageReports[index];
      final spec = scenario.stages[index];
      for (final match in stage.matches) {
        if (!match.isResolved ||
            (match.winner == null &&
                !(spec is SimulationGroupStageSpec &&
                    spec.gameFormat.allowsDraws &&
                    !match.isDecider &&
                    match.homeLegs == spec.gameFormat.bestOfLegs ~/ 2 &&
                    match.awayLegs == spec.gameFormat.bestOfLegs ~/ 2)) ||
            match.homePlayer?.name == match.awayPlayer?.name) {
          throw StateError('Ungültiges Match in ${stage.name}');
        }
      }
    }
    return {
      'name': scenario.name,
      'type': simulationTypeLabel(scenario),
      'allowsDraws': scenario.stages.any((s) => s.gameFormat.allowsDraws),
      'seed': seed,
      'passed': true,
      'matches': report.totalMatches,
      'draws': simulationDrawCount(report),
      'report': report,
      'detail': '$setup\n${formatTournamentSimulationLog([report])}',
    };
  } catch (error, stack) {
    return {
      'name': scenario.name,
      'type': simulationTypeLabel(scenario),
      'allowsDraws': scenario.stages.any((s) => s.gameFormat.allowsDraws),
      'seed': seed,
      'passed': false,
      'matches': 0,
      'detail': '$setup\n$error\n$stack',
    };
  }
}
