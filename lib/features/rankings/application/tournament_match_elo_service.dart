import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../domain/local_elo_calculator.dart';
import '../domain/local_ranking.dart';
import 'local_ranking_elo_service.dart';

class TournamentMatchEloChange {
  const TournamentMatchEloChange({
    required this.rankingName,
    required this.homeDelta,
    required this.awayDelta,
    this.homeRatingBefore,
    this.homeRatingAfter,
    this.awayRatingBefore,
    this.awayRatingAfter,
  });

  final String rankingName;
  final int? homeDelta;
  final int? awayDelta;
  final int? homeRatingBefore;
  final int? homeRatingAfter;
  final int? awayRatingBefore;
  final int? awayRatingAfter;
}

class TournamentMatchEloService {
  TournamentMatchEloService({
    LocalAppDatabase? database,
    TournamentStorage? tournamentStorage,
  }) : _database = database ?? LocalAppDatabase(),
       _tournamentStorage = tournamentStorage;

  final LocalAppDatabase _database;
  final TournamentStorage? _tournamentStorage;

  Future<Map<String, List<TournamentMatchEloChange>>> calculate(
    CreatedTournament tournament,
  ) async {
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return const {};
    }

    final rankings = await _database.loadLocalRankings();
    final selectedRankings = rankings
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              tournament.rankingIds.contains(ranking.id),
        )
        .toList();
    if (selectedRankings.isEmpty) return const {};

    final calculator = const LocalEloCalculator();
    final result = <String, List<TournamentMatchEloChange>>{};
    for (final ranking in selectedRankings) {
      final snapshot = await LocalRankingEloService(
        database: _database,
        tournamentStorage: _tournamentStorage,
      ).calculate(ranking);
      for (final stage in tournament.runStages) {
        final matches = switch (stage) {
          GroupTournamentRunStage() => [
            ...stage.groups.expand((group) => group.matches),
            ...stage.groups.expand(
              (group) => group.knockoutRounds.expand((round) => round),
            ),
            ...stage.groups.expand((group) => group.placementMatches),
          ],
          KnockoutTournamentRunStage() => stage.matches,
          _ => const <GroupMatch>[],
        };
        for (final match in matches) {
          final key = calculator.matchKey(tournament, match);
          if (key == null) continue;
          final delta = snapshot.matchDeltas[key];
          if (delta == null || (delta.home == null && delta.away == null)) {
            continue;
          }
          final matchIndex = int.tryParse(key.split(':').last);
          final homeHistory = matchIndex == null
              ? null
              : snapshot
                    .history[match.homePlayer?.profileId ??
                        match.homePlayer?.name]
                    ?.where(
                      (item) =>
                          item.tournamentId == tournament.id &&
                          item.matchIndex == matchIndex,
                    )
                    .firstOrNull;
          final awayHistory = matchIndex == null
              ? null
              : snapshot
                    .history[match.awayPlayer?.profileId ??
                        match.awayPlayer?.name]
                    ?.where(
                      (item) =>
                          item.tournamentId == tournament.id &&
                          item.matchIndex == matchIndex,
                    )
                    .firstOrNull;
          result
              .putIfAbsent(key, () => [])
              .add(
                TournamentMatchEloChange(
                  rankingName: ranking.name,
                  homeDelta: delta.home,
                  awayDelta: delta.away,
                  homeRatingBefore: homeHistory?.ratingBefore,
                  homeRatingAfter: homeHistory?.ratingAfter,
                  awayRatingBefore: awayHistory?.ratingBefore,
                  awayRatingAfter: awayHistory?.ratingAfter,
                ),
              );
        }
      }
    }
    return result;
  }
}
