import 'dart:math';
import 'player_withdrawal.dart';
import 'imported_tournament_archive.dart';
import '../../statistics/domain/best_performance.dart';
import '../../league/domain/league_match.dart';

const List<String> defaultGroupTieBreakers = [
  'points',
  'legDifference',
  'legsFor',
  'headToHead',
];

String groupLabel(int groupNumber) {
  var number = groupNumber;
  var label = '';
  while (number > 0) {
    number--;
    label = String.fromCharCode(65 + (number % 26)) + label;
    number ~/= 26;
  }

  return 'Gruppe $label';
}

String tieBreakerLabel(String tieBreaker) {
  return switch (tieBreaker) {
    'points' => 'Punkte',
    'legDifference' => 'Leg-Differenz',
    'legsFor' => 'Gewonnene Legs',
    'headToHead' => 'Direkter Vergleich',
    _ => tieBreaker,
  };
}

String _newTournamentId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final randomPart = Random().nextInt(1 << 32);
  return '$timestamp-$randomPart';
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value);
}

List<int> _intListFromJson(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is int) item,
  ];
}

List<int?> _nullableIntListFromJson(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [for (final item in value) item is int ? item : null];
}

List<String> _stringListFromJson(
  Object? value, {
  List<String> fallback = const [],
}) {
  if (value is! List) {
    return List<String>.from(fallback);
  }
  return [
    for (final item in value)
      if (item is String) item,
  ];
}

List<T> _mapListFromJson<T>(
  Object? value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! List) {
    return [];
  }
  return [
    for (final item in value)
      if (item is Map<String, dynamic>) fromJson(item),
  ];
}

TournamentPlayer? _playerFromJson(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  return TournamentPlayer.fromJson(value);
}

List<List<GroupMatch>> _matchRoundsFromJson(Object? value) {
  if (value is! List) {
    return [];
  }
  return [
    for (final round in value)
      if (round is List)
        [
          for (final match in round)
            if (match is Map<String, dynamic>) GroupMatch.fromJson(match),
        ],
  ];
}

List<TournamentRunStage> _runStageListFromJson(Object? value) {
  if (value is! List) {
    return [];
  }

  return [
    for (final item in value)
      if (item is Map<String, dynamic>) _runStageFromJson(item),
  ];
}

TournamentRunStage _runStageFromJson(Map<String, dynamic> json) {
  final kind = json['kind'] as String?;
  if (kind == 'single_knockout') {
    return KnockoutTournamentRunStage(
      name: json['name'] as String? ?? '',
      rounds: _matchRoundsFromJson(json['rounds']),
      placementMatches: _mapListFromJson(
        json['placementMatches'],
        GroupMatch.fromJson,
      ),
      eliminationLossLimit: json['eliminationLossLimit'] as int? ?? 1,
      finalEndsTournament: json['finalEndsTournament'] as bool? ?? false,
    );
  }

  return GroupTournamentRunStage(
    name: json['name'] as String? ?? '',
    groupPlayType: json['groupPlayType'] as String? ?? 'round_robin',
    groups: _mapListFromJson(json['groups'], TournamentGroup.fromJson),
    qualificationPlan: json['qualificationPlan'] is Map<String, dynamic>
        ? QualificationPlan.fromJson(
            json['qualificationPlan'] as Map<String, dynamic>,
          )
        : null,
    tieBreakers: _stringListFromJson(
      json['tieBreakers'],
      fallback: defaultGroupTieBreakers,
    ),
  );
}

Map<String, dynamic> _runStageToJson(TournamentRunStage stage) {
  if (stage is GroupTournamentRunStage) {
    return stage.toJson();
  }
  if (stage is KnockoutTournamentRunStage) {
    return stage.toJson();
  }
  return {'kind': 'unknown', 'name': stage.name};
}

class TournamentPlayer {
  const TournamentPlayer({
    this.profileId,
    required this.name,
    required this.isGenerated,
    this.members = const [],
  });

