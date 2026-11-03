import 'simulation_summary.dart';
import 'tournament_simulation_engine.dart';
import 'tournament_simulation_scenarios.dart';
import 'tournament_simulation_report.dart';

/// Pure entry point for an isolate. No access to saved user tournaments.
List<Map<String, Object>> runDevelopmentSimulations(bool unused) {
  final results = <Map<String, Object>>[];
  for (final scenario in tournamentDevelopmentScenarios) {
    for (final seed in <int?>[null, 7, 42]) {
      final name =
          '${scenario.name} · ${seed == null ? 'Standard' : 'Seed $seed'}';
      try {
        final report = TournamentSimulationEngine().run(scenario, seed: seed);
        if (report.finalPlayers.length != scenario.stages.last.qualifiers ||
            report.finalPlayers.map((p) => p.name).toSet().length !=
                report.finalPlayers.length) {
          throw StateError('Ungültige Anzahl oder doppelte Weiterkommende');
        }
        for (final stage in report.stageReports) {
          if (stage.outputCount < 1 || stage.outputCount > stage.inputCount) {
            throw StateError('Ungültige Teilnehmerzahl');
          }
          for (final match in stage.matches) {
            if (!match.isResolved) {
              throw StateError('Offenes Match in ${stage.name}');
            }
            if (match.isKratzer) {
              if (match.players.map((player) => player.name).toSet().length !=
                  match.players.length) {
                throw StateError('Spieler gegen sich selbst');
              }
            } else if (match.hasPlayers &&
                match.homePlayer!.name == match.awayPlayer!.name) {
              throw StateError('Spieler gegen sich selbst');
            }
          }
        }
        results.add({
          'name': name,
          'type': simulationTypeLabel(scenario),
          'allowsDraws': scenario.stages.any((s) => s.gameFormat.allowsDraws),
          'passed': true,
          'matches': report.totalMatches,
          'draws': simulationDrawCount(report),
          'report': report,
          'detail': formatTournamentSimulationLog([report]),
        });
      } catch (error, stack) {
        results.add({
          'name': name,
          'type': simulationTypeLabel(scenario),
          'allowsDraws': scenario.stages.any((s) => s.gameFormat.allowsDraws),
          'passed': false,
          'matches': 0,
          'detail': '$error\n$stack',
        });
      }
    }
  }
  return results;
}
