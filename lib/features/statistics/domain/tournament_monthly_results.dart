import '../../league/application/league_board_runtime.dart';
import '../../tournaments/domain/tournament_models.dart';

/// Match results of one player in one calendar month, derived exclusively
/// from assigned tournaments and their persisted match results.
class TournamentMonthlyResult {
  const TournamentMonthlyResult({
    required this.playerId,
    required this.year,
    required this.month,
    required this.matches,
    required this.wins,
    required this.losses,
    this.weightedLegs = 0,
  });

  final String playerId;
  final int year;
  final int month;
  final int matches;
  final int wins;
  final int losses;

  /// Only used as a weight for recent-form calculations when no manually
  /// recorded performance exists for the same month.
  final int weightedLegs;

  double get winRate => matches == 0 ? 0 : wins * 100 / matches;

  (String, int, int) get key => (playerId, year, month);

  @override
  String toString() =>
      'TournamentMonthlyResult($playerId, $year-$month, '
      'matches: $matches, wins: $wins, losses: $losses)';
}

/// Recomputes monthly match counts from tournaments. Draws count as played
/// matches but neither as wins nor losses, which keeps the win-rate
/// denominator identical to the source results.
class TournamentMonthlyResultCalculator {
  const TournamentMonthlyResultCalculator();

  List<TournamentMonthlyResult> calculate(
    Iterable<CreatedTournament> tournaments, {
    Set<String>? playerIds,
  }) {
    final rows = <(String, int, int), TournamentMonthlyResult>{};
    final unique = {
      for (final tournament in tournaments) tournament.id: tournament,
    };

    for (final tournament in unique.values) {
      if (tournament.leagueMatch == null &&
          tournament.players.any((player) => player.isTeam)) {
        continue;
      }
      final matches = <GroupMatch>{};

      if (tournament.leagueMatch != null) {
        matches.addAll(LeagueBoardRuntime(tournament).matches);
      } else {
        for (final stage in tournament.runStages) {
          if (stage is KnockoutTournamentRunStage) {
            matches.addAll(stage.matches);
          } else if (stage is GroupTournamentRunStage) {
            for (final group in stage.groups) {
              matches.addAll(group.matches);
              matches.addAll(group.knockoutRounds.expand((round) => round));
              matches.addAll(group.placementMatches);
            }
          }
        }
      }

      for (final match in matches) {
        if (!match.hasResult ||
            match.withdrawalIgnored ||
            match.isAnnulled ||
            !match.hasPlayers) {
          continue;
        }
        final homeScore = match.homeScore;
        final awayScore = match.awayScore;
        if (homeScore == null || awayScore == null) continue;

        final date =
            (tournament.tournamentDate ??
                    match.finishedAt ??
                    match.startedAt ??
                    tournament.finishedAt ??
                    tournament.createdAt)
                .toLocal();
        final homeIds = _profileIds(match.homePlayer, playerIds);
        final awayIds = _profileIds(match.awayPlayer, playerIds);
        final homeLegs = (match.homeLegs ?? 0) + (match.awayLegs ?? 0);

        for (final side in [homeIds, awayIds]) {
          for (final playerId in side) {
            // A player must not be credited twice if both entrants carry the
            // same profile (e.g. a stale assignment after a correction).
            if (homeIds.contains(playerId) && awayIds.contains(playerId)) {
              continue;
            }
            final key = (playerId, date.year, date.month);
            final row = rows.putIfAbsent(
              key,
              () => TournamentMonthlyResult(
                playerId: playerId,
                year: date.year,
                month: date.month,
                matches: 0,
                wins: 0,
                losses: 0,
              ),
            );
            final ownScore = identical(side, homeIds) ? homeScore : awayScore;
            final otherScore = identical(side, homeIds) ? awayScore : homeScore;
            final won = ownScore > otherScore;
            final lost = otherScore > ownScore;
            rows[key] = TournamentMonthlyResult(
              playerId: playerId,
              year: date.year,
              month: date.month,
              matches: row.matches + 1,
              wins: row.wins + (won ? 1 : 0),
              losses: row.losses + (lost ? 1 : 0),
              weightedLegs: row.weightedLegs + homeLegs,
            );
          }
        }
      }
    }

    final result = rows.values.toList()
      ..sort((left, right) {
        final byPlayer = left.playerId.compareTo(right.playerId);
        if (byPlayer != 0) return byPlayer;
        final byYear = left.year.compareTo(right.year);
        return byYear != 0 ? byYear : left.month.compareTo(right.month);
      });
    return List.unmodifiable(result);
  }

  Set<String> _profileIds(
    TournamentPlayer? player,
    Set<String>? playerIds,
  ) {
    if (player == null) return const <String>{};
    return {
      for (final individual in player.individuals)
        if (individual.profileId != null &&
            (playerIds == null || playerIds.contains(individual.profileId)))
          individual.profileId!,
    };
  }
}