  factory TournamentPlayer.fromJson(Map<String, dynamic> json) {
    return TournamentPlayer(
      profileId: json['profileId'] as String?,
      name: json['name'] as String? ?? '',
      isGenerated: json['isGenerated'] as bool? ?? false,
      members: (json['members'] as List? ?? const [])
          .map(
            (e) =>
                TournamentPlayer.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }

  factory TournamentPlayer.generated(int number) {
    return TournamentPlayer(name: 'Spieler $number', isGenerated: true);
  }

  final String? profileId;
  final String name;
  final bool isGenerated;
  final List<TournamentPlayer> members;
  bool get isTeam => members.isNotEmpty;
  List<TournamentPlayer> get individuals =>
      isTeam ? members.expand((p) => p.individuals).toList() : [this];

  factory TournamentPlayer.team(Iterable<TournamentPlayer> players) {
    final members = players.expand((p) => p.individuals).toList();
    if (members.length < 2 ||
        members.map((p) => p.profileId ?? p.name).toSet().length !=
            members.length) {
      throw ArgumentError(
        'Ein Team benötigt mindestens zwei unterschiedliche Spieler.',
      );
    }
    return TournamentPlayer(
      name: members.map((p) => p.name).join(' / '),
      isGenerated: false,
      members: List.unmodifiable(members),
    );
  }

  TournamentPlayer copyWith({
    String? profileId,
    String? name,
    bool? isGenerated,
  }) {
    return TournamentPlayer(
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      isGenerated: isGenerated ?? this.isGenerated,
      members: members,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (profileId != null) 'profileId': profileId,
      'name': name,
      'isGenerated': isGenerated,
      if (isTeam) 'members': members.map((p) => p.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TournamentPlayer &&
        other.profileId == profileId &&
        other.name == name &&
        other.isGenerated == isGenerated &&
        other.members.length == members.length &&
        Iterable<int>.generate(
          members.length,
        ).every((i) => members[i] == other.members[i]);
  }

  @override
  int get hashCode =>
      Object.hash(profileId, name, isGenerated, Object.hashAll(members));
}

class TournamentStage {
  const TournamentStage({
    required this.name,
    required this.type,
    this.finalEndsTournament = true,
    this.knockoutLives,
    this.placementPlaces = const [],
    this.groupCount,
    this.groupSizes = const [],
    this.groupPlayType = 'round_robin',
    this.groupPlayTypes = const [],
    this.groupRoundRobinRepeats = const [],
    this.groupMaxGamesPerPlayer = const [],
    this.groupTieBreakers = defaultGroupTieBreakers,
    this.groupDrawOnStart = false,
    this.groupSlotOrder = const [],
    this.knockoutParticipantCount,
    this.knockoutBracketSize,
    this.knockoutByeCount = 0,
    this.knockoutSlotOrder = const [],
    this.knockoutSeedingMode = 'cross',
    this.knockoutDrawOnStart = false,
    this.qualifiersByGroup = const [],
    this.fixedQualifiersByGroup = const [],
    this.extraQualifierRank,
    this.extraQualifierCount,
    this.qualificationAutoAdjust = true,
    this.qualifiedParticipantCount,
    this.qualificationSummary,
    this.gameFormat = const TournamentGameFormat(),
  });

  factory TournamentStage.fromJson(Map<String, dynamic> json) {
    return TournamentStage(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'groups',
      finalEndsTournament: json['finalEndsTournament'] as bool? ?? false,
      knockoutLives: json['knockoutLives'] as int?,
      placementPlaces: _intListFromJson(json['placementPlaces']),
      groupCount: json['groupCount'] as int?,
      groupSizes: _intListFromJson(json['groupSizes']),
      groupPlayType: json['groupPlayType'] as String? ?? 'round_robin',
      groupPlayTypes: _stringListFromJson(json['groupPlayTypes']),
      groupRoundRobinRepeats: _intListFromJson(json['groupRoundRobinRepeats']),
      groupMaxGamesPerPlayer: _nullableIntListFromJson(
        json['groupMaxGamesPerPlayer'],
      ),
      groupTieBreakers: _stringListFromJson(
        json['groupTieBreakers'],
        fallback: defaultGroupTieBreakers,
      ),
      groupDrawOnStart: json['groupDrawOnStart'] as bool? ?? false,
      groupSlotOrder: _nullableIntListFromJson(json['groupSlotOrder']),
      knockoutParticipantCount: json['knockoutParticipantCount'] as int?,
      knockoutBracketSize: json['knockoutBracketSize'] as int?,
      knockoutByeCount: json['knockoutByeCount'] as int? ?? 0,
      knockoutSlotOrder: _nullableIntListFromJson(json['knockoutSlotOrder']),
      knockoutSeedingMode: json['knockoutSeedingMode'] as String? ?? 'cross',
      knockoutDrawOnStart: json['knockoutDrawOnStart'] as bool? ?? false,
      qualifiersByGroup: _intListFromJson(json['qualifiersByGroup']),
      fixedQualifiersByGroup: _intListFromJson(json['fixedQualifiersByGroup']),
      extraQualifierRank: json['extraQualifierRank'] as int?,
      extraQualifierCount: json['extraQualifierCount'] as int?,
      qualificationAutoAdjust: json['qualificationAutoAdjust'] as bool? ?? true,
      qualifiedParticipantCount: json['qualifiedParticipantCount'] as int?,
      qualificationSummary: json['qualificationSummary'] as String?,
      gameFormat: json['gameFormat'] is Map<String, dynamic>
          ? TournamentGameFormat.fromJson(
              json['gameFormat'] as Map<String, dynamic>,
            )
          : const TournamentGameFormat(),
    );
  }

  final String name;
  final String type;
  final bool finalEndsTournament;
  final int? knockoutLives;
  final List<int> placementPlaces;
  int get lossLimit =>
      knockoutLives ??
      (type == 'double_knockout'
          ? 2
          : type == 'triple_knockout' || type == 'kratzer'
          ? 3
          : 1);
  final int? groupCount;
  final List<int> groupSizes;
  final String groupPlayType;
  final List<String> groupPlayTypes;
  final List<int> groupRoundRobinRepeats;

  /// Null means a full round robin; positive values cap actual games, excluding byes.
  final List<int?> groupMaxGamesPerPlayer;
  int? maxGamesForGroup(int index) =>
      index >= 0 && index < groupMaxGamesPerPlayer.length
      ? groupMaxGamesPerPlayer[index]
      : null;
  final List<String> groupTieBreakers;
  final bool groupDrawOnStart;
  final List<int?> groupSlotOrder;
  final int? knockoutParticipantCount;
  final int? knockoutBracketSize;
  final int knockoutByeCount;
  final List<int?> knockoutSlotOrder;
  final String knockoutSeedingMode;
  final bool knockoutDrawOnStart;
  final List<int> qualifiersByGroup;
  final List<int> fixedQualifiersByGroup;
  final int? extraQualifierRank;
  final int? extraQualifierCount;
  final bool qualificationAutoAdjust;
  final int? qualifiedParticipantCount;
  final String? qualificationSummary;
  final TournamentGameFormat gameFormat;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'finalEndsTournament': finalEndsTournament,
      'knockoutLives': knockoutLives,
      'placementPlaces': placementPlaces,
      'groupCount': groupCount,
      'groupSizes': groupSizes,
      'groupPlayType': groupPlayType,
      'groupPlayTypes': groupPlayTypes,
      'groupRoundRobinRepeats': groupRoundRobinRepeats,
      'groupMaxGamesPerPlayer': groupMaxGamesPerPlayer,
      'groupTieBreakers': groupTieBreakers,
      'groupDrawOnStart': groupDrawOnStart,
      'groupSlotOrder': groupSlotOrder,
      'knockoutParticipantCount': knockoutParticipantCount,
      'knockoutBracketSize': knockoutBracketSize,
      'knockoutByeCount': knockoutByeCount,
      'knockoutSlotOrder': knockoutSlotOrder,
      'knockoutSeedingMode': knockoutSeedingMode,
      'knockoutDrawOnStart': knockoutDrawOnStart,
      'qualifiersByGroup': qualifiersByGroup,
      'fixedQualifiersByGroup': fixedQualifiersByGroup,
      'extraQualifierRank': extraQualifierRank,
      'extraQualifierCount': extraQualifierCount,
      'qualificationAutoAdjust': qualificationAutoAdjust,
      'qualifiedParticipantCount': qualifiedParticipantCount,
      'qualificationSummary': qualificationSummary,
      'gameFormat': gameFormat.toJson(),
    };
  }
}

/// Das tatsächlich gespielte Format einer Etappe. Es ist bewusst unabhängig
/// von der Planungs-Schätzung gespeichert, damit es später in der Übersicht
/// und bei Ergebnissen zuverlässig angezeigt werden kann.
class TournamentGameFormat {
  static final List<int> supportedDrawLegs = List.unmodifiable(
    List.generate(50, (i) => 2 + i * 2),
  );
  bool get allowsDraws => bestOfSets == 1 && bestOfLegs.isEven;
  static final List<int> supportedBestOfLegs = List.unmodifiable(
    List.generate(51, (index) => 1 + index * 2),
  );
  const TournamentGameFormat({
    this.gameType = 'x01',
    this.x01Score = 501,
    this.checkoutType = 'double_out',
    this.doubleIn = false,
    this.bestOfLegs = 3,
    this.bestOfSets = 1,
  });

  factory TournamentGameFormat.fromJson(Map<String, dynamic> json) {
    return TournamentGameFormat(
      gameType: json['gameType'] as String? ?? 'x01',
      x01Score: json['x01Score'] as int? ?? 501,
      checkoutType: json['checkoutType'] as String? ?? 'double_out',
      doubleIn: json['doubleIn'] as bool? ?? false,
      bestOfLegs: json['bestOfLegs'] as int? ?? 3,
      bestOfSets: json['bestOfSets'] as int? ?? 1,
    );
  }

  final String gameType;
  final int x01Score;
  final String checkoutType;
  final bool doubleIn;
  final int bestOfLegs;

  /// One set is the legacy leg-only format.
  final int bestOfSets;
  String get lengthLabel => bestOfSets == 1
      ? 'Best of $bestOfLegs Legs${allowsDraws ? ' · Unentschieden möglich' : ''}'
      : 'Best of $bestOfSets Sets · Best of $bestOfLegs Legs je Set';

  String get checkoutLabel => switch (checkoutType) {
    'single_out' => 'Single Out',
    'master_out' => 'Master Out',
    _ => 'Double Out',
  };

  String get label => gameType == 'cricket'
      ? 'Cricket · $lengthLabel'
      : '$x01Score ${doubleIn ? 'Double In / ' : ''}$checkoutLabel · $lengthLabel';

  Map<String, dynamic> toJson() => {
    'gameType': gameType,
    'x01Score': x01Score,
    'checkoutType': checkoutType,
    'doubleIn': doubleIn,
    'bestOfLegs': bestOfLegs,
    'bestOfSets': bestOfSets,
  };
}

class CreatedTournament {
  CreatedTournament({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.name,
    required this.players,
    required this.stages,
    required this.runStages,
    this.leagueMatch,
    this.importedArchive,
    this.countsForRanking = true,
    List<String> rankingIds = const [],
    this.activeStageIndex = 0,
    this.boardCount = 1,
    this.syncRevision = 0,
    List<PlayerWithdrawal>? withdrawals,
    Set<int>? blockedBoards,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.totalPausedSeconds = 0,
    this.plannedMinimumMinutes,
    this.plannedMinutes,
    this.plannedMatches,
    this.plannedMatchEndSeconds = const [],
    Set<int>? completedStageIndexes,
  }) : id = id ?? _newTournamentId(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       completedStageIndexes = completedStageIndexes ?? <int>{},
       blockedBoards = blockedBoards ?? <int>{},
       rankingIds = List<String>.from(rankingIds),
       withdrawals = withdrawals ?? [];

  factory CreatedTournament.fromJson(Map<String, dynamic> json) {
    return CreatedTournament(
      id: json['id'] as String?,
      createdAt: _dateTimeFromJson(json['createdAt']),
      updatedAt: _dateTimeFromJson(json['updatedAt']),
      name: json['name'] as String? ?? 'Neues Turnier',
      players: _mapListFromJson(json['players'], TournamentPlayer.fromJson),
      stages: _mapListFromJson(json['stages'], TournamentStage.fromJson),
      runStages: _runStageListFromJson(json['runStages']),
      leagueMatch: json['leagueMatch'] == null
          ? null
          : LeagueMatch.fromJson(
              Map<String, dynamic>.from(json['leagueMatch'] as Map),
            ),
      importedArchive: json['importedArchive'] == null
          ? null
          : ImportedTournamentArchive.fromJson(
              Map<String, dynamic>.from(json['importedArchive'] as Map),
            ),
      countsForRanking: json['countsForRanking'] as bool? ?? true,
      rankingIds: List<String>.unmodifiable(
        (json['rankingIds'] as List? ?? const []).cast<String>(),
      ),
      activeStageIndex: json['activeStageIndex'] as int? ?? 0,
      boardCount: (json['boardCount'] as int? ?? 1).clamp(1, 64),
      syncRevision: json['syncRevision'] as int? ?? 0,
      withdrawals: _mapListFromJson(
        json['withdrawals'],
        PlayerWithdrawal.fromJson,
      ),
      blockedBoards: _intListFromJson(
        json['blockedBoards'],
      ).where((b) => b >= 1 && b <= 64).toSet(),
      startedAt: _dateTimeFromJson(json['startedAt']),
      finishedAt: _dateTimeFromJson(json['finishedAt']),
      pausedAt: _dateTimeFromJson(json['pausedAt']),
      totalPausedSeconds: json['totalPausedSeconds'] as int? ?? 0,
      plannedMinimumMinutes: json['plannedMinimumMinutes'] as int?,
      plannedMinutes: json['plannedMinutes'] as int?,
      plannedMatches: json['plannedMatches'] as int?,
      plannedMatchEndSeconds: _intListFromJson(json['plannedMatchEndSeconds']),
      completedStageIndexes: _intListFromJson(
        json['completedStageIndexes'],
      ).toSet(),
    );
  }

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<TournamentPlayer> players;
  final List<TournamentStage> stages;
  final List<TournamentRunStage> runStages;
  final LeagueMatch? leagueMatch;
  final ImportedTournamentArchive? importedArchive;
  bool countsForRanking;
  List<String> rankingIds;
  int activeStageIndex;
  int boardCount;
  int syncRevision;
  final List<PlayerWithdrawal> withdrawals;
  final Set<int> blockedBoards;
  DateTime? startedAt, finishedAt, pausedAt;
  int totalPausedSeconds;
  bool get isClockPaused => pausedAt != null;
  int? plannedMinimumMinutes;
  int? plannedMinutes, plannedMatches;
  List<int> plannedMatchEndSeconds;
  final Set<int> completedStageIndexes;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (withdrawals.isNotEmpty)
        'withdrawals': withdrawals.map((w) => w.toJson()).toList(),
      'name': name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'players': players.map((player) => player.toJson()).toList(),
      'stages': stages.map((stage) => stage.toJson()).toList(),
      'runStages': runStages.map(_runStageToJson).toList(),
      if (leagueMatch != null) 'leagueMatch': leagueMatch!.toJson(),
      if (importedArchive != null) 'importedArchive': importedArchive!.toJson(),
      if (!countsForRanking) 'countsForRanking': false,
      if (rankingIds.isNotEmpty) 'rankingIds': rankingIds,
      'activeStageIndex': activeStageIndex,
      'boardCount': boardCount,
      if (syncRevision != 0) 'syncRevision': syncRevision,
      if (blockedBoards.isNotEmpty)
        'blockedBoards': blockedBoards.toList()..sort(),
      'startedAt': startedAt?.toUtc().toIso8601String(),
      'finishedAt': finishedAt?.toUtc().toIso8601String(),
      if (pausedAt != null) 'pausedAt': pausedAt?.toUtc().toIso8601String(),
      if (totalPausedSeconds > 0) 'totalPausedSeconds': totalPausedSeconds,
      if (plannedMinimumMinutes != null)
        'plannedMinimumMinutes': plannedMinimumMinutes,
      'plannedMinutes': plannedMinutes,
      'plannedMatches': plannedMatches,
      'plannedMatchEndSeconds': plannedMatchEndSeconds,
      'completedStageIndexes': completedStageIndexes.toList()..sort(),
    };
  }
}

abstract class TournamentRunStage {
  const TournamentRunStage({required this.name});

