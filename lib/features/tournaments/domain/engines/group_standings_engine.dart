import '../tournament_models.dart';
import '../../application/player_withdrawal_service.dart';
import '../../modes/swiss/swiss_engine.dart';

class GroupStandingsEngine {
  const GroupStandingsEngine();

  List<PlayerStanding> calculate(
    TournamentGroup group,
    List<String> tieBreakers, {
    CreatedTournament? tournament,
  }) {
    if (group.playType == 'swiss') {
      final rows = SwissEngine.standings(group);
      if (tournament == null) return rows;
      return [
        ...rows.where(
          (row) =>
              PlayerWithdrawalService.policy(tournament, row.player) == null,
        ),
        ...rows.where(
          (row) =>
              PlayerWithdrawalService.policy(tournament, row.player) != null,
        ),
      ];
    }
    final standings = {
      for (final player in group.players) player.name: PlayerStanding(player),
    };

    for (final match in group.matches.where(
      (match) => match.countsForStatistics && !match.isDecider,
    )) {
      final homePlayer = match.homePlayer;
      final awayPlayer = match.awayPlayer;
      if (homePlayer == null || awayPlayer == null) continue;
      final home = standings[homePlayer.name];
      final away = standings[awayPlayer.name];
      if (home == null || away == null) continue;
      final homeLegs = match.homeLegs ?? 0;
      final awayLegs = match.awayLegs ?? 0;

      home.played++;
      home.legsFor += homeLegs;
      home.legsAgainst += awayLegs;
      away.played++;
      away.legsFor += awayLegs;
      away.legsAgainst += homeLegs;

      if (match.winner == homePlayer) {
        home.wins++;
        home.points += 3;
        away.losses++;
      } else if (match.winner == awayPlayer) {
        away.wins++;
        away.points += 3;
        home.losses++;
      } else {
        home.draws++;
        home.points++;
        away.draws++;
        away.points++;
      }
    }

    final sorted = standings.values.toList();
    sorted.sort((a, b) {
      if (tournament != null) {
        final withdrawalOrder =
            (PlayerWithdrawalService.policy(tournament, a.player) == null
                    ? 0
                    : 1)
                .compareTo(
                  PlayerWithdrawalService.policy(tournament, b.player) == null
                      ? 0
                      : 1,
                );
        if (withdrawalOrder != 0) return withdrawalOrder;
      }
      final comparison = compare(a, b, tieBreakers, matches: group.matches);
      return comparison != 0
          ? comparison
          : a.player.name.compareTo(b.player.name);
    });
    return sorted;
  }

  int compare(
    PlayerStanding first,
    PlayerStanding second,
    List<String> tieBreakers, {
    List<GroupMatch> matches = const [],
  }) {
    for (final rule in tieBreakers) {
      final comparison = switch (rule) {
        'points' => second.points.compareTo(first.points),
        'legDifference' => second.legDifference.compareTo(first.legDifference),
        'legsFor' => second.legsFor.compareTo(first.legsFor),
        'headToHead' => _compareHeadToHead(first, second, matches),
        _ => 0,
      };
      if (comparison != 0) return comparison;
    }
    return _compareDecider(first, second, matches);
  }

  int _compareHeadToHead(
    PlayerStanding first,
    PlayerStanding second,
    List<GroupMatch> matches,
  ) {
    var firstPoints = 0;
    var secondPoints = 0;
    var firstLegs = 0;
    var secondLegs = 0;

    for (final match in matches.where(
      (match) => match.countsForStatistics && !match.isDecider,
    )) {
      final home = match.homePlayer;
      final away = match.awayPlayer;
      if (home == null || away == null) continue;
      final isDirectMatch =
          (home.name == first.player.name && away.name == second.player.name) ||
          (home.name == second.player.name && away.name == first.player.name);
      if (!isDirectMatch) continue;

      final firstIsHome = home.name == first.player.name;
      final firstMatchLegs = firstIsHome ? match.homeLegs! : match.awayLegs!;
      final secondMatchLegs = firstIsHome ? match.awayLegs! : match.homeLegs!;
      firstLegs += firstMatchLegs;
      secondLegs += secondMatchLegs;

      if (match.winner?.name == first.player.name) {
        firstPoints += 3;
      } else if (match.winner?.name == second.player.name) {
        secondPoints += 3;
      } else {
        firstPoints++;
        secondPoints++;
      }
    }

    final points = secondPoints.compareTo(firstPoints);
    if (points != 0) return points;
    final difference = (secondLegs - firstLegs).compareTo(
      firstLegs - secondLegs,
    );
    if (difference != 0) return difference;
    return secondLegs.compareTo(firstLegs);
  }

  int _compareDecider(
    PlayerStanding first,
    PlayerStanding second,
    List<GroupMatch> matches,
  ) {
    for (final match in matches.where(
      (match) => match.isDecider && match.hasResult,
    )) {
      final home = match.homePlayer;
      final away = match.awayPlayer;
      if (home == null || away == null || match.winner == null) continue;
      final direct =
          (home.name == first.player.name && away.name == second.player.name) ||
          (home.name == second.player.name && away.name == first.player.name);
      if (direct) return match.winner!.name == first.player.name ? -1 : 1;
    }
    return 0;
  }
}
