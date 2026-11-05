import '../../tournaments/domain/tournament_models.dart';
import 'statistics_period.dart';
import 'league_statistics_entries.dart';

class TournamentPlayerStatistics {
  TournamentPlayerStatistics(this.id, this.name);
  final String id, name;
  int matches = 0,
      wins = 0,
      draws = 0,
      losses = 0,
      legsFor = 0,
      legsAgainst = 0,
      setsFor = 0,
      setsAgainst = 0;
  final Set<String> tournaments = {};
}

/// Recomputed from persisted results: corrections and repeated loads cannot
/// inflate counters. No averages are invented from leg-only tournament scores.
class TournamentStatisticsCalculator {
  const TournamentStatisticsCalculator();
  List<TournamentPlayerStatistics> calculate(
    Iterable<CreatedTournament> tournaments, {
    Map<String, String> aliases = const {},
    StatisticsPeriod? period,
  }) {
    final rows = <String, TournamentPlayerStatistics>{};
    final unique = {
      for (final tournament in tournaments) tournament.id: tournament,
    };
    for (final tournament in unique.values) {
      if (period == null ||
          period.contains(tournament.tournamentDate ?? tournament.createdAt)) {
        for (final entry in leagueStatisticsEntries(tournament)) {
          final id = aliases[entry.id] ?? entry.id;
          final row = rows.putIfAbsent(
            id,
            () => TournamentPlayerStatistics(id, entry.name),
          );
          row.tournaments.add(tournament.id);
          row.matches++;
          final won = entry.ownLegs > entry.otherLegs;
          if (won) {
            row.wins++;
          } else {
            row.losses++;
          }
          row.legsFor += entry.ownLegs;
          row.legsAgainst += entry.otherLegs;
        }
      }
      for (final stage in tournament.runStages) {
        final matches = <GroupMatch>{};
        if (stage is KnockoutTournamentRunStage) matches.addAll(stage.matches);
        if (stage is GroupTournamentRunStage) {
          for (final group in stage.groups) {
            matches.addAll(group.matches);
            matches.addAll(group.placementMatches);
          }
        }
        for (final match in matches) {
          if (period != null &&
              !period.contains(
                tournament.tournamentDate ??
                    match.finishedAt ??
                    match.startedAt ??
                    tournament.createdAt,
              )) {
            continue;
          }
          if (!match.countsForStatistics ||
              match.isAnnulled ||
              !match.hasPlayers) {
            continue;
          }
          final players = [match.homePlayer!, match.awayPlayer!];
          for (var i = 0; i < 2; i++) {
            final player = players[i];
            // Names alone must never attach results to an authenticated profile.
            final rawId =
                player.profileId ?? 'unlinked:${tournament.id}:${player.name}';
            final id = aliases[rawId] ?? rawId;
            final row = rows.putIfAbsent(
              id,
              () => TournamentPlayerStatistics(id, player.name),
            );
            row.tournaments.add(tournament.id);
            row.matches++;
            final own = i == 0 ? match.homeScore! : match.awayScore!;
            final other = i == 0 ? match.awayScore! : match.homeScore!;
            if (own > other) {
              row.wins++;
            } else if (own == other) {
              row.draws++;
            } else {
              row.losses++;
            }
            row.legsFor += (i == 0 ? match.homeLegs : match.awayLegs) ?? 0;
            row.legsAgainst += (i == 0 ? match.awayLegs : match.homeLegs) ?? 0;
            row.setsFor += (i == 0 ? match.homeSets : match.awaySets) ?? 0;
            row.setsAgainst += (i == 0 ? match.awaySets : match.homeSets) ?? 0;
          }
        }
      }
    }
    return rows.values.toList()..sort((a, b) => b.wins.compareTo(a.wins));
  }
}
