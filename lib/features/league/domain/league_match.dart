import '../../tournaments/domain/tournament_models.dart';

class LeagueGame {
  LeagueGame({
    required this.home,
    required this.away,
    this.homeLegs,
    this.awayLegs,
    this.homeSets,
    this.awaySets,
    this.runtime,
  });
  List<int> home;
  List<int> away;
  int? homeLegs;
  int? awayLegs;
  int? homeSets;
  int? awaySets;
  Map<String, dynamic>? runtime;
  bool get isDouble => home.length == 2;
  bool get complete =>
      homeLegs != null && awayLegs != null ||
      homeSets != null && awaySets != null;

  int? homeScore(TournamentGameFormat format) =>
      format.bestOfSets > 1 ? homeSets : homeLegs;

  int? awayScore(TournamentGameFormat format) =>
      format.bestOfSets > 1 ? awaySets : awayLegs;

  void score(
    int? home,
    int? away, {
    TournamentGameFormat format = const TournamentGameFormat(bestOfLegs: 5),
    int? legsHome,
    int? legsAway,
  }) {
    if (home == null && away == null) {
      homeLegs = awayLegs = homeSets = awaySets = null;
      return;
    }
    final target = format.bestOfSets > 1
        ? format.bestOfSets ~/ 2 + 1
        : format.bestOfLegs ~/ 2 + 1;
    final validScore =
        home != null &&
        away != null &&
        home >= 0 &&
        away >= 0 &&
        (format.allowsDraws
            ? home == format.bestOfLegs ~/ 2 && away == format.bestOfLegs ~/ 2
            : (home == target && away < target) ||
                  (away == target && home < target));
    if (!validScore) {
      throw const FormatException(
        'Das Ergebnis passt nicht zum ausgewählten Spielformat.',
      );
    }
    if (format.bestOfSets > 1) {
      homeSets = home;
      awaySets = away;
      homeLegs = legsHome;
      awayLegs = legsAway;
    } else {
      homeLegs = home;
      awayLegs = away;
      homeSets = awaySets = null;
    }
  }

  Map<String, dynamic> toJson() => {
    'home': home,
    'away': away,
    'homeLegs': homeLegs,
    'awayLegs': awayLegs,
    'homeSets': homeSets,
    'awaySets': awaySets,
    if (runtime != null) 'runtime': runtime,
  };
  factory LeagueGame.fromJson(
    Map<String, dynamic> json, {
    TournamentGameFormat format = const TournamentGameFormat(bestOfLegs: 5),
  }) {
    final game = LeagueGame(
      home: List<int>.from(json['home'] as List),
      away: List<int>.from(json['away'] as List),
      homeLegs: json['homeLegs'] as int?,
      awayLegs: json['awayLegs'] as int?,
      homeSets: json['homeSets'] as int?,
      awaySets: json['awaySets'] as int?,
      runtime: json['runtime'] == null
          ? null
          : Map<String, dynamic>.from(json['runtime'] as Map),
    );
    if (game.complete) {
      final home = game.homeScore(format);
      final away = game.awayScore(format);
      game.score(
        home,
        away,
        format: format,
        legsHome: game.homeLegs,
        legsAway: game.awayLegs,
      );
    }
    return game;
  }
}

enum LeagueMatchVariant { traditional, adjusted }

class LeagueSubstitution {
  const LeagueSubstitution({
    required this.teamSide,
    required this.outPlayerIndex,
    required this.inPlayerIndex,
    required this.occurredAt,
  });

  final int teamSide;
  final int outPlayerIndex;
  final int inPlayerIndex;
  final DateTime occurredAt;

  Map<String, Object?> toJson() => {
    'teamSide': teamSide,
    'outPlayerIndex': outPlayerIndex,
    'inPlayerIndex': inPlayerIndex,
    'occurredAt': occurredAt.toIso8601String(),
  };

  factory LeagueSubstitution.fromJson(Map<String, dynamic> json) =>
      LeagueSubstitution(
        teamSide: json['teamSide'] as int,
        outPlayerIndex: json['outPlayerIndex'] as int,
        inPlayerIndex: json['inPlayerIndex'] as int,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
      );
}

