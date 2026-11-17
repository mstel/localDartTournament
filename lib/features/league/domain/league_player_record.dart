import 'league_match.dart';

/// A player's win/loss record inside one league or custom friendly match.
///
/// Roster positions are kept so two equally named players from opposing teams
/// remain separate entries.
class LeaguePlayerRecord {
  const LeaguePlayerRecord({
    required this.name,
    required this.teamSide,
    required this.playerIndex,
    required this.matches,
    required this.wins,
    required this.draws,
    required this.losses,
  });

  final String name;
  final int teamSide;
  final int playerIndex;
  final int matches;
  final int wins;
  final int draws;
  final int losses;
}

class _MutableLeaguePlayerRecord {
  _MutableLeaguePlayerRecord(this.name, this.teamSide, this.playerIndex);

  final String name;
  final int teamSide;
  final int playerIndex;
  int matches = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
}

/// Recomputes player records from persisted, completed league fixtures.
///
/// Doubles are counted once per partner. Score comparison uses the configured
/// set/leg format instead of assuming that leg scores are always present.
List<LeaguePlayerRecord> leaguePlayerRecords(LeagueMatch league) {
  final byPosition = <String, _MutableLeaguePlayerRecord>{};

  for (final game in league.games) {
    if (!game.complete) continue;
    final homeScore = game.homeScore(league.gameFormat);
    final awayScore = game.awayScore(league.gameFormat);
    if (homeScore == null || awayScore == null) continue;

    for (var side = 0; side < 2; side++) {
      final roster = side == 0 ? league.homePlayers : league.awayPlayers;
      final positions = side == 0 ? game.home : game.away;
      final ownScore = side == 0 ? homeScore : awayScore;
      final otherScore = side == 0 ? awayScore : homeScore;

      for (final index in positions.toSet()) {
        if (index < 0 || index >= roster.length) continue;
        final key = '$side:$index';
        final record = byPosition.putIfAbsent(
          key,
          () => _MutableLeaguePlayerRecord(roster[index], side, index),
        );
        record.matches++;
        if (ownScore > otherScore) {
          record.wins++;
        } else if (ownScore < otherScore) {
          record.losses++;
        } else {
          record.draws++;
        }
      }
    }
  }

  return byPosition.values
      .map(
        (record) => LeaguePlayerRecord(
          name: record.name,
          teamSide: record.teamSide,
          playerIndex: record.playerIndex,
          matches: record.matches,
          wins: record.wins,
          draws: record.draws,
          losses: record.losses,
        ),
      )
      .toList()
    ..sort((a, b) {
      final byTeam = a.teamSide.compareTo(b.teamSide);
      if (byTeam != 0) return byTeam;
      final byWins = b.wins.compareTo(a.wins);
      if (byWins != 0) return byWins;
      final byLosses = a.losses.compareTo(b.losses);
      if (byLosses != 0) return byLosses;
      return a.name.compareTo(b.name);
    });
}
