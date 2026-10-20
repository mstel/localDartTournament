import '../tournament_models.dart';

class GroupStandingsEngine {
  const GroupStandingsEngine();

  List<PlayerStanding> calculate(
    TournamentGroup group,
    List<String> tieBreakers,
  ) {
    final standings = {
      for (final player in group.players) player.name: PlayerStanding(player),
    };

    for (final match in group.matches.where(
      (match) => match.hasResult && !match.isDecider,
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
      final comparison = compare(a, b, tieBreakers);
      return comparison != 0
          ? comparison
          : a.player.name.compareTo(b.player.name);
    });
    return sorted;
  }

  int compare(
    PlayerStanding first,
    PlayerStanding second,
    List<String> tieBreakers,
  ) {
    for (final rule in tieBreakers) {
      final comparison = switch (rule) {
        'points' => second.points.compareTo(first.points),
        'legDifference' => second.legDifference.compareTo(first.legDifference),
        'legsFor' => second.legsFor.compareTo(first.legsFor),
        _ => 0,
      };
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}
