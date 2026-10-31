import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/domain/local_ranking.dart';
import '../data/app_database.dart';
import '../domain/tournament_models.dart';

class GroupPlayerRatingService {
  GroupPlayerRatingService({LocalAppDatabase? database})
    : _database = database ?? LocalAppDatabase();

  final LocalAppDatabase _database;

  Future<Map<String, int>> calculate({
    required CreatedTournament tournament,
    required GroupTournamentRunStage stage,
  }) async {
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return const {};
    }

    final rankings = (await _database.loadLocalRankings())
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              tournament.rankingIds.contains(ranking.id),
        )
        .toList();
    final profilesByName = {
      for (final profile in await _database.loadPlayerProfiles())
        profile.displayName.trim().toLowerCase(): profile.id,
    };
    final samplesByProfile = <String, List<int>>{};
    for (final ranking in rankings) {
      final snapshot = await LocalRankingEloService(
        database: _database,
      ).calculate(ranking);
      for (final entry in snapshot.entries) {
        samplesByProfile.putIfAbsent(entry.id, () => []).add(entry.rating);
      }
    }

    final ratings = <String, int>{};
    for (final group in stage.groups) {
      for (final player in group.players) {
        for (final individual in player.individuals) {
          final profileId =
              individual.profileId ??
              profilesByName[individual.name.trim().toLowerCase()];
          if (profileId == null) continue;
          final samples = samplesByProfile[profileId];
          if (samples == null || samples.isEmpty) continue;
          final rating =
              (samples.reduce((sum, value) => sum + value) / samples.length)
                  .round();
          ratings[profileId] = rating;
          ratings[individual.name.toLowerCase()] = rating;
          ratings[individual.name] = rating;
        }
      }
    }
    return Map.unmodifiable(ratings);
  }
}
