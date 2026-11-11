import 'package:flutter_test/flutter_test.dart';

import 'support/tournament_simulation_engine.dart';
import 'support/tournament_simulation_report_log.dart';
import 'support/tournament_simulation_scenarios.dart';

void main() {
  test('RHL production preset completes with home win, draw and away win', () {
    for (final homeWins in [10, 9, 8]) {
      final league = rhlDevelopmentScenario();
      for (var i = 0; i < league.games.length; i++) {
        league.games[i].score(i < homeWins ? 3 : 1, i < homeWins ? 1 : 3);
      }
      expect(league.complete, isTrue);
      expect(league.homePoints, homeWins);
      expect(league.awayPoints, 18 - homeWins);
      expect(league.games.length, 18);
    }
  });
  group('tournament simulation engine', () {
    test('completes common tournament option matrix', () {
      final engine = TournamentSimulationEngine();
      final reports = <TournamentSimulationReport>[];
      final failures = <String>[];
      for (final scenario in tournamentDevelopmentScenarios) {
        try {
          reports.add(engine.run(scenario));
        } catch (error) {
          failures.add('${scenario.name}: $error');
        }
      }
      writeTournamentSimulationLog(reports, failures: failures);

      for (var index = 0; index < reports.length; index++) {
        final report = reports[index];
        final scenario = tournamentDevelopmentScenarios.firstWhere(
          (s) => s.name == report.scenarioName,
        );
        final expectedFinalCount = scenario.stages.last.qualifiers;

        expect(
          report.finalPlayers,
          hasLength(expectedFinalCount),
          reason:
              '${report.scenarioName} muss $expectedFinalCount '
              'finale Teilnehmer ermitteln.',
        );
        expect(
          report.totalMatches,
          greaterThan(0),
          reason: '${report.scenarioName} muss Begegnungen erzeugen.',
        );
        for (final stage in report.stageReports) {
          expect(
            stage.outputCount,
            inInclusiveRange(1, stage.inputCount),
            reason: '${report.scenarioName} / ${stage.name}',
          );
        }
      }
      expect(
        failures,
        isEmpty,
        reason:
            'Produktive Laufzeit blockiert; Details im Turnier-Simulationslog.',
      );
    });

    test('detects impossible qualifier requests', () {
      const scenario = TournamentSimulationScenario(
        name: 'ungueltige KO-Weiterkommen',
        playerCount: 4,
        stages: [
          SimulationEliminationStageSpec(
            name: 'K.-o.-Runde',
            qualifiers: 5,
            lossLimit: 1,
          ),
        ],
      );

      expect(
        () => TournamentSimulationEngine().run(scenario),
        throwsA(isA<TournamentSimulationFailure>()),
      );
    });
  });
}
