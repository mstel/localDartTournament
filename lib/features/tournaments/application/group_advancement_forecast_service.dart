import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../rankings/domain/local_ranking.dart';
import '../data/app_database.dart';
import '../domain/engines/group_advancement_forecast_engine.dart';
import '../domain/tournament_models.dart';

class GroupAdvancementForecastService {
  GroupAdvancementForecastService({
    LocalAppDatabase? database,
    this.simulations = 3000,
  }) : _database = database ?? LocalAppDatabase();

  final LocalAppDatabase _database;
  final int simulations;

  Future<Map<String, AdvancementChance>> calculate({
    required CreatedTournament tournament,
    required GroupTournamentRunStage stage,
  }) async {
    final rankings = (await _database.loadLocalRankings())
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              (tournament.rankingIds.isEmpty ||
                  tournament.rankingIds.contains(ranking.id)),
        )
        .toList();
    final ratings = <String, List<int>>{};
    final wins = <String, int>{};
    final matches = <String, int>{};
    final profileByName = {
      for (final profile in await _database.loadPlayerProfiles())
        profile.displayName.trim().toLowerCase(): profile.id,
    };

    for (final ranking in rankings) {
      final snapshot = await LocalRankingEloService(
        database: _database,
      ).calculate(ranking);
      for (final entry in snapshot.entries) {
        ratings.putIfAbsent(entry.id, () => []).add(entry.rating);
        wins.update(
          entry.id,
          (value) => value + entry.wins,
          ifAbsent: () => entry.wins,
        );
        matches.update(
          entry.id,
          (value) => value + entry.matches,
          ifAbsent: () => entry.matches,
        );
      }
    }

    final playerData = <String, GroupAdvancementPlayerData>{};
    for (final group in stage.groups) {
      for (final player in group.players) {
        final key = player.profileId ?? player.name;
        final id =
            player.profileId ?? profileByName[player.name.trim().toLowerCase()];
        if (id == null) continue;
        final samples = ratings[id];
        final rating = samples == null || samples.isEmpty
            ? defaultEloRating
            : (samples.reduce((sum, value) => sum + value) / samples.length)
                  .round();
        final matchCount = matches[id] ?? 0;
        playerData[key] = GroupAdvancementPlayerData(
          rating: rating,
          historicalWinRate: matchCount == 0
              ? 0.5
              : (wins[id] ?? 0) / matchCount,
        );
      }
    }
    return const GroupAdvancementForecastEngine().calculate(
      stage: stage,
      players: playerData,
      simulations: simulations,
      seed: _seed(tournament.id, stage.name),
    );
  }

  int _seed(String tournamentId, String stageName) {
    var result = 17;
    for (final character in '$tournamentId:$stageName'.codeUnits) {
      result = (result * 31 + character) & 0x7fffffff;
    }
    return result;
  }
}