/// A league match supports the fixed traditional format and an even-roster
/// adjusted format. Each fixture awards one team point.
class LeagueMatch {
  LeagueMatch({
    required this.homeTeam,
    required this.awayTeam,
    required this.homePlayers,
    required this.awayPlayers,
    required this.games,
    this.gameFormat = const TournamentGameFormat(bestOfLegs: 5),
    this.variant = LeagueMatchVariant.traditional,
    this.singlesPerPlayer = 4,
    this.doublesCount = 2,
    int? starterCount,
    this.maxReservePlayers = 4,
    int? substitutionLimit,
    this.allowReentry = false,
    List<LeagueSubstitution>? substitutions,
  }) : starterCount =
           starterCount ??
           (variant == LeagueMatchVariant.traditional ? 4 : homePlayers.length),
       substitutionLimit =
           substitutionLimit ??
           (variant == LeagueMatchVariant.traditional ? 4 : maxReservePlayers),
       substitutions = substitutions ?? [];
  final String homeTeam;
  final String awayTeam;
  final List<String> homePlayers;
  final List<String> awayPlayers;
  final List<LeagueGame> games;
  final TournamentGameFormat gameFormat;
  final LeagueMatchVariant variant;
  final int singlesPerPlayer;
  final int doublesCount;
  final int starterCount;
  final int maxReservePlayers;
  final int substitutionLimit;
  final bool allowReentry;
  final List<LeagueSubstitution> substitutions;

  List<int> activePlayers(int teamSide) {
    _validateTeamSide(teamSide);
    final active = <int>{
      for (var index = 0; index < starterCount; index++) index,
    };
    for (final substitution in substitutions.where(
      (item) => item.teamSide == teamSide,
    )) {
      active
        ..remove(substitution.outPlayerIndex)
        ..add(substitution.inPlayerIndex);
    }
    return active.toList()..sort();
  }

  List<int> reservePlayers(int teamSide) {
    _validateTeamSide(teamSide);
    final roster = teamSide == 0 ? homePlayers : awayPlayers;
    final firstReserve = starterCount;
    final reserveLimit = (starterCount + maxReservePlayers).clamp(
      firstReserve,
      roster.length,
    );
    final reserves = <int>{
      for (var index = firstReserve; index < reserveLimit; index++) index,
    };
    if (allowReentry) {
      reserves.addAll(
        substitutions
            .where(
              (item) =>
                  item.teamSide == teamSide &&
                  item.outPlayerIndex < starterCount,
            )
            .map((item) => item.outPlayerIndex),
      );
    }
    return reserves.toList()..sort();
  }

  int substitutionsUsed(int teamSide) {
    _validateTeamSide(teamSide);
    return substitutions.where((item) => item.teamSide == teamSide).length;
  }

  int substitutionsRemaining(int teamSide) {
    _validateTeamSide(teamSide);
    final active = activePlayers(teamSide).toSet();
    final availableReserveCount = reservePlayers(teamSide)
        .where(
          (player) =>
              !active.contains(player) &&
              (allowReentry ||
                  !substitutions.any(
                    (event) =>
                        event.teamSide == teamSide &&
                        event.outPlayerIndex == player,
                  )),
        )
        .length;
    return (substitutionLimit - substitutionsUsed(teamSide)).clamp(
      0,
      availableReserveCount,
    );
  }