  final String name;
}

class GroupTournamentRunStage extends TournamentRunStage {
  const GroupTournamentRunStage({
    required super.name,
    required this.groupPlayType,
    required this.groups,
    required this.qualificationPlan,
    required this.tieBreakers,
  });

  final String groupPlayType;
  final List<TournamentGroup> groups;
  final QualificationPlan? qualificationPlan;
  final List<String> tieBreakers;

  Map<String, dynamic> toJson() {
    return {
      'kind': 'groups',
      'name': name,
      'groupPlayType': groupPlayType,
      'groups': groups.map((group) => group.toJson()).toList(),
      'qualificationPlan': qualificationPlan?.toJson(),
      'tieBreakers': tieBreakers,
    };
  }
}

class KnockoutTournamentRunStage extends TournamentRunStage {
  const KnockoutTournamentRunStage({
    required super.name,
    required this.rounds,
    this.placementMatches = const [],
    this.eliminationLossLimit = 1,
    this.finalEndsTournament = false,
  });

  final List<List<GroupMatch>> rounds;
  final List<GroupMatch> placementMatches;
  final int eliminationLossLimit;
  final bool finalEndsTournament;

  List<GroupMatch> get matches => [
    for (final round in rounds) ...round,
    ...placementMatches,
  ];

  Map<String, dynamic> toJson() {
    return {
      'kind': 'single_knockout',
      'name': name,
      'rounds': rounds
          .map((round) => round.map((match) => match.toJson()).toList())
          .toList(),
      'placementMatches': placementMatches
          .map((match) => match.toJson())
          .toList(),
      'eliminationLossLimit': eliminationLossLimit,
      'finalEndsTournament': finalEndsTournament,
    };
  }
}

class TournamentGroup {
  TournamentGroup({
    required this.name,
    required this.playType,
    required this.players,
    required this.matches,
    this.knockoutRounds = const [],
    this.placementMatches = const [],
    this.eliminationLossLimit = 1,
    this.finalEndsTournament = false,
  });

