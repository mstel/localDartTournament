import '../../rankings/domain/local_ranking.dart';
import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/application/local_ranking_series_service.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/tournament_winner.dart';
import '../../league/application/league_board_runtime.dart';
import 'best_performance.dart';

class DirectEncounter {
  const DirectEncounter({
    required this.tournamentName,
    required this.date,
    required this.leftScore,
    required this.rightScore,
  });

  final String tournamentName;
  final DateTime date;
  final int leftScore;
  final int rightScore;
}

class DirectEncounterSummary {
  const DirectEncounterSummary({
    required this.encounters,
    required this.leftWins,
    required this.rightWins,
    required this.draws,
  });

  final List<DirectEncounter> encounters;
  final int leftWins;
  final int rightWins;
  final int draws;
}

class LocalPlayerStatistics {
  const LocalPlayerStatistics({
    required this.tournaments,
    required this.matches,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.tournamentWins,
    required this.legsWon,
    required this.legsLost,
    required this.legsDrawn,
    required this.setsWon,
    required this.setsLost,
    required this.bestPerformances,
  });
  final int tournaments, matches, wins, losses, draws, tournamentWins;
  final int legsWon, legsLost, legsDrawn, setsWon, setsLost;
  final List<BestPerformance> bestPerformances;
  int get legsPlayed => legsWon + legsLost;
  int get setsPlayed => setsWon + setsLost;
  double get matchWinRate => matches == 0 ? 0 : wins * 100 / matches;
  double get tournamentWinRate =>
      tournaments == 0 ? 0 : tournamentWins * 100 / tournaments;
  double get legWinRate =>
      legsWon + legsLost == 0 ? 0 : legsWon * 100 / (legsWon + legsLost);
  double get setWinRate =>
      setsWon + setsLost == 0 ? 0 : setsWon * 100 / (setsWon + setsLost);
}

class LocalStatisticsService {
  const LocalStatisticsService({this.database, this.storage});
  final LocalAppDatabase? database;
  final TournamentStorage? storage;

  Future<DirectEncounterSummary> directEncounters(
    String leftId,
    String rightId,
    Iterable<CreatedTournament> tournaments,
  ) async {
    final profiles = await (database ?? LocalAppDatabase())
        .loadPlayerProfiles();
    final profileByName = {
      for (final profile in profiles)
        profile.displayName.trim().toLowerCase(): profile.id,
    };
    final encounters = <DirectEncounter>[];
    var leftWins = 0;
    var rightWins = 0;
    var draws = 0;
    for (final tournament in tournaments) {
      for (final match in _matches(tournament)) {
        if (!match.hasResult || match.withdrawalIgnored) continue;
        final homeIds = _profileIds(match.homePlayer, profileByName);
        final awayIds = _profileIds(match.awayPlayer, profileByName);
        final leftHome = homeIds.contains(leftId);
        final rightHome = homeIds.contains(rightId);
        final leftAway = awayIds.contains(leftId);
        final rightAway = awayIds.contains(rightId);
        if (!(leftHome && rightAway || leftAway && rightHome)) continue;
        final leftScore = leftHome ? match.homeScore! : match.awayScore!;
        final rightScore = leftHome ? match.awayScore! : match.homeScore!;
        if (leftScore > rightScore) {
          leftWins++;
        } else if (rightScore > leftScore) {
          rightWins++;
        } else {
          draws++;
        }
        encounters.add(
          DirectEncounter(
            tournamentName: tournament.name,
            date:
                (match.finishedAt ??
                        tournament.finishedAt ??
                        tournament.createdAt)
                    .toLocal(),
            leftScore: leftScore,
            rightScore: rightScore,
          ),
        );
      }
    }
    encounters.sort((a, b) => b.date.compareTo(a.date));
    return DirectEncounterSummary(
      encounters: encounters,
      leftWins: leftWins,
      rightWins: rightWins,
      draws: draws,
    );
  }

  Set<String> _profileIds(
    TournamentPlayer? player,
    Map<String, String> profileByName,
  ) {
    if (player == null) return const {};
    return {
      for (final individual in player.individuals)
        if (individual.profileId != null)
          individual.profileId!
        else if (profileByName[individual.name.trim().toLowerCase()] != null)
          profileByName[individual.name.trim().toLowerCase()]!,
    };
  }

