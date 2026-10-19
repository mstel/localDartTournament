import 'dart:io';

import 'package:dart_tournament_manager/features/rankings/application/tournament_match_elo_service.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'returns persisted-ranking Elo deltas for tournament result matches',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tournament_match_elo_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final homeProfile = await database.createPlayerProfile(
        displayName: 'Anna Home',
      );
      final awayProfile = await database.createPlayerProfile(
        displayName: 'Ben Away',
      );
      const ranking = LocalRanking(id: 'elo', name: 'Vereinsrangliste');
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(ranking.id, [
        homeProfile.id,
        awayProfile.id,
      ]);

      final home = TournamentPlayer(
        name: homeProfile.displayName,
        profileId: homeProfile.id,
        isGenerated: false,
      );
      final away = TournamentPlayer(
        name: awayProfile.displayName,
        profileId: awayProfile.id,
        isGenerated: false,
      );
      final match = GroupMatch(homePlayer: home, awayPlayer: away, round: 1)
        ..homeLegs = 1
        ..awayLegs = 0;
      final tournament = CreatedTournament(
        name: 'Testturnier',
        players: [home, away],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [match],
            ],
          ),
        ],
        rankingIds: [ranking.id],
        startedAt: DateTime(2026, 1, 1),
      );
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      await storage.saveTournament(tournament);

      final changes = await TournamentMatchEloService(
        database: database,
        tournamentStorage: storage,
      ).calculate(tournament);
      final matchChanges = changes.values.single;

      expect(matchChanges, hasLength(1));
      expect(matchChanges.single.homeDelta, greaterThan(0));
      expect(matchChanges.single.awayDelta, lessThan(0));
    },
  );
}