  final String name;
  final String playType;
  final List<TournamentPlayer> players;
  final List<GroupMatch> matches;
  final List<List<GroupMatch>> knockoutRounds;
  final List<GroupMatch> placementMatches;
  final int eliminationLossLimit;
  final bool finalEndsTournament;

  factory TournamentGroup.fromJson(Map<String, dynamic> json) {
    final storedMatches = _mapListFromJson(
      json['matches'],
      GroupMatch.fromJson,
    );
    final rounds = _matchRoundsFromJson(json['knockoutRounds']);
    final placements = _mapListFromJson(
      json['placementMatches'],
      GroupMatch.fromJson,
    );
    // Both views must edit the same objects after restoring a saved tournament.
    final matches = rounds.isEmpty
        ? storedMatches
        : <GroupMatch>[
            ...rounds.expand((round) => round),
            ...placements,
            ...storedMatches.where((match) => match.isDecider),
          ];
    return TournamentGroup(
      name: json['name'] as String? ?? '',
      playType: json['playType'] as String? ?? 'round_robin',
      players: _mapListFromJson(json['players'], TournamentPlayer.fromJson),
      matches: matches,
      knockoutRounds: rounds,
      placementMatches: placements,
      eliminationLossLimit: json['eliminationLossLimit'] as int? ?? 1,
      finalEndsTournament: json['finalEndsTournament'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'playType': playType,
      'players': players.map((player) => player.toJson()).toList(),
      'matches': matches.map((match) => match.toJson()).toList(),
      'knockoutRounds': knockoutRounds
          .map((round) => round.map((match) => match.toJson()).toList())
          .toList(),
      'placementMatches': placementMatches
          .map((match) => match.toJson())
          .toList(),
      'eliminationLossLimit': eliminationLossLimit,
      'finalEndsTournament': finalEndsTournament,
    };
  }
}

class GroupMatch {
  GroupMatch({
    this.homePlayer,
    this.awayPlayer,
    required this.round,
    this.homeLegs,
    this.awayLegs,
    this.homeSets,
    this.awaySets,
    this.allowsBye = false,
    this.placementKey,
    this.placementRank,
    this.label,
    this.isAnnulled = false,
    this.isDecider = false,
    this.boardNumber,
    this.startedAt,
    this.finishedAt,
    this.startedPlayers,
    this.withdrawalSignature,
    this.withdrawalIgnored = false,
    this.withdrawalHadResult = false,
    this.bestPerformances = const [],
  });