  void substitute({
    required int teamSide,
    required int outPlayerIndex,
    required int inPlayerIndex,
    DateTime? occurredAt,
  }) {
    _validateTeamSide(teamSide);
    final roster = teamSide == 0 ? homePlayers : awayPlayers;
    final active = activePlayers(teamSide);
    final reserves = reservePlayers(teamSide);
    if (outPlayerIndex < 0 ||
        outPlayerIndex >= roster.length ||
        inPlayerIndex < 0 ||
        inPlayerIndex >= roster.length ||
        !active.contains(outPlayerIndex) ||
        !reserves.contains(inPlayerIndex) ||
        active.contains(inPlayerIndex)) {
      throw const FormatException('Ungültiger Teilnehmerwechsel.');
    }
    if (substitutionsRemaining(teamSide) < 1) {
      throw const FormatException('Keine Auswechselungen mehr verfügbar.');
    }
    final alreadySubstitutedOut = substitutions.any(
      (item) =>
          item.teamSide == teamSide && item.outPlayerIndex == inPlayerIndex,
    );
    if (alreadySubstitutedOut && !allowReentry) {
      throw const FormatException(
        'Bereits ausgewechselte Teilnehmer dürfen nicht erneut eingewechselt werden.',
      );
    }

    for (final game in games) {
      if (game.complete || game.runtime?['startedAt'] != null) continue;
      final side = teamSide == 0 ? game.home : game.away;
      for (var index = 0; index < side.length; index++) {
        if (side[index] == outPlayerIndex) side[index] = inPlayerIndex;
      }
    }
    substitutions.add(
      LeagueSubstitution(
        teamSide: teamSide,
        outPlayerIndex: outPlayerIndex,
        inPlayerIndex: inPlayerIndex,
        occurredAt: occurredAt ?? DateTime.now(),
      ),
    );
  }

  void _validateTeamSide(int teamSide) {
    if (teamSide != 0 && teamSide != 1) {
      throw ArgumentError.value(teamSide, 'teamSide');
    }
  }

  int get homePoints => games
      .where(
        (g) =>
            g.complete && g.homeScore(gameFormat)! > g.awayScore(gameFormat)!,
      )
      .length;
  int get awayPoints => games
      .where(
        (g) =>
            g.complete && g.awayScore(gameFormat)! > g.homeScore(gameFormat)!,
      )
      .length;
  bool get complete => games.every((g) => g.complete);
  String get outcome => !complete
      ? 'Noch nicht abgeschlossen'
      : homePoints == awayPoints
      ? 'Unentschieden'
      : 'Sieger: ${homePoints > awayPoints ? homeTeam : awayTeam}';

  factory LeagueMatch.rhl({
    required String homeTeam,
    required String awayTeam,
    required List<String> homePlayers,
    required List<String> awayPlayers,
    TournamentGameFormat gameFormat = const TournamentGameFormat(bestOfLegs: 5),
  }) {
    if (homePlayers.length < 4 ||
        awayPlayers.length < 4 ||
        homePlayers.length > 8 ||
        awayPlayers.length > 8) {
      throw const FormatException(
        'Traditionelle Mannschaften benötigen 4 bis 8 Teilnehmer.',
      );
    }
    final match = LeagueMatch(
      homeTeam: homeTeam.trim(),
      awayTeam: awayTeam.trim(),
      homePlayers: homePlayers.map((p) => p.trim()).toList(),
      awayPlayers: awayPlayers.map((p) => p.trim()).toList(),
      games: [
        for (var round = 0; round < 4; round++)
          for (var home = 0; home < 4; home++)
            LeagueGame(home: [home], away: [(home + round) % 4]),
        LeagueGame(home: [0, 1], away: [0, 1]),
        LeagueGame(home: [2, 3], away: [2, 3]),
      ],
      gameFormat: gameFormat,
      variant: LeagueMatchVariant.traditional,
      singlesPerPlayer: 4,
      doublesCount: 2,
      starterCount: 4,
      maxReservePlayers: 4,
      substitutionLimit: 4,
    );
    match.validate();
    return match;
  }

