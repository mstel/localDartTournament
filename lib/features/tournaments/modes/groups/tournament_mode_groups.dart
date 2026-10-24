part of '../../../../tournament_workspace.dart';

const List<String> defaultGroupTieBreakers = [
  'points',
  'headToHead',
  'legDifference',
  'legsFor',
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

int _roundRobinRepeatForStage(TournamentStage stage, int groupIndex) {
  if (groupIndex < 0 || groupIndex >= stage.groupRoundRobinRepeats.length) {
    return 1;
  }

  final repeatCount = stage.groupRoundRobinRepeats[groupIndex];
  return repeatCount < 1 ? 1 : repeatCount;
}

String _groupPlayTypeForStage(TournamentStage stage, int groupIndex) {
  if (groupIndex >= 0 && groupIndex < stage.groupPlayTypes.length) {
    return stage.groupPlayTypes[groupIndex];
  }

  return stage.groupPlayType;
}

String _groupPlayTypeLabel(String playType) {
  return switch (playType) {
    'round_robin' => 'Jeder gegen jeden',
    'swiss' => 'Schweizer System',
    'mini_knockout' => 'Mini-KO in der Gruppe',
    'double_knockout' => 'Doppel-KO in der Gruppe',
    'triple_knockout' => 'Triple-KO in der Gruppe',
    _ => playType,
  };
}

bool _isEliminationGroupPlayType(String playType) {
  return playType == 'mini_knockout' ||
      playType == 'double_knockout' ||
      playType == 'triple_knockout';
}

int _lossLimitForGroupPlayType(String playType) {
  return switch (playType) {
    'double_knockout' => 2,
    'triple_knockout' => 3,
    _ => 1,
  };
}

List<TournamentGroup> _buildTournamentGroupsForPlayers(
  TournamentStage stage,
  List<TournamentPlayer> players, {
  required int Function(TournamentStage stage, int groupIndex)
      requiredRankForGroup,
}) {
  final groups = <TournamentGroup>[];
  final playersByGroup = GroupDrawAssignment.partitionDraw(
    items: players,
    slotOrder: stage.groupSlotOrder,
    groupSizes: stage.groupSizes,
  );

  for (var groupIndex = 0; groupIndex < stage.groupSizes.length; groupIndex++) {
    final groupPlayType = _groupPlayTypeForStage(stage, groupIndex);
    final groupPlayers = playersByGroup[groupIndex];

    if (_isEliminationGroupPlayType(groupPlayType)) {
      groups.add(
        _buildEliminationTournamentGroup(
          stage: stage,
          groupIndex: groupIndex,
          playType: groupPlayType,
          players: groupPlayers,
          requiredRankForGroup: requiredRankForGroup,
        ),
      );
    } else {
      groups.add(
        TournamentGroup(
          name: groupLabel(groupIndex + 1),
          playType: groupPlayType,
          players: groupPlayers,
          matches: groupPlayType == 'swiss'
              ? SwissEngine.build(groupPlayers, _roundRobinRepeatForStage(stage, groupIndex).clamp(1, SwissEngine.maximumRounds(groupPlayers.length)))
              : _buildRoundRobinMatches(
            groupPlayers,
            repeatCount: _roundRobinRepeatForStage(stage, groupIndex),
            maxGamesPerPlayer: stage.maxGamesForGroup(groupIndex),
          ),
        ),
      );
    }
  }

  return groups;
}

TournamentGroup _buildEliminationTournamentGroup({
  required TournamentStage stage,
  required int groupIndex,
  required String playType,
  required List<TournamentPlayer> players,
  required int Function(TournamentStage stage, int groupIndex)
      requiredRankForGroup,
}) {
  final lossLimit = _lossLimitForGroupPlayType(playType);
  final requiredRank = requiredRankForGroup(stage, groupIndex);
  final rounds = lossLimit == 1
      ? _buildKnockoutRoundsForPlayers(players, qualifyingRank: stage.placementPlaces.isEmpty ? requiredRank : 1)
      : lossLimit == 2
          ? _buildDoubleEliminationRoundsForPlayers(players)
          : _buildTripleEliminationRoundsForPlayers(players);
  final placementMatches = lossLimit == 1
      ? stage.placementPlaces.isNotEmpty ? PlacementEngine.build(rounds, {...stage.placementPlaces.where((p) => p < players.length), if (requiredRank >= 3 && requiredRank.isOdd && requiredRank < players.length) requiredRank}) : _buildPlacementMatchesForPlayers(
          players.length,
          requiredRank,
        )
      : const <GroupMatch>[];

  return TournamentGroup(
    name: groupLabel(groupIndex + 1),
    playType: playType,
    players: players,
    matches: [
      for (final round in rounds) ...round,
      ...placementMatches,
    ],
    knockoutRounds: rounds,
    placementMatches: placementMatches,
    eliminationLossLimit: lossLimit,
    finalEndsTournament: stage.finalEndsTournament,
  );
}

List<GroupMatch> _buildRoundRobinMatches(
  List<TournamentPlayer> players, {
  int repeatCount = 1,
  int? maxGamesPerPlayer,
}) {
  return tournamentEngine.buildRoundRobinMatches(
    players,
    repeatCount: repeatCount,
    maxGamesPerPlayer: maxGamesPerPlayer,
  );
}

int _roundRobinMatchCount(int groupSize, int repeatCount, {int? maxGamesPerPlayer}) {
  return tournamentEngine.roundRobinMatchCount(groupSize, repeatCount, maxGamesPerPlayer: maxGamesPerPlayer);
}

int _groupEliminationMatchEstimate(
  int participantCount,
  int lossLimit,
  int qualifyingRank,
) {
  if (participantCount < 2 || qualifyingRank >= participantCount) {
    return 0;
  }

  if (lossLimit > 1) {
    return (participantCount - qualifyingRank) * lossLimit;
  }

  final players = [
    for (var index = 0; index < participantCount; index++)
      TournamentPlayer.generated(index + 1),
  ];
  final rounds = _buildKnockoutRoundsForPlayers(
    players,
    qualifyingRank: qualifyingRank,
  );
  final placementMatches = _buildPlacementMatchesForPlayers(
    participantCount,
    qualifyingRank,
  );
  return _playableKnockoutMatchCount(rounds) + placementMatches.length;
}

int _playableKnockoutMatchCount(List<List<GroupMatch>> rounds) {
  var count = 0;
  for (var roundIndex = 0; roundIndex < rounds.length; roundIndex++) {
    for (final match in rounds[roundIndex]) {
      if (roundIndex == 0) {
        if (match.homePlayer != null && match.awayPlayer != null) {
          count++;
        }
      } else {
        count++;
      }
    }
  }
  return count;
}

List<GroupMatch> _buildPlacementMatchesForPlayers(
  int participantCount,
  int requiredRank,
) {
  if (participantCount < 4 || requiredRank < 3) {
    return const [];
  }

  final matches = <GroupMatch>[];

  if (requiredRank == 3) {
    matches.add(GroupMatch(round: 100, label: 'Spiel um Platz 3'));
  }

  if (participantCount >= 8 && requiredRank >= 5) {
    if (requiredRank <= 7) {
      matches.addAll([
        GroupMatch(round: 101, label: 'Platz 5 Halbfinale 1'),
        GroupMatch(round: 101, label: 'Platz 5 Halbfinale 2'),
      ]);
    }
    if (requiredRank == 5) {
      matches.add(GroupMatch(round: 102, label: 'Spiel um Platz 5'));
    }
    if (requiredRank == 7) {
      matches.add(GroupMatch(round: 102, label: 'Spiel um Platz 7'));
    }
  }

  return matches;
}

List<List<GroupMatch>> _buildKnockoutRoundsForPlayers(
  List<TournamentPlayer> players, {
  List<int?> slotOrder = const [],
  int qualifyingRank = 1,
}) {
  if (players.length < 2 || qualifyingRank >= players.length) {
    return const [];
  }

  var bracketSize = 2;
  while (bracketSize < players.length) {
    bracketSize *= 2;
  }

  final slots =
      _isValidGroupSlotOrder(slotOrder, players.length, bracketSize) &&
          _groupSlotOrderAvoidsByePair(slotOrder)
      ? List<int?>.from(slotOrder)
      : _automaticGroupSlotOrder(players.length, bracketSize);
  final rounds = <List<GroupMatch>>[];
  final firstRound = <GroupMatch>[];
  for (var index = 0; index < bracketSize; index += 2) {
    final homeSeed = slots[index];
    final awaySeed = slots[index + 1];
    firstRound.add(
      GroupMatch(
        homePlayer: homeSeed == null ? null : players[homeSeed - 1],
        awayPlayer: awaySeed == null ? null : players[awaySeed - 1],
        round: 1,
        allowsBye: true,
      ),
    );
  }
  rounds.add(firstRound);

  final safeQualifyingRank = qualifyingRank < 1 ? 1 : qualifyingRank;
  var remainingSlots = firstRound.length;
  var roundNumber = 2;
  while (remainingSlots > safeQualifyingRank) {
    final matchesInRound = remainingSlots ~/ 2;
    if (matchesInRound < 1) {
      break;
    }
    rounds.add(
      List.generate(matchesInRound, (_) => GroupMatch(round: roundNumber)),
    );
    remainingSlots = matchesInRound;
    roundNumber++;
  }

  _advanceKnockoutWinnersInBuiltRounds(rounds);
  return rounds;
}

List<List<GroupMatch>> _buildDoubleEliminationRoundsForPlayers(
  List<TournamentPlayer> players, {
  List<int?> slotOrder = const [],
}) {
  if (players.length < 2) {
    return const [];
  }

  var bracketSize = 2;
  while (bracketSize < players.length) {
    bracketSize *= 2;
  }

  final slots =
      _isValidGroupSlotOrder(slotOrder, players.length, bracketSize) &&
          _groupSlotOrderAvoidsByePair(slotOrder)
      ? List<int?>.from(slotOrder)
      : _automaticGroupSlotOrder(players.length, bracketSize);
  return _buildDoubleEliminationRoundsFromSlots(players, slots);
}

List<List<GroupMatch>> _buildTripleEliminationRoundsForPlayers(
  List<TournamentPlayer> players, {
  int lossLimit = 3,
  List<int?> slotOrder = const [],
}) {
  if (players.length < 2) {
    return const [];
  }

  var bracketSize = 2;
  while (bracketSize < players.length) {
    bracketSize *= 2;
  }

  final slots =
      _isValidGroupSlotOrder(slotOrder, players.length, bracketSize) &&
          _groupSlotOrderAvoidsByePair(slotOrder)
      ? List<int?>.from(slotOrder)
      : _automaticGroupSlotOrder(players.length, bracketSize);
  return _buildTripleEliminationRoundsFromSlots(players, slots, lossLimit: lossLimit);
}

void _advanceKnockoutWinnersInBuiltRounds(List<List<GroupMatch>> rounds) {
  for (var roundIndex = 0; roundIndex < rounds.length - 1; roundIndex++) {
    final currentRound = rounds[roundIndex];
    final nextRound = rounds[roundIndex + 1];
    for (var matchIndex = 0; matchIndex < currentRound.length; matchIndex++) {
      final winner = currentRound[matchIndex].winner;
      if (winner == null) {
        continue;
      }

      final targetMatch = nextRound[matchIndex ~/ 2];
      if (matchIndex.isEven) {
        targetMatch.homePlayer = winner;
      } else {
        targetMatch.awayPlayer = winner;
      }
    }
  }
}

List<int?> _automaticGroupSlotOrder(int participantCount, int bracketSize) {
  return [
    for (final seed in _seedOrderForSize(bracketSize))
      seed <= participantCount ? seed : null,
  ];
}

bool _isValidGroupSlotOrder(
  List<int?> slotOrder,
  int participantCount,
  int bracketSize,
) {
  if (slotOrder.length != bracketSize) {
    return false;
  }

  final values = slotOrder.whereType<int>().toList()..sort();
  if (values.length != participantCount) {
    return false;
  }

  for (var index = 0; index < values.length; index++) {
    if (values[index] != index + 1) {
      return false;
    }
  }

  return true;
}

bool _groupSlotOrderAvoidsByePair(List<int?> slotOrder) {
  for (var index = 0; index < slotOrder.length; index += 2) {
    final first = slotOrder[index];
    final second = index + 1 < slotOrder.length ? slotOrder[index + 1] : null;
    if (first == null && second == null) {
      return false;
    }
  }
  return true;
}