  factory GroupMatch.fromJson(Map<String, dynamic> json) {
    return GroupMatch(
      homePlayer: _playerFromJson(json['homePlayer']),
      awayPlayer: _playerFromJson(json['awayPlayer']),
      round: json['round'] as int? ?? 1,
      homeLegs: json['homeLegs'] as int?,
      awayLegs: json['awayLegs'] as int?,
      homeSets: json['homeSets'] as int?,
      awaySets: json['awaySets'] as int?,
      allowsBye: json['allowsBye'] as bool? ?? false,
      placementKey: json['placementKey'] as String?,
      placementRank: json['placementRank'] as int?,
      label: json['label'] as String?,
      isAnnulled: json['isAnnulled'] as bool? ?? false,
      isDecider: json['isDecider'] as bool? ?? false,
      boardNumber: json['boardNumber'] as int?,
      startedAt: _dateTimeFromJson(json['startedAt']),
      finishedAt: _dateTimeFromJson(json['finishedAt']),
      startedPlayers: json['startedPlayers'] as String?,
      withdrawalSignature: json['withdrawalSignature'] as String?,
      withdrawalIgnored: json['withdrawalIgnored'] == true,
      withdrawalHadResult: json['withdrawalHadResult'] == true,
      bestPerformances: (json['bestPerformances'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => BestPerformance.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }

  TournamentPlayer? homePlayer;
  TournamentPlayer? awayPlayer;
  final int round;
  int? homeLegs;
  int? awayLegs;
  int? homeSets;
  int? awaySets;
  bool get hasSetScore => homeSets != null && awaySets != null;
  int? get homeScore => hasSetScore ? homeSets : homeLegs;
  int? get awayScore => hasSetScore ? awaySets : awayLegs;
  String get scoreLabel => withdrawalIgnored
      ? 'Nicht gewertet'
      : '$homeScore:$awayScore${hasSetScore ? ' Sets' : ''}${withdrawalSignature != null && !withdrawalHadResult ? ' · kampflos' : ''}';
  bool allowsBye;
  final String? placementKey;
  final int? placementRank;
  final String? label;
  bool isAnnulled;
  final bool isDecider;
  int? boardNumber;
  DateTime? startedAt;
  DateTime? finishedAt;
  String? startedPlayers;
  String? withdrawalSignature;
  bool withdrawalIgnored;
  bool withdrawalHadResult;
  List<BestPerformance> bestPerformances;
  bool get countsForStatistics => hasResult && !withdrawalIgnored;

  bool get hasPlayers => homePlayer != null && awayPlayer != null;
  bool get hasScore => hasPlayers && homeLegs != null && awayLegs != null;
  bool get hasResult => hasScore && !isAnnulled;
  bool get isResolved => isAnnulled || hasResult || winner != null;

  TournamentPlayer? get winner {
    if (allowsBye && homePlayer != null && awayPlayer == null) {
      return homePlayer;
    }
    if (allowsBye && awayPlayer != null && homePlayer == null) {
      return awayPlayer;
    }
    if (!hasResult) {
      return null;
    }
    if (homeScore! == awayScore!) {
      return null;
    }

    return homeScore! > awayScore! ? homePlayer : awayPlayer;
  }

  TournamentPlayer? get loser {
    final winningPlayer = winner;
    if (winningPlayer == null || !hasResult) {
      return null;
    }

    return winningPlayer == homePlayer ? awayPlayer : homePlayer;
  }

  Map<String, dynamic> toJson() {
    return {
      'homePlayer': homePlayer?.toJson(),
      'awayPlayer': awayPlayer?.toJson(),
      'round': round,
      'homeLegs': homeLegs,
      'awayLegs': awayLegs,
      'homeSets': homeSets,
      'awaySets': awaySets,
      'allowsBye': allowsBye,
      'placementKey': placementKey,
      'placementRank': placementRank,
      'label': label,
      'isAnnulled': isAnnulled,
      if (withdrawalSignature != null)
        'withdrawalSignature': withdrawalSignature,
      if (withdrawalIgnored) 'withdrawalIgnored': true,
      if (withdrawalHadResult) 'withdrawalHadResult': true,
      'isDecider': isDecider,
      'boardNumber': boardNumber,
      'startedAt': startedAt?.toUtc().toIso8601String(),
      'finishedAt': finishedAt?.toUtc().toIso8601String(),
      'startedPlayers': startedPlayers,
      'bestPerformances': bestPerformances
          .map((item) => item.toJson())
          .toList(),
    };
  }
}

class PlayerStanding {
  PlayerStanding(this.player);

  final TournamentPlayer player;
  int played = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int legsFor = 0;
  int legsAgainst = 0;
  int points = 0;

  int get legDifference => legsFor - legsAgainst;
}

class BestOfCandidate {
  const BestOfCandidate({
    required this.groupName,
    required this.groupNumber,
    required this.place,
    required this.standing,
  });

  final String groupName;
  final int groupNumber;
  final int place;
  final PlayerStanding standing;
}

class QualificationPlan {
  const QualificationPlan({
    required this.totalQualifiers,
    required this.fixedPerGroup,
    required this.extraCount,
    required this.extraRank,
    required this.eligibleGroupSize,
    required this.extraGroups,
    this.fixedByGroup = const [],
  });

  final int totalQualifiers;
  final int fixedPerGroup;
  final int extraCount;
  final int extraRank;
  final int? eligibleGroupSize;
  final List<int> extraGroups;
  final List<int> fixedByGroup;

  factory QualificationPlan.fromJson(Map<String, dynamic> json) {
    return QualificationPlan(
      totalQualifiers: json['totalQualifiers'] as int? ?? 0,
      fixedPerGroup: json['fixedPerGroup'] as int? ?? 0,
      extraCount: json['extraCount'] as int? ?? 0,
      extraRank: json['extraRank'] as int? ?? 0,
      eligibleGroupSize: json['eligibleGroupSize'] as int?,
      extraGroups: _intListFromJson(json['extraGroups']),
      fixedByGroup: _intListFromJson(json['fixedByGroup']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalQualifiers': totalQualifiers,
      'fixedPerGroup': fixedPerGroup,
      'extraCount': extraCount,
      'extraRank': extraRank,
      'eligibleGroupSize': eligibleGroupSize,
      'extraGroups': extraGroups,
      'fixedByGroup': fixedByGroup,
    };
  }

  String get summary {
    final fixedText = fixedPerGroup == 0
        ? 'keine sicheren Plätze'
        : 'Top $fixedPerGroup je Gruppe';

    if (extraCount == 0) {
      return '$totalQualifiers Weiterkommende - $fixedText';
    }

    final groupText = extraGroups.isEmpty
        ? ''
        : ' aus ${_formatGroupSelection(extraGroups)}';

    return '$totalQualifiers Weiterkommende - $fixedText + '
        'beste $extraCount $extraRank. Plätze$groupText';
  }

  String _formatGroupSelection(List<int> groups) {
    if (groups.length == 1) {
      return groupLabel(groups.first);
    }

    return groups.map(groupLabel).join(', ');
  }
}
