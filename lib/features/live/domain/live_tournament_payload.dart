/// Versioned, deliberately slim read model for public spectator pages.
///
/// It contains only tournament progress and anonymised player labels. No
/// rankings, achievements, board assignments, internal settings, hints,
/// audio state, full activity log or historical tournaments are included.
class LiveTournamentPayload {
  const LiveTournamentPayload({
    required this.channel,
    required this.generatedAt,
    required this.tournamentName,
    required this.tournamentDate,
    required this.status,
    required this.formatLines,
    required this.clock,
    required this.players,
    required this.standings,
    required this.bracket,
    required this.matches,
    required this.bestPerformances,
    this.endScreen,
  }) : assert(status == 'running' || status == 'finished');

  static const schemaVersion = 1;

  final String channel;
  final DateTime generatedAt;
  final String tournamentName;
  final DateTime? tournamentDate;
  final String status;
  final List<String> formatLines;
  final LiveTournamentClock clock;
  final List<LiveTournamentPlayer> players;
  final List<LiveStandingGroup> standings;
  final List<LiveBracketRound> bracket;
  final List<LiveMatch> matches;
  final List<LiveBestPerformance> bestPerformances;
  final LiveEndScreen? endScreen;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'channel': channel,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'tournament': {
      'name': tournamentName,
      'date': tournamentDate?.toIso8601String(),
      'status': status,
      'format': formatLines,
      'clock': clock.toJson(),
    },
    'players': [for (final player in players) player.toJson()],
    'standings': [for (final group in standings) group.toJson()],
    'bracket': [for (final round in bracket) round.toJson()],
    'matches': [for (final match in matches) match.toJson()],
    'bestPerformances': [
      for (final performance in bestPerformances) performance.toJson(),
    ],
    if (endScreen != null) 'endScreen': endScreen!.toJson(),
  };
}

class LiveTournamentClock {
  const LiveTournamentClock({
    required this.startedAt,
    required this.forecastEnd,
    required this.elapsedSeconds,
    required this.finishedAt,
  });

  final DateTime? startedAt;
  final DateTime? forecastEnd;
  final int elapsedSeconds;
  final DateTime? finishedAt;

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt?.toIso8601String(),
    'forecastEnd': forecastEnd?.toIso8601String(),
    'elapsedSeconds': elapsedSeconds,
    'finishedAt': finishedAt?.toIso8601String(),
  };
}

class LiveTournamentPlayer {
  const LiveTournamentPlayer({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class LiveStandingGroup {
  const LiveStandingGroup({required this.name, required this.rows});

  final String name;
  final List<LiveStandingRow> rows;

  Map<String, dynamic> toJson() => {
    'name': name,
    'rows': [for (final row in rows) row.toJson()],
  };
}

class LiveStandingRow {
  const LiveStandingRow({
    required this.playerId,
    required this.name,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.points,
  });

  final String playerId;
  final String name;
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int points;

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'name': name,
    'played': played,
    'wins': wins,
    'draws': draws,
    'losses': losses,
    'points': points,
  };
}

class LiveBracketRound {
  const LiveBracketRound({required this.name, required this.matches});

  final String name;
  final List<LiveMatch> matches;

  Map<String, dynamic> toJson() => {
    'name': name,
    'matches': [for (final match in matches) match.toJson()],
  };
}

class LiveMatch {
  const LiveMatch({
    required this.id,
    required this.home,
    required this.away,
    required this.homeLegs,
    required this.awayLegs,
    required this.status,
    required this.label,
  });

  final String id;
  final String home;
  final String away;
  final int? homeLegs;
  final int? awayLegs;
  final String status;
  final String label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'home': home,
    'away': away,
    'homeLegs': homeLegs,
    'awayLegs': awayLegs,
    'status': status,
    'label': label,
  };
}

class LiveBestPerformance {
  const LiveBestPerformance({
    required this.player,
    required this.label,
    required this.value,
    required this.details,
  });

  final String player;
  final String label;
  final int? value;
  final String? details;

  Map<String, dynamic> toJson() => {
    'player': player,
    'label': label,
    if (value != null) 'value': value,
    if (details != null) 'details': details,
  };
}

class LiveEndScreen {
  const LiveEndScreen({
    required this.winner,
    required this.resultLine,
    required this.finishedAt,
  });

  final String? winner;
  final String? resultLine;
  final DateTime? finishedAt;

  Map<String, dynamic> toJson() => {
    'winner': winner,
    'resultLine': resultLine,
    'finishedAt': finishedAt?.toIso8601String(),
  };
}
