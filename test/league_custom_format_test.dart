import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/league/application/league_board_runtime.dart';
import 'package:dart_tournament_manager/features/league/application/league_duration_estimator.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';

void main() {
  final home = [for (var i = 1; i <= 7; i++) 'Heim $i'];
  final away = [for (var i = 1; i <= 7; i++) 'Gast $i'];

  test(
    'adjusted schedule spreads singles and limits doubles to unique pairs',
    () {
      final league = LeagueMatch.adjusted(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: home,
        awayPlayers: away,
        singlesPerPlayer: 2,
        doublesCount: 3,
      );

      expect(league.games, hasLength(17));
      expect(league.games.where((game) => game.isDouble), hasLength(3));
      for (var player = 0; player < 7; player++) {
        expect(
          league.games.where(
            (game) => !game.isDouble && game.home.single == player,
          ),
          hasLength(2),
        );
        expect(
          league.games.where(
            (game) => !game.isDouble && game.away.single == player,
          ),
          hasLength(2),
        );
        expect(
          league.games.where(
            (game) => game.isDouble && game.home.contains(player),
          ),
          hasLength(lessThanOrEqualTo(1)),
        );
      }
      expect(
        league.games
            .where((game) => game.isDouble)
            .expand((game) => game.home)
            .length,
        6,
      );
      expect(
        league.games
            .where((game) => game.isDouble)
            .expand((game) => game.away)
            .length,
        6,
      );
      final restored = LeagueMatch.fromJson(league.toJson());
      expect(restored.variant, LeagueMatchVariant.adjusted);
      expect(restored.games, hasLength(17));
      expect(restored.singlesPerPlayer, 2);
      expect(restored.doublesCount, 3);
    },
  );

  test('cannot schedule more doubles than disjoint player pairs', () {
    expect(
      () => LeagueMatch.adjusted(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: home,
        awayPlayers: away,
        singlesPerPlayer: 2,
        doublesCount: 4,
      ),
      throwsFormatException,
    );
  });

  test('custom format and set results survive persistence', () {
    const format = TournamentGameFormat(
      x01Score: 301,
      checkoutType: 'single_out',
      bestOfLegs: 3,
      bestOfSets: 3,
    );
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: home,
      awayPlayers: away,
      singlesPerPlayer: 1,
      doublesCount: 0,
      gameFormat: format,
    );
    league.games.first.score(2, 1, format: format, legsHome: 3, legsAway: 1);

    final restored = LeagueMatch.fromJson(league.toJson());
    expect(restored.gameFormat.x01Score, 301);
    expect(restored.gameFormat.checkoutType, 'single_out');
    expect(restored.gameFormat.bestOfSets, 3);
    expect(restored.games.first.homeScore(format), 2);
    expect(restored.games.first.homeLegs, 3);
    expect(restored.homePoints, 1);
    expect(
      () => restored.games[1].score(1, 1, format: format),
      throwsFormatException,
    );
  });

  test(
    'league fixtures project into the standard run stage and sync results',
    () {
      const format = TournamentGameFormat(bestOfLegs: 3, bestOfSets: 3);
      final league = LeagueMatch.adjusted(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: ['Heim 1', 'Heim 2'],
        awayPlayers: ['Gast 1', 'Gast 2'],
        singlesPerPlayer: 1,
        doublesCount: 0,
        gameFormat: format,
      );
      final tournament = CreatedTournament(
        name: 'Freundschaftsspiel',
        players: [
          for (final name in ['Heim 1', 'Heim 2', 'Gast 1', 'Gast 2'])
            TournamentPlayer(name: name, isGenerated: false),
        ],
        stages: [],
        runStages: [],
        leagueMatch: league,
      );
      final runtime = LeagueBoardRuntime(tournament)..installOn(tournament);
      final runStage = tournament.runStages.single as GroupTournamentRunStage;
      expect(tournament.stages.single.gameFormat, format);
      expect(runStage.groups.single.matches, hasLength(2));

      runtime.matches.first
        ..homeSets = 2
        ..awaySets = 1
        ..homeLegs = 5
        ..awayLegs = 3;
      runtime.writeTo(tournament);

      expect(tournament.leagueMatch!.games.first.homeSets, 2);
      expect(tournament.leagueMatch!.games.first.awaySets, 1);
      expect(tournament.leagueMatch!.games.first.homeLegs, 5);
      expect(tournament.leagueMatch!.games.first.awayLegs, 3);
      expect(tournament.leagueMatch!.homePoints, 1);
    },
  );

  test('duration estimate uses the league board schedule and BO5 settings', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: home,
      awayPlayers: away,
      singlesPerPlayer: 2,
      doublesCount: 3,
    );
    const estimator = LeagueDurationEstimator();
    final oneBoard = estimator.estimate(
      league: league,
      boards: 1,
      parameters: const TournamentPlanningParameters(),
    );
    final threeBoards = estimator.estimate(
      league: league,
      boards: 3,
      parameters: const TournamentPlanningParameters(),
    );
    expect(oneBoard.matches, 17);
    expect(oneBoard.minutes, greaterThan(0));
    expect(threeBoards.minutes, lessThanOrEqualTo(oneBoard.minutes));
  });

  test('duration estimate uses the configured X01 and leg/set format', () {
    LeagueMatch adjustedWithFormat(TournamentGameFormat format) =>
        LeagueMatch.adjusted(
          homeTeam: 'Heim',
          awayTeam: 'Gast',
          homePlayers: home,
          awayPlayers: away,
          singlesPerPlayer: 2,
          doublesCount: 3,
          gameFormat: format,
        );

    const estimator = LeagueDurationEstimator();
    final shortFormat = estimator.estimate(
      league: adjustedWithFormat(
        const TournamentGameFormat(
          x01Score: 301,
          checkoutType: 'single_out',
          bestOfLegs: 3,
        ),
      ),
      boards: 2,
      parameters: const TournamentPlanningParameters(),
    );
    final longFormat = estimator.estimate(
      league: adjustedWithFormat(
        const TournamentGameFormat(x01Score: 901, bestOfLegs: 9, bestOfSets: 3),
      ),
      boards: 2,
      parameters: const TournamentPlanningParameters(),
    );

    expect(longFormat.matches, shortFormat.matches);
    expect(longFormat.minutes, greaterThan(shortFormat.minutes));
  });

  test('late reserves and extra substitutions extend the counters', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: home,
      awayPlayers: away,
      singlesPerPlayer: 1,
      doublesCount: 1,
      starterCount: 6,
      maxReservePlayers: 1,
      substitutionLimit: 1,
    );

    expect(league.homePlayers, hasLength(7));
    expect(league.maxReservePlayers, 1);
    expect(league.substitutionLimit, 1);

    league.addReservePlayers(teamSide: 0, names: const ['Heim 8']);
    expect(league.homePlayers, hasLength(8));
    expect(league.maxReservePlayers, 2);
    expect(league.reservePlayers(0), contains(7));

    league.addSubstitution(teamSide: 0, outPlayerIndex: 0, inPlayerIndex: 6);
    expect(league.substitutionLimit, 2);
    expect(league.substitutionsUsed(0), 1);
    expect(league.substitutionsRemaining(0), 1);
    expect(league.activePlayers(0), contains(6));
    expect(league.activePlayers(0), isNot(contains(0)));

    final restored = LeagueMatch.fromJson(league.toJson());
    expect(restored.maxReservePlayers, 2);
    expect(restored.substitutionLimit, 2);
    expect(restored.substitutionsUsed(0), 1);
  });

  test('adding substitution budget only raises the available counter', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: home,
      awayPlayers: away,
      singlesPerPlayer: 1,
      doublesCount: 1,
      starterCount: 5,
      maxReservePlayers: 2,
      substitutionLimit: 1,
    );

    expect(league.substitutionLimitFor(0), 1);
    expect(league.substitutionLimitFor(1), 1);
    expect(league.substitutionsRemaining(0), 1);
    expect(league.substitutionsRemaining(1), 1);
    expect(league.substitutionsUsed(0), 0);

    league.addSubstitutionBudget(teamSide: 0);

    expect(league.substitutionLimitFor(0), 2);
    expect(league.substitutionLimitFor(1), 1);
    expect(league.substitutionsRemaining(0), 2);
    expect(league.substitutionsRemaining(1), 1);
    expect(league.substitutionsUsed(0), 0);
    expect(league.substitutions, isEmpty);

    final restored = LeagueMatch.fromJson(league.toJson());
    expect(restored.substitutionLimitFor(0), 2);
    expect(restored.substitutionLimitFor(1), 1);
    expect(restored.substitutionsRemaining(0), 2);
    expect(restored.substitutionsRemaining(1), 1);
  });

  test('a rejected substitution leaves both team budgets untouched', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: home.take(6).toList(),
      awayPlayers: away.take(6).toList(),
      singlesPerPlayer: 1,
      doublesCount: 1,
      starterCount: 4,
      maxReservePlayers: 2,
      substitutionLimit: 1,
    );

    expect(
      () => league.substitute(
        teamSide: 1,
        outPlayerIndex: 5,
        inPlayerIndex: 4,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('nicht in der aktuellen Aufstellung'),
        ),
      ),
    );

    expect(league.substitutionLimitFor(0), 1);
    expect(league.substitutionLimitFor(1), 1);
    expect(league.substitutionsRemaining(0), 1);
    expect(league.substitutionsRemaining(1), 1);
    expect(league.substitutions, isEmpty);
  });

  test('successful substitutions consume only the selected team budget', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: home,
      awayPlayers: away,
      singlesPerPlayer: 1,
      doublesCount: 1,
      starterCount: 5,
      maxReservePlayers: 2,
      substitutionLimit: 2,
    );

    league.substitute(teamSide: 0, outPlayerIndex: 3, inPlayerIndex: 6);

    expect(league.substitutionsRemaining(0), 1);
    expect(league.substitutionsRemaining(1), 2);
    expect(league.activePlayers(0), isNot(contains(3)));
    expect(league.activePlayers(0), contains(6));
    expect(
      league.substitutions.where((event) => event.outPlayerIndex == 3),
      hasLength(1),
    );
  });
}
