import 'package:dart_tournament_manager/features/dev_tools/domain/tournament_simulation_engine.dart';
import 'package:dart_tournament_manager/features/dev_tools/domain/tournament_simulation_scenarios.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'group and Kratzer tournaments complete through production simulation',
    () {
      final engine = TournamentSimulationEngine();
      final groupScenario = tournamentDevelopmentScenarios.firstWhere(
        (scenario) => scenario.name.startsWith('Begrenzte Gruppe: 13'),
      );
      final groups = engine.run(groupScenario, seed: 82);
      expect(groups.finalPlayers, hasLength(1));
      expect(groups.totalMatches, greaterThan(0));
      expect(
        groups.stageReports
            .expand((stage) => stage.matches)
            .where((match) => match.countsForStatistics),
        isNotEmpty,
      );

      final kratzerScenario = tournamentDevelopmentScenarios.firstWhere(
        (scenario) => scenario.name == 'Kratzer mit zwei Sechsergruppen',
      );
      final kratzer = engine.run(kratzerScenario, seed: 82);
      final kratzerMatches = kratzer.stageReports
          .expand((stage) => stage.matches)
          .toList();
      expect(kratzerMatches, isNotEmpty);
      expect(kratzerMatches.every((match) => match.isKratzer), isTrue);
      expect(
        kratzerMatches.any((match) => match.scratchedPlayer != null),
        isTrue,
      );
    },
  );

  test('league and friendly match results keep their reported values', () {
    final league = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: const ['H1', 'H2', 'H3', 'H4'],
      awayPlayers: const ['G1', 'G2', 'G3', 'G4'],
    );
    for (var index = 0; index < league.games.length; index++) {
      league.games[index].score(index < 6 ? 3 : 1, index < 6 ? 1 : 3);
    }
    expect(league.complete, isTrue);
    expect(league.homePoints, 6);
    expect(league.awayPoints, 12);

    const home = TournamentPlayer(
      profileId: 'friendly-home',
      name: 'Marvin',
      isGenerated: false,
    );
    const away = TournamentPlayer(
      profileId: 'friendly-away',
      name: 'Daniel',
      isGenerated: false,
    );
    final match = GroupMatch(
      homePlayer: home,
      awayPlayer: away,
      round: 1,
      homeLegs: 2,
      awayLegs: 1,
      boardNumber: 2,
      startedAt: DateTime(2026, 8, 1, 18),
      finishedAt: DateTime(2026, 8, 1, 18, 30),
    );
    final friendly = CreatedTournament(
      id: 'friendly',
      name: 'Freundschaftsspiel',
      players: const [home, away],
      stages: const [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Partie',
          rounds: [
            [match],
          ],
        ),
      ],
      countsForRanking: false,
    );
    friendly.addActivity(
      'result_entered',
      'Ergebnis eingetragen · Board 2 · Marvin 2:1 Daniel',
    );

    expect(match.winner, same(home));
    expect(match.loser, same(away));
    expect(match.scoreLabel, '2:1');
    expect(friendly.activityLog.single.message, contains('Board 2'));
    expect(friendly.countsForRanking, isFalse);
  });
}
