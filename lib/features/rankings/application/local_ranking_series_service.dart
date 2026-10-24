import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../domain/local_ranking.dart';

class LocalSeriesEntry {
  const LocalSeriesEntry({
    required this.player,
    required this.points,
    required this.participations,
    required this.setsWon,
    required this.firstPlaces,
    required this.secondPlaces,
    required this.thirdPlaces,
    required this.bestPerformances,
  });

  final PlayerProfile player;
  final int points;
  final int participations;
  final int setsWon;
  final int firstPlaces;
  final int secondPlaces;
  final int thirdPlaces;
  final int bestPerformances;
}

class LocalRankingSeriesService {
  const LocalRankingSeriesService({
    required LocalAppDatabase database,
    TournamentStorage? tournamentStorage,
  }) : _database = database,
       _tournamentStorage = tournamentStorage;

  final LocalAppDatabase _database;
  final TournamentStorage? _tournamentStorage;

  Future<List<LocalSeriesEntry>> calculate(
    LocalRanking ranking, {
    Iterable<CreatedTournament>? tournaments,
  }) async {
    if (ranking.type != RankingType.series) {
      throw ArgumentError.value(
        ranking.type,
        'ranking.type',
        'Not a series ranking',
      );
    }
    final ids = (await _database.loadRankingPlayerIds(ranking.id)).toSet();
    final profiles = await _database.loadPlayerProfiles();
    final counters = {
      for (final player in profiles)
        if (ids.contains(player.id)) player.id: _SeriesCounters(),
    };
    final source =
        tournaments ??
        await (_tournamentStorage ?? TournamentStorage()).loadTournaments();

    for (final tournament in source) {
      if (!tournament.countsForRanking ||
          !tournament.rankingIds.contains(ranking.id) ||
          !ranking.includesTournamentDate(
            (tournament.finishedAt ?? tournament.createdAt).toLocal(),
          )) {
        continue;
      }
      final participants = tournament.players
          .where(
            (player) =>
                player.profileId != null &&
                counters.containsKey(player.profileId),
          )
          .map((player) => player.profileId!)
          .toSet();
      for (final id in participants) {
        counters[id]!.participations++;
      }
      for (final match in _matches(tournament)) {
        if (!match.hasResult) continue;
        final homeId = match.homePlayer?.profileId;
        final awayId = match.awayPlayer?.profileId;
        if (homeId != null && counters.containsKey(homeId)) {
          counters[homeId]!.setsWon += match.homeSets ?? 0;
        }
        if (awayId != null && counters.containsKey(awayId)) {
          counters[awayId]!.setsWon += match.awaySets ?? 0;
        }
        for (final performance in match.bestPerformances) {
          final playerId = performance.playerProfileId;
          if (playerId != null && counters.containsKey(playerId)) {
            counters[playerId]!.bestPerformances++;
          }
        }
      }
      final places = _tournamentPlaces(tournament);
      if (places.isNotEmpty && counters.containsKey(places[0])) {
        counters[places[0]]!.firstPlaces++;
      }
      if (places.length > 1 && counters.containsKey(places[1])) {
        counters[places[1]]!.secondPlaces++;
      }
      if (places.length > 2 && counters.containsKey(places[2])) {
        counters[places[2]]!.thirdPlaces++;
      }
    }

    final entries = [
      for (final player in profiles)
        if (counters[player.id] case final count?)
          LocalSeriesEntry(
            player: player,
            points:
                count.participations * ranking.participationPoints +
                count.setsWon * ranking.setWinPoints +
                count.firstPlaces * ranking.firstPlacePoints +
                count.secondPlaces * ranking.secondPlacePoints +
                count.thirdPlaces * ranking.thirdPlacePoints +
                count.bestPerformances * ranking.bestPerformancePoints,
            participations: count.participations,
            setsWon: count.setsWon,
            firstPlaces: count.firstPlaces,
            secondPlaces: count.secondPlaces,
            thirdPlaces: count.thirdPlaces,
            bestPerformances: count.bestPerformances,
          ),
    ]..sort((a, b) => b.points.compareTo(a.points));
    return entries;
  }

  Iterable<GroupMatch> _matches(CreatedTournament tournament) sync* {
    for (final stage in tournament.runStages) {
      if (stage is KnockoutTournamentRunStage) yield* stage.matches;
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          yield* group.matches;
          yield* group.knockoutRounds.expand((round) => round);
          yield* group.placementMatches;
        }
      }
    }
  }

  Iterable<GroupMatch> _placementMatches(CreatedTournament tournament) sync* {
    for (final stage in tournament.runStages) {
      if (stage is KnockoutTournamentRunStage) yield* stage.placementMatches;
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          yield* group.placementMatches;
        }
      }
    }
  }

  GroupMatch? _finalMatch(CreatedTournament tournament) {
    GroupMatch? result;
    for (final stage in tournament.runStages) {
      if (stage is KnockoutTournamentRunStage && stage.rounds.isNotEmpty) {
        final round = stage.rounds.last;
        if (round.length == 1 && round.single.hasResult) result = round.single;
      }
    }
    return result;
  }

  List<String> _tournamentPlaces(CreatedTournament tournament) {
    final finalMatch = _finalMatch(tournament);
    if (finalMatch != null) {
      final result = <String>[
        ?finalMatch.winner?.profileId,
        ?finalMatch.loser?.profileId,
      ];
      for (final match in _placementMatches(
        tournament,
      ).where((m) => m.placementRank == 3 && m.hasResult)) {
        final id = match.winner?.profileId;
        if (id != null && !result.contains(id)) result.add(id);
      }
      return result;
    }
    final wins = <String, int>{};
    final legsFor = <String, int>{};
    final legDifference = <String, int>{};
    for (final match in _matches(tournament).toSet()) {
      if (!match.hasResult || match.withdrawalIgnored) continue;
      final home = match.homePlayer?.profileId,
          away = match.awayPlayer?.profileId;
      if (home == null || away == null) continue;
      wins.putIfAbsent(home, () => 0);
      wins.putIfAbsent(away, () => 0);
      final winner = match.winner?.profileId;
      if (winner != null) {
        wins.update(winner, (value) => value + 1, ifAbsent: () => 1);
      }
      for (final (player, won, lost) in [
        (home, match.homeLegs ?? 0, match.awayLegs ?? 0),
        (away, match.awayLegs ?? 0, match.homeLegs ?? 0),
      ]) {
        legsFor.update(player, (value) => value + won, ifAbsent: () => won);
        legDifference.update(
          player,
          (value) => value + won - lost,
          ifAbsent: () => won - lost,
        );
      }
    }
    final result = wins.keys.toList()
      ..sort((a, b) {
        final byWins = (wins[b] ?? 0).compareTo(wins[a] ?? 0);
        if (byWins != 0) return byWins;
        final byDifference = (legDifference[b] ?? 0).compareTo(
          legDifference[a] ?? 0,
        );
        return byDifference != 0
            ? byDifference
            : (legsFor[b] ?? 0).compareTo(legsFor[a] ?? 0);
      });
    return result.take(3).toList();
  }
}

class _SeriesCounters {
  int participations = 0;
  int setsWon = 0;
  int firstPlaces = 0;
  int secondPlaces = 0;
  int thirdPlaces = 0;
  int bestPerformances = 0;
}
