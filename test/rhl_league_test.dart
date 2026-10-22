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
      expect(jsonDecode(await file.readAsString())['schemaVersion'], 27);
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
