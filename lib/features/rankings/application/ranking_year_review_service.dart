import '../../statistics/domain/best_performance.dart';
import '../../statistics/domain/player_monthly_performance.dart';
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
      scores171Plus = 0,
      shortLegs = 0,
      highFinishes = 0,
      bullseyeFinishes = 0;
  double? highestAverage;
  double? highestScoring;
  double? highestCheckoutRate;
}

class RankingMonthlyClubPerformance {
  const RankingMonthlyClubPerformance({
    required this.year,
    required this.month,
    required this.weightedLegs,
    this.matches = 0,
    required this.scoring,
    required this.average,
    required this.checkoutRate,
  });

  final int year;
  final int month;
  final int weightedLegs;
  final int matches;
  final double? scoring;
  final double? average;
  final double? checkoutRate;
}

class RankingYearReview {
  RankingYearReview(
    this.year,
    this.players,
    this.monthlyTournaments,
    this.tournaments, {
    this.yearlyTournaments = const {},
    this.profileIds = const {},
    this.monthlyClubPerformance = const [],
  });
  final int? year;
  final int tournaments;
  final Map<String, RankingYearPlayerStats> players;
  final List<int> monthlyTournaments;
  final Map<int, int> yearlyTournaments;
  final Map<String, String> profileIds;
  final List<RankingMonthlyClubPerformance> monthlyClubPerformance;
  int get totalLegs =>
      players.values.fold(0, (sum, player) => sum + player.legsWon);
  int get totalBestPerformances =>
      players.values.fold(0, (sum, player) => sum + player.bestPerformances);
  int get total180 =>
      players.values.fold(0, (sum, player) => sum + player.scores180);
  int get total170 =>
      players.values.fold(0, (sum, player) => sum + player.scores170);
  int get total171Plus =>
      players.values.fold(0, (sum, player) => sum + player.scores171Plus);
  int get totalShortLegs =>
      players.values.fold(0, (sum, player) => sum + player.shortLegs);
  int get totalHighFinishes =>
      players.values.fold(0, (sum, player) => sum + player.highFinishes);
  int get totalBullseyeFinishes =>
      players.values.fold(0, (sum, player) => sum + player.bullseyeFinishes);
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
    final monthlyPerformance = combineMonthlyPlayerPerformances(
      recorded: await db.loadPlayerMonthlyPerformanceForPlayers(
        roster,
        year: year,
      ),
      imported: await db.loadMonthlyPlayerPerformances(roster, year: year),
    );
    final monthlyClubPerformance = aggregateMonthlyClubPerformance(
      monthlyPerformance,
    );
    for (final performance in monthlyPerformance) {
      final playerStats = stats[performance.playerId];
      if (playerStats == null) continue;
      playerStats.highestAverage = _maximum(
        playerStats.highestAverage,
        performance.average,
      );
      playerStats.highestScoring = _maximum(
        playerStats.highestScoring,
        performance.scoring,
      );
      playerStats.highestCheckoutRate = _maximum(
        playerStats.highestCheckoutRate,
        performance.checkoutRate,
      );
    }
    final monthly = List<int>.filled(12, 0);
    final yearly = <int, int>{};
    var tournamentCount = 0;
    final tournaments = await (tournamentStorage ?? TournamentStorage())
        .loadTournaments();
    for (final tournament in tournaments) {
      final date =
          (tournament.tournamentDate ??
                  tournament.finishedAt ??
                  tournament.createdAt)
              .toLocal();
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
      final matches = _matches(tournament).toSet().toList();
      for (final match in matches) {
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
          switch (performance.normalizedType) {
            case BestPerformanceType.score180:
              player.scores180++;
            case BestPerformanceType.bigFish170:
              player.scores170++;
            case BestPerformanceType.score171Plus ||
                BestPerformanceType.score170:
              player.scores171Plus++;
            case BestPerformanceType.highFinish:
              player.highFinishes++;
            case BestPerformanceType.bullseyeFinish:
              player.bullseyeFinishes++;
            case BestPerformanceType.shortLeg:
              player.shortLegs++;
          }
        }
      }
      final archive = tournament.importedArchive;
      final hasNativeBestPerformances = matches.any(
        (match) => match.bestPerformances.isNotEmpty,
      );
      if (archive != null && !hasNativeBestPerformances) {
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
            switch (performance.normalizedType) {
              case BestPerformanceType.score180:
                player.scores180++;
              case BestPerformanceType.bigFish170:
                player.scores170++;
              case BestPerformanceType.score171Plus ||
                  BestPerformanceType.score170:
                player.scores171Plus++;
              case BestPerformanceType.highFinish:
                player.highFinishes++;
              case BestPerformanceType.bullseyeFinish:
                player.bullseyeFinishes++;
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
      monthlyClubPerformance: monthlyClubPerformance,
    );
  }

  static List<RankingMonthlyClubPerformance> aggregateMonthlyClubPerformance(
    Iterable<PlayerMonthlyPerformance> performances,
  ) {
    final byMonth = <(int, int), List<PlayerMonthlyPerformance>>{};
    for (final performance in performances) {
      if (performance.weightedLegs <= 0 ||
          performance.month < 1 ||
          performance.month > 12) {
        continue;
      }
      byMonth
          .putIfAbsent((performance.year, performance.month), () => [])
          .add(performance);
    }

    double? weightedMean(
      Iterable<PlayerMonthlyPerformance> entries,
      double? Function(PlayerMonthlyPerformance) valueOf,
    ) {
      var weightedTotal = 0.0;
      var totalWeight = 0;
      for (final entry in entries) {
        final value = valueOf(entry);
        if (value == null || entry.weightedLegs <= 0) continue;
        weightedTotal += value * entry.weightedLegs;
        totalWeight += entry.weightedLegs;
      }
      return totalWeight == 0 ? null : weightedTotal / totalWeight;
    }

    final periods = byMonth.keys.toList()
      ..sort((left, right) {
        final yearOrder = left.$1.compareTo(right.$1);
        return yearOrder != 0 ? yearOrder : left.$2.compareTo(right.$2);
      });
    return [
      for (final period in periods)
        if (byMonth[period] case final monthEntries?)
          RankingMonthlyClubPerformance(
            year: period.$1,
            month: period.$2,
            weightedLegs:
                monthEntries.fold<int>(
                  0,
                  (total, entry) => total + entry.weightedLegs,
                ) ~/
                2,
            matches:
                monthEntries.fold<int>(
                  0,
                  (total, entry) => total + entry.matches,
                ) ~/
                2,
            scoring: weightedMean(monthEntries, (entry) => entry.scoring),
            average: weightedMean(monthEntries, (entry) => entry.average),
            checkoutRate: weightedMean(
              monthEntries,
              (entry) => entry.checkoutRate,
            ),
          ),
    ];
  }

  double? _maximum(double? current, double? candidate) {
    if (candidate == null) return current;
    return current == null || candidate > current ? candidate : current;
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