  factory LeagueMatch.adjusted({
    required String homeTeam,
    required String awayTeam,
    required List<String> homePlayers,
    required List<String> awayPlayers,
    required int singlesPerPlayer,
    required int doublesCount,
    int? starterCount,
    int maxReservePlayers = 2,
    int? substitutionLimit,
    bool allowReentry = false,
    TournamentGameFormat gameFormat = const TournamentGameFormat(bestOfLegs: 5),
  }) {
    final starters =
        starterCount ??
        (homePlayers.length < awayPlayers.length
            ? homePlayers.length
            : awayPlayers.length);
    if (homePlayers.length < starters ||
        awayPlayers.length < starters ||
        starters < 1) {
      throw const FormatException(
        'Beide Teams benötigen mindestens so viele Teilnehmer wie Stammplätze.',
      );
    }
    if (singlesPerPlayer < 1) {
      throw const FormatException(
        'Jeder Teilnehmer muss mindestens ein Einzel spielen.',
      );
    }
    if (maxReservePlayers < 0 ||
        homePlayers.length > starters + maxReservePlayers ||
        awayPlayers.length > starters + maxReservePlayers) {
      throw const FormatException(
        'Die Mannschaftskader überschreiten die erlaubte Anzahl Ersatzspieler.',
      );
    }
    if (doublesCount < 0 || doublesCount > starters ~/ 2) {
      throw const FormatException(
        'Die Anzahl der Doppel darf höchstens der Hälfte der Teilnehmer je Team entsprechen.',
      );
    }
    final games = <LeagueGame>[];
    for (var round = 0; round < singlesPerPlayer; round++) {
      for (var player = 0; player < starters; player++) {
        games.add(
          LeagueGame(home: [player], away: [(player + round) % starters]),
        );
      }
    }
    for (var pair = 0; pair < doublesCount; pair++) {
      games.add(
        LeagueGame(
          home: [pair * 2, pair * 2 + 1],
          away: [pair * 2, pair * 2 + 1],
        ),
      );
    }
    final match = LeagueMatch(
      homeTeam: homeTeam.trim(),
      awayTeam: awayTeam.trim(),
      homePlayers: homePlayers.map((p) => p.trim()).toList(),
      awayPlayers: awayPlayers.map((p) => p.trim()).toList(),
      games: games,
      gameFormat: gameFormat,
      variant: LeagueMatchVariant.adjusted,
      singlesPerPlayer: singlesPerPlayer,
      doublesCount: doublesCount,
      starterCount: starters,
      maxReservePlayers: maxReservePlayers,
      substitutionLimit: substitutionLimit ?? maxReservePlayers,
      allowReentry: allowReentry,
    );
    match.validate();
    return match;
  }

