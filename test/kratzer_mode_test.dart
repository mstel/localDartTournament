import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/dev_tools/domain/tournament_simulation_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  TournamentSimulationReport simulate(
    int lives,
    int players,
    int seed,
    bool finalEnds,
  ) => TournamentSimulationEngine().run(
    TournamentSimulationScenario(
      name: '$lives Leben',
      playerCount: players,
      stages: [
        SimulationEliminationStageSpec(
          name: 'KO',
          qualifiers: 1,
          lossLimit: lives,
          finalEndsTournament: finalEnds,
        ),
      ],
    ),
    seed: seed,
    randomResults: true,
  );

  test(
    '2 to 10 lives use production runtime and eliminate at the chosen limit',
    () {
      for (var lives = 2; lives <= 10; lives++) {
        for (final players in [2, 5, 11]) {
          for (var seed = 0; seed < 5; seed++) {
            final report = simulate(lives, players, seed, false);
            final losses = <String, int>{};
            for (final record in report.stageReports.single.matchRecords) {
              final loser = record.match.loser;
              if (record.match.hasResult && loser != null) {
                losses.update(loser.name, (n) => n + 1, ifAbsent: () => 1);
              }
            }
            expect(
              losses.values.where((n) => n == lives),
              hasLength(players - 1),
            );
            expect(
              losses[report.finalPlayers.single.name] ?? 0,
              lessThan(lives),
            );
          }
        }
      }
    },
  );

  test(
    'grand final decides even when the previously undefeated player loses',
    () {
      for (final lives in [2, 3]) {
        var testedUpset = false;
        for (var seed = 0; seed < 30; seed++) {
          final report = simulate(lives, 2, seed, true);
          final matches = report.stageReports.single.matchRecords
              .where((r) => r.match.hasResult)
              .toList();
          expect(matches, hasLength(2));
          expect(
            report.finalPlayers.single.name,
            matches.last.match.winner!.name,
          );
          if (matches.first.match.winner!.name !=
              report.finalPlayers.single.name) {
            testedUpset = true;
          }
        }
        expect(testedUpset, isTrue);
      }
    },
  );

  test('new stages default to single final, legacy stages keep lives mode', () {
    const stage = TournamentStage(name: 'KO', type: 'triple_knockout');
    expect(stage.finalEndsTournament, isTrue);
    expect(
      TournamentStage.fromJson({
        'name': 'Alt',
        'type': 'triple_knockout',
      }).finalEndsTournament,
      isFalse,
    );
    final configured = TournamentStage(
      name: 'Kratzer',
      type: 'kratzer',
      knockoutLives: 7,
      finalEndsTournament: false,
    );
    final loaded = TournamentStage.fromJson(configured.toJson());
    expect(loaded.lossLimit, 7);
    expect(loaded.finalEndsTournament, isFalse);
  });

  test(
    'multi-player Kratzer rounds keep only the scratched player as loser',
    () {
      final report = TournamentSimulationEngine().run(
        const TournamentSimulationScenario(
          name: 'balanced Kratzer',
          playerCount: 7,
          boards: 2,
          stages: [
            SimulationEliminationStageSpec(
              name: 'Kratzer',
              qualifiers: 1,
              lossLimit: 3,
              isKratzer: true,
            ),
          ],
        ),
        seed: 3,
        randomResults: true,
      );
      expect(report.finalPlayers, hasLength(1));
      for (final record in report.stageReports.single.matchRecords) {
        expect(record.match.isKratzer, isTrue);
        expect(record.match.players.length, inInclusiveRange(3, 6));
        expect(record.match.winner, isNull);
        expect(record.match.loser, record.match.scratchedPlayer);
      }
    },
  );
}
