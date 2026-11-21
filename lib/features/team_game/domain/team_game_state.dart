import 'dart:convert';
import 'dart:math' as math;

enum TeamGameStatus { setup, running, finished }

enum TeamGameWinner { home, away }

extension TeamGameStatusWire on TeamGameStatus {
  String get wireName => switch (this) {
    TeamGameStatus.setup => 'setup',
    TeamGameStatus.running => 'running',
    TeamGameStatus.finished => 'finished',
  };
}

extension TeamGameWinnerWire on TeamGameWinner {
  String get wireName => switch (this) {
    TeamGameWinner.home => 'home',
    TeamGameWinner.away => 'away',
  };
}

extension TeamGameWinnerLabel on TeamGameWinner {
  String labelFor(TeamGameState state) => switch (this) {
    TeamGameWinner.home => state.home.teamName,
    TeamGameWinner.away => state.away.teamName,
  };
}

class TeamGameSide {
  const TeamGameSide({required this.teamName, required this.players});

  final String teamName;
  final List<String> players;

  TeamGameSide normalized() => TeamGameSide(
    teamName: teamName.trim(),
    players: [
      for (final player in players)
        if (player.trim().isNotEmpty) player.trim(),
    ],
  );

  Map<String, dynamic> toJson() => {
    'teamName': teamName,
    'players': players,
  };

  factory TeamGameSide.fromJson(Object? value) {
    if (value is! Map) {
      return const TeamGameSide(teamName: '', players: []);
    }
    return TeamGameSide(
      teamName: value['teamName']?.toString() ?? '',
      players: [
        for (final player in (value['players'] as List? ?? const []))
          player.toString(),
      ],
    );
  }
}

class TeamGameTurn {
  const TeamGameTurn({
    required this.index,
    required this.player,
    required this.teamName,
    required this.isHome,
  });

  final int index;
  final String player;
  final String teamName;
  final bool isHome;

  String get identity => '$isHome:$index:$player';
}

/// Versionierter, reiner Zustand des casual "Team Game"-Modus.
///
/// Es werden bewusst keine Ergebnisse oder Punkte gespeichert. Der Zustand
/// dient ausschließlich der Synchronisation zwischen Hauptmonitor und
/// Zweitmonitor.
class TeamGameState {
  static const schemaVersion = 1;

  const TeamGameState({
    required this.id,
    required this.home,
    required this.away,
    this.currentIndex = 0,
    this.status = TeamGameStatus.setup,
    this.winner,
    required this.updatedAt,
  });

  factory TeamGameState.create({
    required String homeTeam,
    required List<String> homePlayers,
    required String awayTeam,
    required List<String> awayPlayers,
    String? id,
    DateTime? updatedAt,
  }) {
    return TeamGameState(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      home: TeamGameSide(teamName: homeTeam, players: homePlayers).normalized(),
      away: TeamGameSide(teamName: awayTeam, players: awayPlayers).normalized(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  final String id;
  final TeamGameSide home;
  final TeamGameSide away;
  final int currentIndex;
  final TeamGameStatus status;
  final TeamGameWinner? winner;
  final DateTime updatedAt;

  bool get isFinished => status == TeamGameStatus.finished;
  bool get hasPlayers => home.players.isNotEmpty && away.players.isNotEmpty;

  /// Berechnet den Spieler für einen beliebigen Wechsel, ohne eine feste
  /// Rundenzahl anzunehmen. Heim und Gast rotieren unabhängig voneinander
  /// durch ihre Kader: nach dem letzten Spieler eines Teams beginnt dieses
  /// Team wieder beim ersten Spieler.
  TeamGameTurn? turnAt(int index) {
    final homePlayers = home.players;
    final awayPlayers = away.players;
    if (homePlayers.isEmpty || awayPlayers.isEmpty) return null;

    final step = index < 0 ? 0 : index;
    final isHome = step.isEven;
    final players = isHome ? homePlayers : awayPlayers;
    final rotations = step ~/ 2;

    return TeamGameTurn(
      index: step,
      player: players[rotations % players.length],
      teamName: isHome ? home.teamName : away.teamName,
      isHome: isHome,
    );
  }

  TeamGameTurn? get currentTurn => turnAt(currentIndex);

  String? get winningTeamName => winner?.labelFor(this);

  bool get canGoNext => currentTurn != null;

  bool get canGoBack => currentTurn != null && currentIndex > 0;

  TeamGameState prepared() => TeamGameState(
    id: id,
    home: home,
    away: away,
    currentIndex: 0,
    status: TeamGameStatus.setup,
    winner: null,
    updatedAt: DateTime.now(),
  );

  TeamGameState started() => TeamGameState(
    id: id,
    home: home,
    away: away,
    currentIndex: 0,
    status: TeamGameStatus.running,
    winner: null,
    updatedAt: DateTime.now(),
  );

  TeamGameState next() {
    if (currentTurn == null) return this;
    return TeamGameState(
      id: id,
      home: home,
      away: away,
      currentIndex: currentIndex + 1,
      status: status,
      winner: winner,
      updatedAt: DateTime.now(),
    );
  }

  TeamGameState previous() {
    if (currentTurn == null || currentIndex <= 0) return this;
    return TeamGameState(
      id: id,
      home: home,
      away: away,
      currentIndex: math.max(0, currentIndex - 1),
      status: status,
      winner: winner,
      updatedAt: DateTime.now(),
    );
  }

  TeamGameState finished(TeamGameWinner result) => TeamGameState(
    id: id,
    home: home,
    away: away,
    currentIndex: currentIndex,
    status: TeamGameStatus.finished,
    winner: result,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'homeTeam': home.teamName,
    'homePlayers': home.players,
    'awayTeam': away.teamName,
    'awayPlayers': away.players,
    'currentIndex': currentIndex,
    'status': status.wireName,
    'winner': winner?.wireName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  String toJsonString() => jsonEncode(toJson());

  factory TeamGameState.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Team-Game-Signal ist kein Objekt.');
    }
    final version = value['schemaVersion'] as int? ?? 1;
    if (version > schemaVersion) {
      throw FormatException(
        'Team-Game-Signal hat die unbekannte Version $version.',
      );
    }
    return TeamGameState(
      id: value['id']?.toString() ?? '',
      home: TeamGameSide(
        teamName: value['homeTeam']?.toString() ?? '',
        players: [
          for (final player in (value['homePlayers'] as List? ?? const []))
            player.toString(),
        ],
      ),
      away: TeamGameSide(
        teamName: value['awayTeam']?.toString() ?? '',
        players: [
          for (final player in (value['awayPlayers'] as List? ?? const []))
            player.toString(),
        ],
      ),
      currentIndex: value['currentIndex'] as int? ?? 0,
      status: _statusFromJson(value['status']),
      winner: _winnerFromJson(value['winner']),
      updatedAt: _dateTimeFromJson(value['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory TeamGameState.fromJsonString(String source) =>
      TeamGameState.fromJson(jsonDecode(source));
}

TeamGameStatus _statusFromJson(Object? value) => switch (value) {
  'running' => TeamGameStatus.running,
  'finished' => TeamGameStatus.finished,
  _ => TeamGameStatus.setup,
};

TeamGameWinner? _winnerFromJson(Object? value) => switch (value) {
  'home' => TeamGameWinner.home,
  'away' => TeamGameWinner.away,
  _ => null,
};

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