  void validate({bool validateSinglesDistribution = true}) {
    if (homeTeam.isEmpty || awayTeam.isEmpty) {
      throw const FormatException('Mannschaftsnamen fehlen.');
    }
    for (final roster in [homePlayers, awayPlayers]) {
      if (roster.length < starterCount || roster.any((p) => p.trim().isEmpty)) {
        throw FormatException(
          variant == LeagueMatchVariant.traditional
              ? 'Je Mannschaft werden mindestens 4 Stammspieler benötigt.'
              : 'Teilnehmernamen dürfen nicht leer sein.',
        );
      }
    }
    if (starterCount < 1 ||
        maxReservePlayers < 0 ||
        substitutionLimit < 0 ||
        homePlayers.length > starterCount + maxReservePlayers ||
        awayPlayers.length > starterCount + maxReservePlayers) {
      throw const FormatException('Ungültige Kader- oder Wechselregeln.');
    }
    if (variant == LeagueMatchVariant.traditional &&
        (starterCount != 4 ||
            homePlayers.length > 8 ||
            awayPlayers.length > 8 ||
            maxReservePlayers != 4)) {
      throw const FormatException(
        'Ungültiger traditioneller Mannschaftskader.',
      );
    }
    if (variant == LeagueMatchVariant.traditional &&
        (games.length != 18 || games.where((g) => g.isDouble).length != 2)) {
      throw const FormatException(
        'Ein RHL-Ligaspiel benötigt 16 Einzel und 2 Doppel.',
      );
    }
    if (variant == LeagueMatchVariant.adjusted) {
      if (singlesPerPlayer < 1 ||
          doublesCount < 0 ||
          doublesCount > starterCount ~/ 2 ||
          games.length != starterCount * singlesPerPlayer + doublesCount ||
          games.where((g) => g.isDouble).length != doublesCount) {
        throw const FormatException('Ungültiger angepasster Spielplan.');
      }
      // Substitutions intentionally change the scheduled player distribution.
      // Persisted schedules may predate the fairness rule or have been edited.
      if (validateSinglesDistribution && substitutions.isEmpty) {
        for (var player = 0; player < starterCount; player++) {
          if (games
                      .where(
                        (game) => !game.isDouble && game.home.contains(player),
                      )
                      .length !=
                  singlesPerPlayer ||
              games
                      .where(
                        (game) => !game.isDouble && game.away.contains(player),
                      )
                      .length !=
                  singlesPerPlayer) {
            throw const FormatException(
              'Die Einzel müssen gleichmäßig auf alle Teilnehmer verteilt sein.',
            );
          }
        }
      }
    }
    for (final game in games) {
      if (game.home.length != game.away.length ||
          ![1, 2].contains(game.home.length) ||
          game.home.toSet().length != game.home.length ||
          game.away.toSet().length != game.away.length ||
          game.home.any((i) => i < 0 || i >= homePlayers.length) ||
          game.away.any((i) => i < 0 || i >= awayPlayers.length)) {
        throw const FormatException('Ungültige Aufstellung.');
      }
    }
    for (var index = 0; index < substitutions.length; index++) {
      final event = substitutions[index];
      final roster = event.teamSide == 0 ? homePlayers : awayPlayers;
      final isReentry =
          allowReentry &&
          substitutions
              .take(index)
              .any(
                (previous) =>
                    previous.teamSide == event.teamSide &&
                    previous.outPlayerIndex == event.inPlayerIndex,
              );
      if (event.teamSide < 0 ||
          event.teamSide > 1 ||
          event.outPlayerIndex < 0 ||
          event.outPlayerIndex >= roster.length ||
          (event.inPlayerIndex < starterCount && !isReentry) ||
          event.inPlayerIndex >= roster.length) {
        throw const FormatException(
          'Ungültiger gespeicherter Teilnehmerwechsel.',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 5,
    'preset': 'rhl',
    'variant': variant.name,
    'starterCount': starterCount,
    'maxReservePlayers': maxReservePlayers,
    'substitutionLimit': substitutionLimit,
    'allowReentry': allowReentry,
    'substitutions': substitutions.map((event) => event.toJson()).toList(),
    if (variant == LeagueMatchVariant.adjusted) ...{
      'singlesPerPlayer': singlesPerPlayer,
      'doublesCount': doublesCount,
    },
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'homePlayers': homePlayers,
    'awayPlayers': awayPlayers,
    'gameFormat': gameFormat.toJson(),
    'games': games.map((g) => g.toJson()).toList(),
  };
  factory LeagueMatch.fromJson(Map<String, dynamic> json) {
    if (![1, 2, 3, 4, 5].contains(json['version']) || json['preset'] != 'rhl') {
      throw const FormatException('Nicht unterstützte Ligaspiel-Version.');
    }
    final gameFormat = json['gameFormat'] is Map
        ? TournamentGameFormat.fromJson(
            Map<String, dynamic>.from(json['gameFormat'] as Map),
          )
        : const TournamentGameFormat(bestOfLegs: 5);
    final match = LeagueMatch(
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      homePlayers: List<String>.from(json['homePlayers'] as List),
      awayPlayers: List<String>.from(json['awayPlayers'] as List),
      games: (json['games'] as List)
          .map(
            (g) => LeagueGame.fromJson(
              Map<String, dynamic>.from(g as Map),
              format: gameFormat,
            ),
          )
          .toList(),
      gameFormat: gameFormat,
      variant: json['variant'] == LeagueMatchVariant.adjusted.name
          ? LeagueMatchVariant.adjusted
          : LeagueMatchVariant.traditional,
      singlesPerPlayer: json['singlesPerPlayer'] as int? ?? 4,
      doublesCount: json['doublesCount'] as int? ?? 2,
      starterCount: json['starterCount'] as int?,
      maxReservePlayers:
          json['maxReservePlayers'] as int? ??
          (json['variant'] == LeagueMatchVariant.adjusted.name ? 0 : 4),
      substitutionLimit: json['substitutionLimit'] as int?,
      allowReentry: json['allowReentry'] as bool? ?? false,
      substitutions: (json['substitutions'] as List? ?? const [])
          .map(
            (item) => LeagueSubstitution.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
    match.validate(validateSinglesDistribution: false);
    return match;
  }
}
