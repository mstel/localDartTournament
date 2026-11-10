import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';

LeagueMatch fixture() => LeagueMatch.rhl(
  homeTeam: 'Heim',
  awayTeam: 'Gast',
  homePlayers: ['H1', 'H2', 'H3', 'H4'],
  awayPlayers: ['G1', 'G2', 'G3', 'G4'],
);

void main() {
  test('preset contains all 16 distinct singles and two doubles', () {
    final league = fixture();
    expect(league.games.length, 18);
    expect(
      league.games
          .where((g) => !g.isDouble)
          .map((g) => '${g.home.single}:${g.away.single}')
          .toSet()
          .length,
      16,
    );
    expect(league.games.where((g) => g.isDouble).length, 2);
  });
  test('traditional roster allows four starters and up to four reserves', () {
    final six = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
    );
    final seven = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'H7'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
    );
    final eight = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'H7', 'H8'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7', 'G8'],
    );

    expect(six.games, hasLength(18));
    expect(six.substitutionsRemaining(0), 2);
    expect(seven.substitutionsRemaining(0), 3);
    expect(seven.substitutionsRemaining(1), 2);
    expect(eight.substitutionsRemaining(0), 4);
    expect(
      () => LeagueMatch.rhl(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: List.generate(9, (index) => 'H$index'),
        awayPlayers: List.generate(4, (index) => 'G$index'),
      ),
      throwsFormatException,
    );
  });
  test(
    'substitution updates only future fixtures and persists re-entry rules',
    () {
      final league = LeagueMatch.rhl(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
        awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
      );
      league.games[0]
        ..homeLegs = 3
        ..awayLegs = 1;
      league.games[1].runtime = {
        'startedAt': DateTime(2026, 11, 10).toIso8601String(),
      };

      league.substitute(
        teamSide: 0,
        outPlayerIndex: 0,
        inPlayerIndex: 4,
        occurredAt: DateTime(2026, 11, 10, 12),
      );

      expect(league.games[0].home, [0]);
      expect(league.games[1].home, [1]);
      expect(league.games[2].home, [2]);
      expect(league.games[4].home, [4]);
      expect(league.activePlayers(0), contains(4));
      expect(league.activePlayers(0), isNot(contains(0)));
      expect(league.substitutionsRemaining(0), 1);
      expect(
        () =>
            league.substitute(teamSide: 0, outPlayerIndex: 4, inPlayerIndex: 0),
        throwsFormatException,
      );

      final restored = LeagueMatch.fromJson(league.toJson());
      expect(restored.activePlayers(0), league.activePlayers(0));
      expect(
        restored.substitutions.single.toJson(),
        league.substitutions.single.toJson(),
      );
      expect(restored.games[4].home, [4]);
    },
  );
  test('adjusted substitutions honor the optional re-entry rule', () {
    final noReturn = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
      starterCount: 4,
      maxReservePlayers: 2,
      substitutionLimit: 3,
      singlesPerPlayer: 1,
      doublesCount: 0,
    );
    noReturn.substitute(teamSide: 0, outPlayerIndex: 0, inPlayerIndex: 4);
    expect(
      () =>
          noReturn.substitute(teamSide: 0, outPlayerIndex: 4, inPlayerIndex: 0),
      throwsFormatException,
    );

    final reentry = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
      starterCount: 4,
      maxReservePlayers: 2,
      substitutionLimit: 3,
      allowReentry: true,
      singlesPerPlayer: 1,
      doublesCount: 0,
    );
    reentry.substitute(teamSide: 0, outPlayerIndex: 0, inPlayerIndex: 4);
    reentry.substitute(teamSide: 0, outPlayerIndex: 4, inPlayerIndex: 0);

    expect(reentry.activePlayers(0), contains(0));
    expect(reentry.substitutionsUsed(0), 2);
    expect(LeagueMatch.fromJson(reentry.toJson()).allowReentry, isTrue);
  });
  test('adjusted games use equal starter count with unequal roster sizes', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'H7'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
      starterCount: 4,
      maxReservePlayers: 3,
      substitutionLimit: 3,
      singlesPerPlayer: 2,
      doublesCount: 2,
    );
    expect(league.games, hasLength(10));
    expect(league.games.expand((game) => game.home).toSet(), {0, 1, 2, 3});
    expect(league.games.expand((game) => game.away).toSet(), {0, 1, 2, 3});
    expect(league.substitutionsRemaining(0), 3);
    expect(league.substitutionsRemaining(1), 2);
  });
  test('match points, draw, winner, deletion and invalid results', () {
    final league = fixture();
    for (var i = 0; i < 18; i++) {
      league.games[i].score(i < 9 ? 3 : 1, i < 9 ? 1 : 3);
    }
    expect(league.homePoints, 9);
    expect(league.awayPoints, 9);
    expect(league.outcome, 'Unentschieden');
    league.games.last.score(3, 2);
    expect(league.outcome, 'Sieger: Heim');
    league.games.last.score(null, null);
    expect(league.complete, isFalse);
    expect(() => league.games.last.score(3, 3), throwsFormatException);
    expect(() => league.games.last.score(2, 1), throwsFormatException);
  });
  test(
    'reserve lineups and saved scores survive migration and reload',
    () async {
      final dir = Directory.systemTemp.createTempSync('league_storage_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/tournaments.json');
      await file.writeAsString(
        jsonEncode({'schemaVersion': 8, 'tournaments': []}),
      );
      final storage = TournamentStorage(file: file);
      final league = fixture();
      league.homePlayers.add('Ersatz');
      league.games.last.home = [0, 4];
      league.games.first.score(3, 2);
      final tournament = CreatedTournament(
        name: 'Liga',
        players: [],
        stages: [],
        runStages: [],
        leagueMatch: league,
      );
      await storage.saveTournament(tournament);
      final restored = (await storage.loadTournaments()).single;
      expect(restored.leagueMatch!.toJson(), league.toJson());
      expect(await File('${file.path}.v8.bak').exists(), isTrue);
      expect(jsonDecode(await file.readAsString())['schemaVersion'], 39);
    },
  );
  test('legacy tournaments remain ordinary tournaments', () {
    final old = CreatedTournament(
      name: 'Alt',
      players: [],
      stages: [],
      runStages: [],
    );
    expect(CreatedTournament.fromJson(old.toJson()).leagueMatch, isNull);
  });
}