  Future<LocalPlayerStatistics> forPlayers(Set<String> ids, {int? year}) async {
    final database = this.database ?? LocalAppDatabase();
    final localProfiles = await database.loadPlayerProfiles();
    final tournaments = await (storage ?? TournamentStorage())
        .loadTournaments();
    return _forPlayers(
      ids,
      year: year,
      localProfiles: localProfiles,
      tournaments: tournaments,
    );
  }

  Future<LocalPlayerStatistics> forPlayersFromTournaments(
    Set<String> ids,
    Iterable<CreatedTournament> tournaments, {
    int? year,
  }) async {
    final localProfiles = await (database ?? LocalAppDatabase())
        .loadPlayerProfiles();
    return _forPlayers(
      ids,
      year: year,
      localProfiles: localProfiles,
      tournaments: tournaments,
    );
  }

  Future<LocalPlayerStatistics> _forPlayers(
    Set<String> ids, {
    required int? year,
    required List<PlayerProfile> localProfiles,
    required Iterable<CreatedTournament> tournaments,
  }) async {
    final profileByName = <String, String>{
      for (final profile in localProfiles)
        profile.displayName.trim().toLowerCase(): profile.id,
    };
    final playedTournamentIds = <String>{};
    var matches = 0, wins = 0, losses = 0, draws = 0, tournamentWins = 0;
    var legsWon = 0, legsLost = 0, legsDrawn = 0, setsWon = 0, setsLost = 0;
    final performances = <BestPerformance>[];
    for (final tournament in tournaments) {
      if (year != null) {
        final tDate = (tournament.finishedAt ?? tournament.createdAt).toLocal();
        if (tDate.year != year) continue;
      }
      if (tournament.players.any(
        (p) => p.profileId != null && ids.contains(p.profileId),
      )) {
        playedTournamentIds.add(tournament.id);
      }
      final winnerId = TournamentWinner.profileId(tournament);
      if (winnerId != null && ids.contains(winnerId)) {
        tournamentWins++;
      }
      for (final match in _matches(tournament)) {
        if (!match.hasResult || match.withdrawalIgnored) continue;
        final home = match.homePlayer?.profileId;
        final away = match.awayPlayer?.profileId;
        final homeIn = home != null && ids.contains(home);
        final awayIn = away != null && ids.contains(away);
        if (homeIn == awayIn) continue;
        matches++;
        final isHome = homeIn;
        if (match.homeScore == match.awayScore) {
          draws++;
        } else if ((isHome && match.homeScore! > match.awayScore!) ||
            (!isHome && match.awayScore! > match.homeScore!)) {
          wins++;
        } else {
          losses++;
        }
        legsWon += isHome ? match.homeLegs ?? 0 : match.awayLegs ?? 0;
        legsLost += isHome ? match.awayLegs ?? 0 : match.homeLegs ?? 0;
        if (match.homeLegs == match.awayLegs) legsDrawn++;
        setsWon += isHome ? match.homeSets ?? 0 : match.awaySets ?? 0;
        setsLost += isHome ? match.awaySets ?? 0 : match.homeSets ?? 0;
        performances.addAll(
          match.bestPerformances.where(
            (p) =>
                (p.playerProfileId != null &&
                    ids.contains(p.playerProfileId)) ||
                (p.playerProfileId == null &&
                    (isHome
                            ? match.homePlayer?.name
                            : match.awayPlayer?.name) ==
                        p.playerName),
          ),
        );
      }
      final archive = tournament.importedArchive;
      if (archive != null) {
        final profileByChallongeId = <String, String>{
          for (final participant in archive.participants)
            if (participant['profileId'] is String)
              '${participant['id']}': participant['profileId'] as String,
          for (final participant in archive.participants)
            if (participant['profileId'] is String)
              for (final alias
                  in participant['groupPlayerIds'] as List? ?? const [])
                '$alias': participant['profileId'] as String,
        };
        final nameByChallongeId = <String, String>{
          for (final participant in archive.participants)
            '${participant['id']}': '${participant['name'] ?? ''}',
          for (final participant in archive.participants)
            for (final alias
                in participant['groupPlayerIds'] as List? ?? const [])
              '$alias': '${participant['name'] ?? ''}',
        };
        for (final importedMatch in archive.matches) {
          final rawPerformances =
              importedMatch['bestPerformances'] as List? ?? const [];
          final challongeIds = [
            '${importedMatch['player1_id']}',
            '${importedMatch['player2_id']}',
          ];
          for (final raw in rawPerformances.whereType<Map>()) {
            final performance = BestPerformance.fromJson(
              Map<String, dynamic>.from(raw),
            );
            final matchingProfileIds = challongeIds
                .where((id) => nameByChallongeId[id] == performance.playerName)
                .map((id) => profileByChallongeId[id])
                .whereType<String>()
                .toList();
            final profileId =
                performance.playerProfileId ??
                (matchingProfileIds.isEmpty
                    ? profileByName[performance.playerName.trim().toLowerCase()]
                    : matchingProfileIds.first);
            if (profileId != null && ids.contains(profileId)) {
              performances.add(performance);
            }
          }
        }
      }
    }
    return LocalPlayerStatistics(
      tournaments: playedTournamentIds.length,
      matches: matches,
      wins: wins,
      losses: losses,
      draws: draws,
      tournamentWins: tournamentWins,
      legsWon: legsWon,
      legsLost: legsLost,
      legsDrawn: legsDrawn,
      setsWon: setsWon,
      setsLost: setsLost,
      bestPerformances: performances,
    );
  }

