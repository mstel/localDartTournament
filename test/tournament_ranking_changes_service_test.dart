import 'package:dart_tournament_manager/features/rankings/application/tournament_ranking_changes_service.dart';
import 'package:dart_tournament_manager/features/rankings/domain/elo_tier.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test(
    'ranks players before and after a tournament and identifies movers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ranking-change-position-test-',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final aProfile = await database.createPlayerProfile(displayName: 'Anna');
      final bProfile = await database.createPlayerProfile(displayName: 'Ben');
      final cProfile = await database.createPlayerProfile(displayName: 'Caro');
      const ranking = LocalRanking(
        id: 'elo',
        name: 'Vereinsrangliste',
        newPlayerK: 40,
        normalPlayerK: 40,
      );
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(ranking.id, [
        aProfile.id,
        bProfile.id,
        cProfile.id,
      ]);

      TournamentPlayer player(String id, String name) =>
          TournamentPlayer(name: name, profileId: id, isGenerated: false);

      CreatedTournament completedMatch(
        String name,
        DateTime date,
        TournamentPlayer home,
        TournamentPlayer away,
      ) {
        final match = GroupMatch(homePlayer: home, awayPlayer: away, round: 1)
          ..homeLegs = 1
          ..awayLegs = 0;
        return CreatedTournament(
          name: name,
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
          startedAt: date,
        );
      }

      final a = player(aProfile.id, 'Anna');
      final b = player(bProfile.id, 'Ben');
      final c = player(cProfile.id, 'Caro');
      final beforeOne = completedMatch('Vorher 1', DateTime(2026, 1, 1), b, a);
      final beforeTwo = completedMatch('Vorher 2', DateTime(2026, 1, 2), c, a);
      final target = completedMatch('Zielturnier', DateTime(2026, 1, 3), c, b);
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      for (final tournament in [beforeOne, beforeTwo, target]) {
        await storage.saveTournament(tournament);
      }

      final changes = await TournamentRankingChangesService(
        database: database,
        storage: storage,
      ).calculate(target);
      final ben = changes.singleWhere(
        (change) => change.playerProfileId == bProfile.id,
      );
      final caro = changes.singleWhere(
        (change) => change.playerProfileId == cProfile.id,
      );

      expect(caro.rankingPositionBefore, 2);
      expect(caro.rankingPositionAfter, 1);
      expect(caro.positionChange, 1);
      expect(ben.rankingPositionBefore, 1);
      expect(ben.rankingPositionAfter, 2);
      expect(ben.positionChange, -1);
    },
  );

  test('unchanged and unranked players have no ranking movement', () {
    const unchanged = TournamentRankingPlayerChange(
      playerProfileId: 'anna',
      playerName: 'Anna',
      delta: 0,
      ratingBefore: 900,
      ratingAfter: 900,
      tierBefore: EloTier.silber,
      tierAfter: EloTier.silber,
      enableTiers: false,
      rankingName: 'Vereinsrangliste',
      rankingPositionBefore: 8,
      rankingPositionAfter: 8,
    );
    const unranked = TournamentRankingPlayerChange(
      playerProfileId: 'ben',
      playerName: 'Ben',
      delta: 20,
      ratingBefore: 800,
      ratingAfter: 820,
      tierBefore: EloTier.bronze,
      tierAfter: EloTier.bronze,
      enableTiers: false,
      rankingName: 'Vereinsrangliste',
      rankingPositionBefore: null,
      rankingPositionAfter: null,
    );

    expect(unchanged.hasPositionChange, isFalse);
    expect(unranked.hasPositionChange, isFalse);
  });
}
