import 'dart:convert';
import 'dart:math';

import 'player_withdrawal.dart';
import 'imported_tournament_archive.dart';
import '../../statistics/domain/best_performance.dart';
import '../../league/domain/league_match.dart';
import 'second_screen_widget_placement.dart';
import 'tournament_activity_entry.dart';

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
    'points' => 'Matchpunkte',
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

int? _kratzerPlayersPerBoardFromJson(Object? value) {
  if (value is int && value >= 3 && value <= 6) return value;
  return null;
}

bool _boolFromJson(Object? value) => value is bool && value;

String _directorSchedulingStrategyFromJson(Object? value) {
  final strategy = (value as String? ?? 'group').trim().toLowerCase();
  return strategy == 'global' ? 'global' : 'group';
}

List<String> _groupTieBreakersFromJson(Object? value) {
  final tieBreakers = _stringListFromJson(
    value,
    fallback: defaultGroupTieBreakers,
  );
  const previousDefault = ['points', 'headToHead', 'legDifference', 'legsFor'];
  final isPreviousDefault =
      tieBreakers.length == previousDefault.length &&
      tieBreakers.asMap().entries.every(
        (entry) => entry.value == previousDefault[entry.key],
      );
  return isPreviousDefault
      ? List<String>.from(defaultGroupTieBreakers)
      : tieBreakers;
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

Map<int, String> _intStringMapFromJson(Object? value) {
  if (value is! Map) return const {};
  final result = <int, String>{};
  for (final entry in value.entries) {
    final index = int.tryParse(entry.key.toString());
    final label = entry.value;
    if (index != null && label is String && label.trim().isNotEmpty) {
      result[index] = label.trim();
    }
  }
  return result;
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
      isKratzer: json['isKratzer'] as bool? ?? false,
      kratzerPlayersPerBoard: _kratzerPlayersPerBoardFromJson(
        json['kratzerPlayersPerBoard'],
      ),
      kratzerPreferSameScratchCount: _boolFromJson(
        json['kratzerPreferSameScratchCount'],
      ),
      kratzerPlayUntilElimination: _boolFromJson(
        json['kratzerPlayUntilElimination'],
      ),
      kratzerBonusLifeFor180: _boolFromJson(json['kratzerBonusLifeFor180']),
      kratzerBonusLifeForHighFinish: _boolFromJson(
        json['kratzerBonusLifeForHighFinish'],
      ),
      kratzerHandicapsEnabled: _boolFromJson(json['kratzerHandicapsEnabled']),
      kratzerHandicaps: _stringListFromJson(json['kratzerHandicaps']),
      kratzerHandicapAssignments: _intStringMapFromJson(
        json['kratzerHandicapAssignments'],
      ),
      participants: _mapListFromJson(
        json['participants'],
        TournamentPlayer.fromJson,
      ),
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
    tieBreakers: _groupTieBreakersFromJson(json['tieBreakers']),
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
    this.compactName,
    this.members = const [],
    this.kratzerStartingScratches = 0,
  });

  factory TournamentPlayer.fromJson(Map<String, dynamic> json) {
    return TournamentPlayer(
      profileId: json['profileId'] as String?,
      name: json['name'] as String? ?? '',
      isGenerated: json['isGenerated'] as bool? ?? false,
      compactName: json['compactName'] as String?,
      kratzerStartingScratches: (json['kratzerStartingScratches'] as int? ?? 0)
          .clamp(0, 10),
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
  final String? compactName;
  final int kratzerStartingScratches;
  String get shortDisplayName {
    if (isTeam) {
      return members.map((player) => player.shortDisplayName).join(' / ');
    }
    final compact = compactName?.trim();
    if (compact != null && compact.isNotEmpty) return compact;
    if (isGenerated) return name;
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return name;
    return '${parts.first} ${parts.last[0]}.';
  }

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
    String? compactName,
    int? kratzerStartingScratches,
  }) {
    return TournamentPlayer(
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      isGenerated: isGenerated ?? this.isGenerated,
      compactName: compactName ?? this.compactName,
      members: members,
      kratzerStartingScratches:
          kratzerStartingScratches ?? this.kratzerStartingScratches,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (profileId != null) 'profileId': profileId,
      'name': name,
      'isGenerated': isGenerated,
      if (compactName != null) 'compactName': compactName,
      if (kratzerStartingScratches > 0)
        'kratzerStartingScratches': kratzerStartingScratches,
      if (isTeam) 'members': members.map((p) => p.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TournamentPlayer &&
        other.profileId == profileId &&
        other.name == name &&
        other.isGenerated == isGenerated &&
        other.compactName == compactName &&
        other.kratzerStartingScratches == kratzerStartingScratches &&
        other.members.length == members.length &&
        Iterable<int>.generate(
          members.length,
        ).every((i) => members[i] == other.members[i]);
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    name,
    isGenerated,
    compactName,
    kratzerStartingScratches,
    Object.hashAll(members),
  );
}

class TournamentStage {
  const TournamentStage({
    required this.name,
    required this.type,
    this.finalEndsTournament = true,
    this.knockoutLives,
    this.kratzerPlayersPerBoard,
    this.kratzerPreferSameScratchCount = false,
    this.kratzerPlayUntilElimination = false,
    this.kratzerBonusLifeFor180 = false,
    this.kratzerBonusLifeForHighFinish = false,
    this.kratzerHandicapsEnabled = false,
    this.kratzerHandicaps = const [],
    this.kratzerHandicapAssignments = const {},
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
    this.groupDrawCompleted = false,
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
    final groupSlotOrder = _nullableIntListFromJson(json['groupSlotOrder']);
    return TournamentStage(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'groups',
      finalEndsTournament: json['finalEndsTournament'] as bool? ?? false,
      knockoutLives: json['knockoutLives'] as int?,
      kratzerPlayersPerBoard: _kratzerPlayersPerBoardFromJson(
        json['kratzerPlayersPerBoard'],
      ),
      kratzerPreferSameScratchCount: _boolFromJson(
        json['kratzerPreferSameScratchCount'],
      ),
      kratzerPlayUntilElimination: _boolFromJson(
        json['kratzerPlayUntilElimination'],
      ),
      kratzerBonusLifeFor180: _boolFromJson(json['kratzerBonusLifeFor180']),
      kratzerBonusLifeForHighFinish: _boolFromJson(
        json['kratzerBonusLifeForHighFinish'],
      ),
      kratzerHandicapsEnabled: _boolFromJson(json['kratzerHandicapsEnabled']),
      kratzerHandicaps: _stringListFromJson(json['kratzerHandicaps']),
      kratzerHandicapAssignments: _intStringMapFromJson(
        json['kratzerHandicapAssignments'],
      ),
      placementPlaces: _intListFromJson(json['placementPlaces']),
      groupCount: json['groupCount'] as int?,
      groupSizes: _intListFromJson(json['groupSizes']),
      groupPlayType: json['groupPlayType'] as String? ?? 'round_robin',
      groupPlayTypes: _stringListFromJson(json['groupPlayTypes']),
      groupRoundRobinRepeats: _intListFromJson(json['groupRoundRobinRepeats']),
      groupMaxGamesPerPlayer: _nullableIntListFromJson(
        json['groupMaxGamesPerPlayer'],
      ),
      groupTieBreakers: _groupTieBreakersFromJson(json['groupTieBreakers']),
      groupDrawOnStart: json['groupDrawOnStart'] as bool? ?? false,
      groupSlotOrder: groupSlotOrder,
      groupDrawCompleted:
          json['groupDrawCompleted'] as bool? ?? groupSlotOrder.isNotEmpty,
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
  final int? kratzerPlayersPerBoard;
  final bool kratzerPreferSameScratchCount;
  final bool kratzerPlayUntilElimination;
  final bool kratzerBonusLifeFor180;
  final bool kratzerBonusLifeForHighFinish;
  final bool kratzerHandicapsEnabled;
  final List<String> kratzerHandicaps;
  final Map<int, String> kratzerHandicapAssignments;
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
  final bool groupDrawCompleted;
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
      if (kratzerPlayersPerBoard != null)
        'kratzerPlayersPerBoard': kratzerPlayersPerBoard,
      'kratzerPreferSameScratchCount': kratzerPreferSameScratchCount,
      'kratzerPlayUntilElimination': kratzerPlayUntilElimination,
      'kratzerBonusLifeFor180': kratzerBonusLifeFor180,
      'kratzerBonusLifeForHighFinish': kratzerBonusLifeForHighFinish,
      if (kratzerHandicapsEnabled || kratzerHandicaps.isNotEmpty)
        'kratzerHandicapsEnabled': kratzerHandicapsEnabled,
      if (kratzerHandicaps.isNotEmpty) 'kratzerHandicaps': kratzerHandicaps,
      if (kratzerHandicapAssignments.isNotEmpty)
        'kratzerHandicapAssignments': {
          for (final entry in kratzerHandicapAssignments.entries)
            entry.key.toString(): entry.value,
        },
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
      'groupDrawCompleted': groupDrawCompleted,
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

  TournamentStage copyWith({
    List<String>? groupTieBreakers,
    List<int?>? groupSlotOrder,
    bool? groupDrawCompleted,
    bool? kratzerHandicapsEnabled,
    List<String>? kratzerHandicaps,
    Map<int, String>? kratzerHandicapAssignments,
  }) => TournamentStage(
    name: name,
    type: type,
    finalEndsTournament: finalEndsTournament,
    knockoutLives: knockoutLives,
    kratzerPlayersPerBoard: kratzerPlayersPerBoard,
    kratzerPreferSameScratchCount: kratzerPreferSameScratchCount,
    kratzerPlayUntilElimination: kratzerPlayUntilElimination,
    kratzerBonusLifeFor180: kratzerBonusLifeFor180,
    kratzerBonusLifeForHighFinish: kratzerBonusLifeForHighFinish,
    kratzerHandicapsEnabled:
        kratzerHandicapsEnabled ?? this.kratzerHandicapsEnabled,
    kratzerHandicaps: kratzerHandicaps ?? this.kratzerHandicaps,
    kratzerHandicapAssignments:
        kratzerHandicapAssignments ?? this.kratzerHandicapAssignments,
    placementPlaces: placementPlaces,
    groupCount: groupCount,
    groupSizes: groupSizes,
    groupPlayType: groupPlayType,
    groupPlayTypes: groupPlayTypes,
    groupRoundRobinRepeats: groupRoundRobinRepeats,
    groupMaxGamesPerPlayer: groupMaxGamesPerPlayer,
    groupTieBreakers: groupTieBreakers ?? this.groupTieBreakers,
    groupDrawOnStart: groupDrawOnStart,
    groupSlotOrder: groupSlotOrder ?? this.groupSlotOrder,
    groupDrawCompleted: groupDrawCompleted ?? this.groupDrawCompleted,
    knockoutParticipantCount: knockoutParticipantCount,
    knockoutBracketSize: knockoutBracketSize,
    knockoutByeCount: knockoutByeCount,
    knockoutSlotOrder: knockoutSlotOrder,
    knockoutSeedingMode: knockoutSeedingMode,
    knockoutDrawOnStart: knockoutDrawOnStart,
    qualifiersByGroup: qualifiersByGroup,
    fixedQualifiersByGroup: fixedQualifiersByGroup,
    extraQualifierRank: extraQualifierRank,
    extraQualifierCount: extraQualifierCount,
    qualificationAutoAdjust: qualificationAutoAdjust,
    qualifiedParticipantCount: qualifiedParticipantCount,
    qualificationSummary: qualificationSummary,
    gameFormat: gameFormat,
  );
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
    bool countsForRanking = true,
    List<String> rankingIds = const [],
    this.activeStageIndex = 0,
    this.boardCount = 1,
    Map<int, String> directorBoardNames = const {},
    Map<int, String> directorBoardLiveUrls = const {},
    this.directorModeEnabled = false,
    this.directorSchedulingStrategy = 'group',
    this.showAchievementNotifications = true,
    this.showPlayerInsights = false,
    this.soundModeEnabled = false,
    Map<String, List<int>> directorGroupBoardAssignments = const {},
    Map<String, List<SecondScreenWidgetPlacement>> secondScreenLayouts =
        const {},
    this.secondScreenActiveLayout,
    this.syncRevision = 0,
    DateTime? tournamentDate,
    List<TournamentActivityEntry>? activityLog,
    List<PlayerWithdrawal>? withdrawals,
    Set<int>? blockedBoards,
    Map<String, List<int>>? groupBoardAssignments,
    this.startedAt,
    this.finishedAt,
    this.pausedAt,
    this.reopenedForCorrections = false,
    this.totalPausedSeconds = 0,
    this.plannedMinimumMinutes,
    this.plannedMinutes,
    this.plannedMatches,
    this.plannedMatchEndSeconds = const [],
    Set<int>? completedStageIndexes,
  }) : _countsForRanking = countsForRanking,
       id = id ?? _newTournamentId(),
       createdAt = createdAt ?? DateTime.now(),
       tournamentDate = tournamentDate == null
           ? null
           : DateTime(
               tournamentDate.year,
               tournamentDate.month,
               tournamentDate.day,
             ),
       updatedAt = updatedAt ?? DateTime.now(),
       completedStageIndexes = completedStageIndexes ?? <int>{},
       blockedBoards = blockedBoards ?? <int>{},
       groupBoardAssignments = {
         for (final entry in (groupBoardAssignments ?? const {}).entries)
           entry.key: List<int>.unmodifiable(entry.value),
       },
       directorBoardNames = Map<int, String>.from(directorBoardNames),
       directorBoardLiveUrls = Map<int, String>.from(directorBoardLiveUrls),
       secondScreenLayouts = {
         for (final entry in secondScreenLayouts.entries)
           entry.key: List<SecondScreenWidgetPlacement>.from(entry.value),
       },
       directorGroupBoardAssignments = {
         for (final entry in directorGroupBoardAssignments.entries)
           entry.key: List<int>.from(entry.value),
       },
       rankingIds = List<String>.from(rankingIds),
       withdrawals = withdrawals ?? [],
       activityLog = activityLog ?? [];

  CreatedTournament copy({String? name}) {
    final data = Map<String, dynamic>.from(toJson());
    data.remove('id');
    data.remove('createdAt');
    data.remove('updatedAt');
    if (name != null) {
      data['name'] = name;
    } else {
      data['name'] = '${this.name} - Kopie';
    }
    return CreatedTournament.fromJson(data);
  }

  factory CreatedTournament.fromJson(Map<String, dynamic> json) {
    return CreatedTournament(
      id: json['id'] as String?,
      createdAt: _dateTimeFromJson(json['createdAt']),
      tournamentDate: _dateTimeFromJson(json['tournamentDate']),
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
      directorBoardNames: {
        for (final entry in (json['directorBoardNames'] as Map? ?? {}).entries)
          if (int.tryParse(entry.key.toString()) case final board?)
            if (board >= 1 && board <= 64 && entry.value is String)
              board: entry.value as String,
      },
      directorBoardLiveUrls: {
        for (final entry
            in (json['directorBoardLiveUrls'] as Map? ?? {}).entries)
          if (int.tryParse(entry.key.toString()) case final board?)
            if (board >= 1 && board <= 64 && entry.value is String)
              board: entry.value as String,
      },
      directorModeEnabled: json['directorModeEnabled'] as bool? ?? false,
      directorSchedulingStrategy: _directorSchedulingStrategyFromJson(
        json['directorSchedulingStrategy'],
      ),
      showAchievementNotifications:
          json['showAchievementNotifications'] as bool? ?? true,
      showPlayerInsights: json['showPlayerInsights'] as bool? ?? false,
      soundModeEnabled: json['soundModeEnabled'] as bool? ?? false,
      directorGroupBoardAssignments: {
        for (final entry
            in (json['directorGroupBoardAssignments'] as Map? ?? {}).entries)
          if (entry.key is String && entry.value is List)
            entry.key as String:
                (entry.value as List)
                    .whereType<int>()
                    .where((board) => board >= 1 && board <= 64)
                    .toSet()
                    .toList()
                  ..sort(),
      },
      secondScreenLayouts: {
        for (final entry in (json['secondScreenLayouts'] as Map? ?? {}).entries)
          if (entry.key is String && entry.value is List)
            entry.key as String: [
              for (final item in entry.value as List)
                if (item is Map<String, dynamic>)
                  SecondScreenWidgetPlacement.fromJson(item),
            ],
      },
      secondScreenActiveLayout: json['secondScreenActiveLayout'] as String?,
      syncRevision: json['syncRevision'] as int? ?? 0,
      activityLog: [
        for (final item in json['activityLog'] as List? ?? const [])
          if (item is Map<String, dynamic>)
            TournamentActivityEntry.fromJson(item),
      ],
      withdrawals: _mapListFromJson(
        json['withdrawals'],
        PlayerWithdrawal.fromJson,
      ),
      blockedBoards: _intListFromJson(
        json['blockedBoards'],
      ).where((b) => b >= 1 && b <= 64).toSet(),
      groupBoardAssignments: json['groupBoardAssignments'] is Map
          ? (json['groupBoardAssignments'] as Map).map(
              (key, value) => MapEntry(
                key.toString(),
                _intListFromJson(
                  value,
                ).where((board) => board >= 1 && board <= 64).toList(),
              ),
            )
          : const {},
      startedAt: _dateTimeFromJson(json['startedAt']),
      finishedAt: _dateTimeFromJson(json['finishedAt']),
      pausedAt: _dateTimeFromJson(json['pausedAt']),
      reopenedForCorrections: json['reopenedForCorrections'] as bool? ?? false,
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
  DateTime? tournamentDate;
  DateTime updatedAt;
  final List<TournamentPlayer> players;
  final List<TournamentStage> stages;
  final List<TournamentRunStage> runStages;
  final LeagueMatch? leagueMatch;
  final ImportedTournamentArchive? importedArchive;
  bool _countsForRanking;
  bool get isKratzerTournament =>
      stages.any((stage) => stage.type == 'kratzer');
  bool get countsForRanking =>
      leagueMatch == null && !isKratzerTournament && _countsForRanking;
  set countsForRanking(bool value) => _countsForRanking = value;
  List<String> rankingIds;
  int activeStageIndex;
  int boardCount;
  final Map<int, String> directorBoardNames;
  final Map<int, String> directorBoardLiveUrls;
  bool directorModeEnabled;
  String directorSchedulingStrategy;
  bool showAchievementNotifications;
  bool showPlayerInsights;
  bool soundModeEnabled;
  final Map<String, List<int>> directorGroupBoardAssignments;
  final Map<String, List<SecondScreenWidgetPlacement>> secondScreenLayouts;
  String? secondScreenActiveLayout;
  int syncRevision;
  final List<PlayerWithdrawal> withdrawals;
  final List<TournamentActivityEntry> activityLog;
  final Set<int> blockedBoards;
  final Map<String, List<int>> groupBoardAssignments;
  DateTime? startedAt, finishedAt, pausedAt;
  bool reopenedForCorrections;
  int totalPausedSeconds;
  bool get isClockPaused => pausedAt != null;
  DateTime get effectiveDate => tournamentDate ?? startedAt ?? createdAt;

  void addActivity(String type, String message, {DateTime? timestamp}) {
    activityLog.add(
      TournamentActivityEntry(
        type: type,
        message: message,
        timestamp: timestamp ?? DateTime.now(),
      ),
    );
  }

  int? plannedMinimumMinutes;
  int? plannedMinutes, plannedMatches;
  List<int> plannedMatchEndSeconds;
  final Set<int> completedStageIndexes;

  String boardDisplayName(int board) {
    final name = directorBoardNames[board]?.trim();
    return name == null || name.isEmpty ? 'Board $board' : name;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (withdrawals.isNotEmpty)
        'withdrawals': withdrawals.map((w) => w.toJson()).toList(),
      'name': name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (tournamentDate != null)
        'tournamentDate': DateTime(
          tournamentDate!.year,
          tournamentDate!.month,
          tournamentDate!.day,
        ).toIso8601String(),
      if (activityLog.isNotEmpty)
        'activityLog': activityLog.map((entry) => entry.toJson()).toList(),
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
      if (directorBoardNames.isNotEmpty)
        'directorBoardNames': {
          for (final entry in directorBoardNames.entries)
            if (entry.value.trim().isNotEmpty)
              entry.key.toString(): entry.value.trim(),
        },
      if (directorBoardLiveUrls.isNotEmpty)
        'directorBoardLiveUrls': {
          for (final entry in directorBoardLiveUrls.entries)
            if (entry.value.trim().isNotEmpty)
              entry.key.toString(): entry.value.trim(),
        },
      if (directorModeEnabled) 'directorModeEnabled': true,
      if (directorSchedulingStrategy != 'group')
        'directorSchedulingStrategy': directorSchedulingStrategy,
      if (!showAchievementNotifications) 'showAchievementNotifications': false,
      if (showPlayerInsights) 'showPlayerInsights': true,
      if (soundModeEnabled) 'soundModeEnabled': true,
      if (directorGroupBoardAssignments.isNotEmpty)
        'directorGroupBoardAssignments': {
          for (final entry in directorGroupBoardAssignments.entries)
            entry.key: entry.value.toSet().toList()..sort(),
        },
      if (secondScreenLayouts.isNotEmpty)
        'secondScreenLayouts': {
          for (final entry in secondScreenLayouts.entries)
            entry.key: entry.value
                .map((placement) => placement.toJson())
                .toList(),
        },
      if (secondScreenActiveLayout != null)
        'secondScreenActiveLayout': secondScreenActiveLayout,
      if (syncRevision != 0) 'syncRevision': syncRevision,
      if (blockedBoards.isNotEmpty)
        'blockedBoards': blockedBoards.toList()..sort(),
      if (groupBoardAssignments.isNotEmpty)
        'groupBoardAssignments': {
          for (final entry in groupBoardAssignments.entries)
            entry.key: entry.value.toList()..sort(),
        },
      'startedAt': startedAt?.toUtc().toIso8601String(),
      'finishedAt': finishedAt?.toUtc().toIso8601String(),
      if (pausedAt != null) 'pausedAt': pausedAt?.toUtc().toIso8601String(),
      if (reopenedForCorrections) 'reopenedForCorrections': true,
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
    this.isKratzer = false,
    this.kratzerPlayersPerBoard,
    this.kratzerPreferSameScratchCount = false,
    this.kratzerPlayUntilElimination = false,
    this.kratzerBonusLifeFor180 = false,
    this.kratzerBonusLifeForHighFinish = false,
    this.kratzerHandicapsEnabled = false,
    this.kratzerHandicaps = const [],
    this.kratzerHandicapAssignments = const {},
    this.participants = const [],
  });

  final List<List<GroupMatch>> rounds;
  final List<GroupMatch> placementMatches;
  final int eliminationLossLimit;
  final bool finalEndsTournament;
  final bool isKratzer;
  final int? kratzerPlayersPerBoard;
  final bool kratzerPreferSameScratchCount;
  final bool kratzerPlayUntilElimination;
  final bool kratzerBonusLifeFor180;
  final bool kratzerBonusLifeForHighFinish;
  final bool kratzerHandicapsEnabled;
  final List<String> kratzerHandicaps;
  final Map<int, String> kratzerHandicapAssignments;
  final List<TournamentPlayer> participants;

  List<GroupMatch> get matches => [
    for (final round in rounds) ...round,
    ...placementMatches,
  ];

  int scratchesFor(TournamentPlayer player) =>
      player.kratzerStartingScratches +
      matches.where((match) => match.scratchedPlayer == player).length;

  int bonusLivesFor(TournamentPlayer player) => matches
      .expand((match) => match.kratzerBonusLives)
      .where((bonus) => bonus.player == player)
      .length;

  int livesRemainingFor(TournamentPlayer player) {
    final remaining =
        eliminationLossLimit - scratchesFor(player) + bonusLivesFor(player);
    return remaining < 0 ? 0 : remaining;
  }

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
      if (isKratzer) 'isKratzer': true,
      if (kratzerPlayersPerBoard != null)
        'kratzerPlayersPerBoard': kratzerPlayersPerBoard,
      if (isKratzer) ...{
        'kratzerPreferSameScratchCount': kratzerPreferSameScratchCount,
        'kratzerPlayUntilElimination': kratzerPlayUntilElimination,
        'kratzerBonusLifeFor180': kratzerBonusLifeFor180,
        'kratzerBonusLifeForHighFinish': kratzerBonusLifeForHighFinish,
        if (kratzerHandicapsEnabled || kratzerHandicaps.isNotEmpty)
          'kratzerHandicapsEnabled': kratzerHandicapsEnabled,
        if (kratzerHandicaps.isNotEmpty) 'kratzerHandicaps': kratzerHandicaps,
        if (kratzerHandicapAssignments.isNotEmpty)
          'kratzerHandicapAssignments': {
            for (final entry in kratzerHandicapAssignments.entries)
              entry.key.toString(): entry.value,
          },
      },
      if (participants.isNotEmpty)
        'participants': participants.map((player) => player.toJson()).toList(),
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
    final storedMatchesByKey = <String, GroupMatch>{};
    for (final match in storedMatches) {
      storedMatchesByKey.putIfAbsent(jsonEncode(match.toJson()), () => match);
    }
    GroupMatch restoreMatchReference(GroupMatch match) =>
        storedMatchesByKey[jsonEncode(match.toJson())] ?? match;
    final rounds = _matchRoundsFromJson(
      json['knockoutRounds'],
    ).map((round) => round.map(restoreMatchReference).toList()).toList();
    final placements = _mapListFromJson(
      json['placementMatches'],
      GroupMatch.fromJson,
    ).map(restoreMatchReference).toList();
    final matches = <GroupMatch>[];
    final seenMatches = <GroupMatch>{};
    void addMatch(GroupMatch match) {
      if (seenMatches.add(match)) matches.add(match);
    }

    for (final match in storedMatches) {
      addMatch(match);
    }
    for (final match in rounds.expand((round) => round)) {
      addMatch(match);
    }
    for (final match in placements) {
      addMatch(match);
    }
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

enum KratzerBonusLifeType { score180, highFinish }

class KratzerBonusLife {
  const KratzerBonusLife({required this.player, required this.type});

  factory KratzerBonusLife.fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'score180' => KratzerBonusLifeType.score180,
      'highFinish' => KratzerBonusLifeType.highFinish,
      _ => throw const FormatException('Ungültiger Kratzer-Bonusleben-Typ'),
    };
    final player = _playerFromJson(json['player']);
    if (player == null) {
      throw const FormatException('Spieler für Kratzer-Bonusleben fehlt');
    }
    return KratzerBonusLife(player: player, type: type);
  }

  final TournamentPlayer player;
  final KratzerBonusLifeType type;

  Map<String, dynamic> toJson() => {
    'player': player.toJson(),
    'type': type.name,
  };
}

class GroupMatch {
  GroupMatch({
    this.homePlayer,
    this.awayPlayer,
    this.players = const [],
    this.scratchedPlayer,
    this.scratchEligiblePlayers = const [],
    this.isKratzer = false,
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
    List<TournamentAchievementNotice>? achievementNotifications,
    this.kratzerBonusLives = const [],
  }) : achievementNotifications = List<TournamentAchievementNotice>.of(
         achievementNotifications ?? const [],
       );

  factory GroupMatch.fromJson(Map<String, dynamic> json) {
    return GroupMatch(
      homePlayer: _playerFromJson(json['homePlayer']),
      awayPlayer: _playerFromJson(json['awayPlayer']),
      players: _mapListFromJson(json['players'], TournamentPlayer.fromJson),
      scratchedPlayer: _playerFromJson(json['scratchedPlayer']),
      scratchEligiblePlayers: _mapListFromJson(
        json['scratchEligiblePlayers'],
        TournamentPlayer.fromJson,
      ),
      isKratzer: json['isKratzer'] == true,
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
      achievementNotifications:
          (json['achievementNotifications'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) => TournamentAchievementNotice.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(),
      kratzerBonusLives: _mapListFromJson(
        json['kratzerBonusLives'],
        KratzerBonusLife.fromJson,
      ),
    );
  }

  TournamentPlayer? homePlayer;
  TournamentPlayer? awayPlayer;
  List<TournamentPlayer> players;
  TournamentPlayer? scratchedPlayer;
  List<TournamentPlayer> scratchEligiblePlayers;
  bool isKratzer;
  final int round;
  int? homeLegs;
  int? awayLegs;
  int? homeSets;
  int? awaySets;
  bool get hasSetScore => homeSets != null && awaySets != null;
  int? get homeScore => hasSetScore ? homeSets : homeLegs;
  int? get awayScore => hasSetScore ? awaySets : awayLegs;
  String get scoreLabel => isKratzer
      ? scratchedPlayer == null
            ? 'Noch offen'
            : 'Kratzer: ${scratchedPlayer!.name}'
      : withdrawalIgnored
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
  List<TournamentAchievementNotice> achievementNotifications;
  List<KratzerBonusLife> kratzerBonusLives;
  bool get countsForStatistics => hasResult && !withdrawalIgnored;

  bool get hasPlayers => isKratzer
      ? players.length >= 3 && players.length <= 6
      : homePlayer != null && awayPlayer != null;
  String get participantLabel => isKratzer
      ? players.map((player) => player.name).join(' · ')
      : '${homePlayer?.name ?? 'Offen'} – ${awayPlayer?.name ?? 'Offen'}';
  String get participantShortLabel => isKratzer
      ? players.map((player) => player.shortDisplayName).join(' · ')
      : '${homePlayer?.shortDisplayName ?? 'Offen'} – ${awayPlayer?.shortDisplayName ?? 'Offen'}';
  bool get hasScore => isKratzer
      ? scratchedPlayer != null
      : hasPlayers && homeLegs != null && awayLegs != null;
  bool get hasResult =>
      isKratzer ? scratchedPlayer != null : hasScore && !isAnnulled;
  bool get isResolved => isAnnulled || hasResult || winner != null;

  TournamentPlayer? get winner {
    if (isKratzer) return null;
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
    if (isKratzer) return scratchedPlayer;
    final winningPlayer = winner;
    if (winningPlayer == null || !hasResult) {
      return null;
    }

    return winningPlayer == homePlayer ? awayPlayer : homePlayer;
  }

  Map<String, dynamic> toJson() {
    return {
      if (players.isNotEmpty)
        'players': players.map((player) => player.toJson()).toList(),
      if (scratchedPlayer != null) 'scratchedPlayer': scratchedPlayer!.toJson(),
      if (scratchEligiblePlayers.isNotEmpty)
        'scratchEligiblePlayers': scratchEligiblePlayers
            .map((player) => player.toJson())
            .toList(),
      if (isKratzer) 'isKratzer': true,
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
      if (achievementNotifications.isNotEmpty)
        'achievementNotifications': achievementNotifications
            .map((item) => item.toJson())
            .toList(),
      if (kratzerBonusLives.isNotEmpty)
        'kratzerBonusLives': kratzerBonusLives
            .map((bonus) => bonus.toJson())
            .toList(),
    };
  }
}

class TournamentAchievementNotice {
  const TournamentAchievementNotice({
    required this.playerProfileId,
    required this.playerName,
    required this.achievementName,
    required this.explanation,
    required this.rankingName,
  });

  factory TournamentAchievementNotice.fromJson(Map<String, dynamic> json) =>
      TournamentAchievementNotice(
        playerProfileId: json['playerProfileId'] as String? ?? '',
        playerName: json['playerName'] as String? ?? '',
        achievementName: json['achievementName'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
        rankingName: json['rankingName'] as String? ?? '',
      );

  final String playerProfileId;
  final String playerName;
  final String achievementName;
  final String explanation;
  final String rankingName;

  Map<String, dynamic> toJson() => {
    'playerProfileId': playerProfileId,
    'playerName': playerName,
    'achievementName': achievementName,
    'explanation': explanation,
    'rankingName': rankingName,
  };
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
