import '../../statistics/domain/best_performance.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/tournament_winner.dart';
import '../domain/local_ranking.dart';

class RankingYearPlayerStats {
  int participations = 0, tournamentWins = 0, legsWon = 0, legsLost = 0;
  int bestPerformances = 0,
      scores180 = 0,
      scores170 = 0,
      shortLegs = 0,
      highFinishes = 0;
}

class RankingYearReview {
  RankingYearReview(
    this.year,
    this.players,
    this.monthlyTournaments,
    this.tournaments, {
    this.yearlyTournaments = const {},
    this.profileIds = const {},
  });
  final int? year;
  final int tournaments;
  final Map<String, RankingYearPlayerStats> players;
  final List<int> monthlyTournaments;
  final Map<int, int> yearlyTournaments;
  final Map<String, String> profileIds;
  int get totalLegs =>
      players.values.fold(0, (sum, player) => sum + player.legsWon);
  int get totalBestPerformances =>
      players.values.fold(0, (sum, player) => sum + player.bestPerformances);
  int get total180 =>
      players.values.fold(0, (sum, player) => sum + player.scores180);
  int get total170 =>
      players.values.fold(0, (sum, player) => sum + player.scores170);
  int get totalShortLegs =>
      players.values.fold(0, (sum, player) => sum + player.shortLegs);
  int get totalHighFinishes =>
      players.values.fold(0, (sum, player) => sum + player.highFinishes);
}

class RankingYearReviewService {
  const RankingYearReviewService({this.database, this.tournamentStorage});
  final LocalAppDatabase? database;
  final TournamentStorage? tournamentStorage;

  Future<RankingYearReview> calculate(LocalRanking ranking, int? year) async {
    final db = database ?? LocalAppDatabase();
    final roster = (await db.loadRankingPlayerIds(ranking.id)).toSet();
    final names = {
      for (final player in await db.loadPlayerProfiles())
        player.id: player.displayName,
    };
    final profileIdByName = {
      for (final entry in names.entries)
        entry.value.trim().toLowerCase(): entry.key,
    };
    final stats = {for (final id in roster) id: RankingYearPlayerStats()};
    final monthly = List<int>.filled(12, 0);
    final yearly = <int, int>{};
    var tournamentCount = 0;
    final tournaments = await (tournamentStorage ?? TournamentStorage())
        .loadTournaments();
    for (final tournament in tournaments) {
      final date = (tournament.finishedAt ?? tournament.createdAt).toLocal();
      if (year != null && date.year != year) continue;
      if (!ranking.includesTournamentDate(date) ||
          !tournament.countsForRanking ||
          !tournament.rankingIds.contains(ranking.id)) {
        continue;
      }
      tournamentCount++;
      monthly[date.month - 1]++;
      yearly.update(date.year, (v) => v + 1, ifAbsent: () => 1);
      final participants = tournament.players
          .where((p) => p.profileId != null && stats.containsKey(p.profileId))
          .map((p) => p.profileId!)
          .toSet();
      for (final id in participants) {
        stats[id]!.participations++;
      }
      for (final match in _matches(tournament).toSet()) {
        if (!match.hasResult || match.withdrawalIgnored) continue;
        final home = match.homePlayer?.profileId,
            away = match.awayPlayer?.profileId;
        if (home == null ||
            away == null ||
            !stats.containsKey(home) ||
            !stats.containsKey(away)) {
          continue;
        }
        stats[home]!.legsWon += match.homeLegs ?? 0;
        stats[home]!.legsLost += match.awayLegs ?? 0;
        stats[away]!.legsWon += match.awayLegs ?? 0;
        stats[away]!.legsLost += match.homeLegs ?? 0;
        for (final performance in match.bestPerformances) {
          final id = performance.playerProfileId;
          if (id == null || !stats.containsKey(id)) continue;
          final player = stats[id]!;
          player.bestPerformances++;
          switch (performance.type) {
            case BestPerformanceType.score180:
              player.scores180++;
            case BestPerformanceType.score170:
              player.scores170++;
            case BestPerformanceType.highFinish:
              player.highFinishes++;
            case BestPerformanceType.shortLeg:
              player.shortLegs++;
          }
        }
      }
      final archive = tournament.importedArchive;
      if (archive != null) {
        final byName = <String, String>{};
        for (final participant in archive.participants) {
          final id = participant['profileId'];
          if (id is! String || !stats.containsKey(id)) continue;
          byName['${participant['name'] ?? ''}'] = id;
          for (final alias
              in participant['groupPlayerIds'] as List? ?? const []) {
            byName['$alias'] = id;
          }
        }
        for (final importedMatch in archive.matches) {
          for (final raw
              in (importedMatch['bestPerformances'] as List? ?? const [])
                  .whereType<Map>()) {
            final performance = BestPerformance.fromJson(
              Map<String, dynamic>.from(raw),
            );
            final id =
                performance.playerProfileId ??
                byName[performance.playerName] ??
                profileIdByName[performance.playerName.trim().toLowerCase()];
            if (id == null || !stats.containsKey(id)) continue;
            final player = stats[id]!;
            player.bestPerformances++;
            switch (performance.type) {
              case BestPerformanceType.score180:
                player.scores180++;
              case BestPerformanceType.score170:
                player.scores170++;
              case BestPerformanceType.highFinish:
                player.highFinishes++;
              case BestPerformanceType.shortLeg:
                player.shortLegs++;
            }
          }
        }
      }
      final winnerId = TournamentWinner.profileId(tournament);
      if (winnerId != null && stats.containsKey(winnerId)) {
        stats[winnerId]!.tournamentWins++;
      }
    }
    final mappedProfileIds = <String, String>{};
    for (final entry in stats.entries) {
      final playerName = names[entry.key] ?? entry.key;
      mappedProfileIds[playerName] = entry.key;
    }
    return RankingYearReview(
      year,
      {
        for (final entry in stats.entries)
          names[entry.key] ?? entry.key: entry.value,
      },
      monthly,
      tournamentCount,
      yearlyTournaments: yearly,
      profileIds: mappedProfileIds,
    );
  }

  Iterable<GroupMatch> _matches(CreatedTournament tournament) sync* {
    for (final stage in tournament.runStages) {
      if (stage is KnockoutTournamentRunStage) {
        yield* stage.matches;
        yield* stage.placementMatches;
      }
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          yield* group.matches;
          yield* group.knockoutRounds.expand((round) => round);
          yield* group.placementMatches;
        }
      }
    }
  }
}