  Future<List<LocalRanking>> rankingsFor(Set<String> playerIds) async {
    if (playerIds.isEmpty) return const [];
    return (database ?? LocalAppDatabase()).loadRankingsForPlayer(
      playerIds.first,
    );
  }

  /// Returns the position of [playerIds] in each of their rankings.
  /// Position is 1-based (Platz 1 = Platz 1 von N).
  Future<List<RankingPosition>> rankingPositionsFor(
    Set<String> playerIds,
    List<LocalRanking> rankings,
  ) async {
    if (playerIds.isEmpty || rankings.isEmpty) return const [];
    final db = database ?? LocalAppDatabase();
    final result = <RankingPosition>[];
    for (final ranking in rankings) {
      try {
        if (ranking.type == RankingType.elo) {
          final snapshot = await LocalRankingEloService(
            database: db,
          ).calculate(ranking);
          final sorted = snapshot.entries; // already sorted by rating desc
          final pos = sorted.indexWhere((e) => playerIds.contains(e.id));
          if (pos >= 0) {
            result.add(
              RankingPosition(
                ranking: ranking,
                position: pos + 1,
                total: sorted.length,
              ),
            );
          }
        } else {
          // Series ranking – reuse LocalRankingSeriesService
          final entries = await LocalRankingSeriesService(
            database: db,
          ).calculate(ranking);
          final pos = entries.indexWhere(
            (e) => playerIds.contains(e.player.id),
          );
          if (pos >= 0) {
            result.add(
              RankingPosition(
                ranking: ranking,
                position: pos + 1,
                total: entries.length,
              ),
            );
          }
        }
      } catch (_) {
        // Skip ranking if calculation fails (e.g. wrong type)
      }
    }
    return result;
  }

  Iterable<GroupMatch> _matches(CreatedTournament tournament) sync* {
    if (tournament.leagueMatch != null) {
      yield* LeagueBoardRuntime(tournament).matches;
      return;
    }
    for (final stage in tournament.runStages) {
      if (stage is KnockoutTournamentRunStage) {
        yield* stage.matches;
      } else if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          yield* group.matches;
          yield* group.knockoutRounds.expand((round) => round);
          yield* group.placementMatches;
        }
      }
    }
  }
}

/// A player's position in a specific ranking.
class RankingPosition {
  const RankingPosition({
    required this.ranking,
    required this.position,
    required this.total,
  });
  final LocalRanking ranking;
  final int position;
  final int total;
}
