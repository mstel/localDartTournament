import 'dart:io';

import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/statistics/domain/local_statistics.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'deleting a tournament removes its best performances from player stats',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'local_statistics_best_performance_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final player = await database.createPlayerProfile(
        displayName: 'Anna Musterfrau',
      );
      final opponent = await database.createPlayerProfile(
        displayName: 'Ben Beispielmann',
      );
      final home = TournamentPlayer(
        name: player.displayName,
        profileId: player.id,
        isGenerated: false,
      );
      final away = TournamentPlayer(
        name: opponent.displayName,
        profileId: opponent.id,
        isGenerated: false,
      );
      final match = GroupMatch(
        homePlayer: home,
        awayPlayer: away,
        round: 1,
        homeLegs: 2,
        awayLegs: 0,
        bestPerformances: [
          BestPerformance(
            type: BestPerformanceType.score170,
            playerName: player.displayName,
            playerProfileId: player.id,
            value: 170,
          ),
        ],
      );
      final tournament = CreatedTournament(
        id: 'best-performance-tournament',
        name: 'Vereinsmeisterschaft',
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
      );
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      final statistics = LocalStatisticsService(
        database: database,
        storage: storage,
      );

      await storage.saveTournament(tournament);
      expect(
        (await statistics.forPlayers({player.id})).bestPerformances,
        hasLength(1),
      );

      await storage.deleteTournament(tournament.id);

      expect(
        (await statistics.forPlayers({player.id})).bestPerformances,
        isEmpty,
      );
    },
  );
}
