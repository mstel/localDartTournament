part of '../../../../../../tournament_workspace.dart';

class _KnockoutBracketView extends StatelessWidget {
  const _KnockoutBracketView({
    required this.stage,
    required this.qualifyingRank,
    required this.onEditResult,
    required this.canEditResults,
    this.placementMatches = const [],
    this.isEditMode = false,
    this.onSwapSlot,
  });

  final KnockoutTournamentRunStage stage;
  final List<GroupMatch> placementMatches;
  final int qualifyingRank;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResults;
  final bool isEditMode;
  final void Function(int fromSlotIndex, int toSlotIndex)? onSwapSlot;

  @override
  Widget build(BuildContext context) {
    if (placementMatches.any((m) => m.placementKey != null)) {
      final edges = PlacementEngine.sources(stage.rounds, placementMatches);
      final rounds = <List<GroupMatch>>[
        for (final number
            in placementMatches.map((m) => m.round).toSet().toList()..sort())
          placementMatches.where((m) => m.round == number).toList(),
      ];
      final numbers = _stageMatchNumbers([...stage.rounds, ...rounds]);
      String sourceName(PlacementSource source) =>
          '${source.loser ? 'Verlierer' : 'Gewinner'} Spiel ${numbers[source.match] ?? '?'}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KnockoutBracketView(
            stage: stage,
            qualifyingRank: qualifyingRank,
            onEditResult: onEditResult,
            canEditResults: canEditResults,
            isEditMode: isEditMode,
            onSwapSlot: onSwapSlot,
          ),
          const SizedBox(height: 24),
          const _BracketBandTitle(title: 'Platzierungsspiele'),
          _BracketTreeLayout(
            totalRounds: rounds.length,
            columnWidth: 260,
            cardHeight: 224,
            firstRoundGap: 12,
            useBalancedColumnLayout: true,
            roundMatches: rounds,
            sourceMatches: {
              for (final e in edges.entries)
                e.key: (first: e.value.home.match, second: e.value.away.match),
            },
            roundTitles: [
              for (var i = 0; i < rounds.length; i++)
                'Platzierung · ${knockoutRoundName(i, rounds.length)}',
            ],
            roundCards: [
              for (var i = 0; i < rounds.length; i++)
                [
                  for (var j = 0; j < rounds[i].length; j++)
                    _KnockoutBracketMatchCard(
                      match: rounds[i][j],
                      matchNumber: numbers[rounds[i][j]]!,
                      homeSourceLabel: sourceName(edges[rounds[i][j]]!.home),
                      awaySourceLabel: sourceName(edges[rounds[i][j]]!.away),
                      roundIndex: i,
                      matchIndex: j,
                      totalRounds: rounds.length,
                      qualifyingRank: 0,
                      qualificationLabel: rounds[i][j].label,
                      onEditResult: onEditResult,
                      canEditResult: canEditResults,
                      isEditMode: false,
                    ),
                ],
            ],
          ),
        ],
      );
    }
    if (stage.eliminationLossLimit == 2) {
      final matchNumbers = _stageMatchNumbers(stage.rounds);
      final sourceMatches = _stageSourceMatches(stage);
      final sourceLabels = _deferUnresolvedSourcePlayerLabels(
        _stageSourceLabels(stage, matchNumbers),
        sourceMatches,
        matchNumbers,
      );
      return _DoubleEliminationBracketView(
        stage: stage,
        matchNumbers: matchNumbers,
        sourceLabels: sourceLabels,
        sourceMatches: sourceMatches,
        qualifyingRank: qualifyingRank,
        onEditResult: onEditResult,
        canEditResults: canEditResults,
        isEditMode: isEditMode,
        onSwapSlot: onSwapSlot,
      );
    }
    if (stage.eliminationLossLimit >= 3) {
      final matchNumbers = _stageMatchNumbers(stage.rounds);
      final sourceMatches = _stageSourceMatches(stage);
      final sourceLabels = _deferUnresolvedSourcePlayerLabels(
        _stageSourceLabels(stage, matchNumbers),
        sourceMatches,
        matchNumbers,
      );
      return _TripleEliminationBracketView(
        stage: stage,
        matchNumbers: matchNumbers,
        sourceLabels: sourceLabels,
        sourceMatches: sourceMatches,
        qualifyingRank: qualifyingRank,
        onEditResult: onEditResult,
        canEditResults: canEditResults,
        isEditMode: isEditMode,
        onSwapSlot: onSwapSlot,
      );
    }

    final displayRounds = _singleKnockoutRoundsWithPlacement(
      stage.rounds,
      placementMatches,
    );
    final matchNumbers = _stageMatchNumbers(displayRounds);
    final sourceMatches = {
      ..._singleKnockoutSourceMatches(displayRounds),
      ..._singleKnockoutPlacementSourceMatches(stage.rounds, placementMatches),
    };
    final sourceLabels = _deferUnresolvedSourcePlayerLabels(
      {
        ..._singleKnockoutSourceLabels(displayRounds, matchNumbers),
        ..._singleKnockoutPlacementSourceLabels(
          stage.rounds,
          placementMatches,
          matchNumbers,
        ),
      },
      sourceMatches,
      matchNumbers,
    );

    return _BracketTreeLayout(
      totalRounds: displayRounds.length,
      columnWidth: 260,
      cardHeight: 224,
      firstRoundGap: 12,
      useBalancedColumnLayout: stage.eliminationLossLimit > 1,
      roundMatches: displayRounds,
      sourceMatches: sourceMatches,
      roundTitles: [
        for (var index = 0; index < displayRounds.length; index++)
          stage.eliminationLossLimit == 2
              ? displayRounds[index]
                    .map((m) => knockoutMatchName(m, stage.matches))
                    .toSet()
                    .join(' / ')
              : stage.eliminationLossLimit > 1
              ? displayRounds[index]
                    .map((m) => knockoutMatchName(m, stage.matches))
                    .toSet()
                    .join(' / ')
              : _singleKnockoutColumnTitle(
                  displayRounds[index],
                  index,
                  displayRounds.length,
                ),
      ],
      roundCards: [
        for (
          var roundIndex = 0;
          roundIndex < displayRounds.length;
          roundIndex++
        )
          [
            for (
              var matchIndex = 0;
              matchIndex < displayRounds[roundIndex].length;
              matchIndex++
            )
              _KnockoutBracketMatchCard(
                match: displayRounds[roundIndex][matchIndex],
                matchNumber:
                    matchNumbers[displayRounds[roundIndex][matchIndex]] ??
                    matchIndex + 1,
                homeSourceLabel:
                    sourceLabels[displayRounds[roundIndex][matchIndex]]?.first,
                awaySourceLabel:
                    sourceLabels[displayRounds[roundIndex][matchIndex]]?.second,
                roundIndex: roundIndex,
                matchIndex: matchIndex,
                totalRounds: displayRounds.length,
                qualifyingRank: qualifyingRank,
                qualificationLabel: _singleKnockoutQualificationLabel(
                  displayRounds[roundIndex][matchIndex],
                  sourceMatches,
                  qualifyingRank,
                  roundIndex,
                  displayRounds.length,
                ),
                onEditResult: onEditResult,
                canEditResult: canEditResults,
                isEditMode: isEditMode,
                onSwapSlot: onSwapSlot,
              ),
          ],
      ],
    );
  }
}

List<List<GroupMatch>> _singleKnockoutRoundsWithPlacement(
  List<List<GroupMatch>> rounds,
  List<GroupMatch> placementMatches,
) {
  if (placementMatches.isEmpty) {
    return rounds;
  }
  if (rounds.isEmpty) {
    return [placementMatches];
  }

  final displayRounds = [
    for (final round in rounds) List<GroupMatch>.from(round),
  ];
  final fifthSemis = placementMatches
      .where((match) => match.label?.startsWith('Platz 5 Halbfinale') ?? false)
      .toList();
  final finalColumnMatches = placementMatches
      .where(
        (match) =>
            match.label == 'Spiel um Platz 3' ||
            match.label == 'Spiel um Platz 5' ||
            match.label == 'Spiel um Platz 7',
      )
      .toList();

  if (fifthSemis.isNotEmpty) {
    final targetIndex = displayRounds.length >= 2
        ? displayRounds.length - 2
        : displayRounds.length - 1;
    displayRounds[targetIndex].addAll(fifthSemis);
  }
  if (finalColumnMatches.isNotEmpty) {
    displayRounds.add(finalColumnMatches);
  }

  return displayRounds;
}

String _singleKnockoutColumnTitle(
  List<GroupMatch> matches,
  int roundIndex,
  int totalRounds,
) {
  if (matches.isNotEmpty &&
      matches.every((match) => _isPlacementMatchLabel(match.label))) {
    return 'Platzierung';
  }
  return _bracketRoundTitle(roundIndex, totalRounds);
}

bool _isPlacementMatchLabel(String? label) {
  return label == 'Spiel um Platz 3' ||
      label == 'Spiel um Platz 5' ||
      label == 'Spiel um Platz 7' ||
      (label?.startsWith('Platz 5 Halbfinale') ?? false);
}

String? _singleKnockoutQualificationLabel(
  GroupMatch match,
  Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})> sourceMatches,
  int qualifyingRank,
  int roundIndex,
  int totalRounds,
) {
  if (qualifyingRank <= 0) {
    return null;
  }

  final hasPlacementMatches = sourceMatches.keys.any(
    (sourceMatch) => _isPlacementMatchLabel(sourceMatch.label),
  );
  if (!hasPlacementMatches) {
    return _bracketQualificationLabelFor(
      roundIndex: roundIndex,
      totalRounds: totalRounds,
      qualifyingRank: qualifyingRank,
    );
  }

  final label = match.label;
  if (label == 'Spiel um Platz 3' && qualifyingRank >= 3) {
    return 'Sieger weiter';
  }
  if (label == 'Spiel um Platz 5' && qualifyingRank >= 5) {
    return 'Sieger weiter';
  }
  if (label == 'Spiel um Platz 7' && qualifyingRank >= 7) {
    return 'Sieger weiter';
  }

  for (final entry in sourceMatches.entries) {
    final placementLabel = entry.key.label;
    if (!_isPlacementMatchLabel(placementLabel)) {
      continue;
    }
    if (entry.value.first != match && entry.value.second != match) {
      continue;
    }
    if (placementLabel == 'Spiel um Platz 3' && qualifyingRank >= 3) {
      return 'Sieger weiter / Verlierer Platz 3';
    }
    if (placementLabel == 'Spiel um Platz 5' && qualifyingRank >= 5) {
      return 'Sieger weiter / Verlierer Platz 5';
    }
    if (placementLabel == 'Spiel um Platz 7' && qualifyingRank >= 7) {
      return 'Sieger weiter / Verlierer Platz 7';
    }
  }

  return null;
}

Map<GroupMatch, int> _stageMatchNumbers(List<List<GroupMatch>> rounds) {
  final numbers = <GroupMatch, int>{};
  var nextNumber = 1;
  for (final round in rounds) {
    for (final match in round) {
      if (match.label == _autoAdvanceLabel) {
        continue;
      }
      numbers[match] = nextNumber;
      nextNumber++;
    }
  }
  return numbers;
}

Map<GroupMatch, ({String? first, String? second})> _stageSourceLabels(
  KnockoutTournamentRunStage stage,
  Map<GroupMatch, int> matchNumbers,
) {
  if (stage.eliminationLossLimit == 2) {
    return _doubleSourceLabels(stage.rounds, matchNumbers);
  }
  if (stage.eliminationLossLimit >= 3) {
    return _lossLevelSourceLabels(stage.rounds, matchNumbers);
  }
  return _singleKnockoutSourceLabels(stage.rounds, matchNumbers);
}

Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})> _stageSourceMatches(
  KnockoutTournamentRunStage stage,
) {
  if (stage.eliminationLossLimit == 2) {
    return _doubleSourceMatches(stage.rounds);
  }
  if (stage.eliminationLossLimit >= 3) {
    return _lossLevelSourceMatches(stage.rounds);
  }
  return _singleKnockoutSourceMatches(stage.rounds);
}

Map<GroupMatch, ({String? first, String? second})>
_deferUnresolvedSourcePlayerLabels(
  Map<GroupMatch, ({String? first, String? second})> labels,
  Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})> sourceMatches,
  Map<GroupMatch, int> matchNumbers,
) {
  return {
    for (final entry in labels.entries)
      entry.key: (
        first: _deferredSourceLabel(
          entry.value.first,
          sourceMatches[entry.key]?.first,
          labels,
          matchNumbers,
        ),
        second: _deferredSourceLabel(
          entry.value.second,
          sourceMatches[entry.key]?.second,
          labels,
          matchNumbers,
        ),
      ),
  };
}

String? _deferredSourceLabel(
  String? label,
  GroupMatch? sourceMatch,
  Map<GroupMatch, ({String? first, String? second})> labels,
  Map<GroupMatch, int> matchNumbers,
) {
  if (label == null || sourceMatch == null || sourceMatch.hasResult) {
    return label;
  }

  final winner = sourceMatch.winner;
  final sourceNumber = matchNumbers[sourceMatch];
  if (winner == null || sourceNumber == null || label != winner.name) {
    return label;
  }

  final sourceLabels = labels[sourceMatch];
  final hasUnresolvedExpectedHome =
      sourceMatch.homePlayer == null &&
      _isExpectedBracketSourceLabel(sourceLabels?.first);
  final hasUnresolvedExpectedAway =
      sourceMatch.awayPlayer == null &&
      _isExpectedBracketSourceLabel(sourceLabels?.second);
  if (!hasUnresolvedExpectedHome && !hasUnresolvedExpectedAway) {
    return label;
  }

  return 'Gewinner Spiel $sourceNumber';
}

bool _isExpectedBracketSourceLabel(String? label) {
  return label != null &&
      (label.startsWith('Gewinner Spiel ') ||
          label.startsWith('Verlierer Spiel '));
}

Map<GroupMatch, ({String? first, String? second})> _singleKnockoutSourceLabels(
  List<List<GroupMatch>> rounds,
  Map<GroupMatch, int> matchNumbers,
) {
  final labels = <GroupMatch, ({String? first, String? second})>{};
  for (var roundIndex = 1; roundIndex < rounds.length; roundIndex++) {
    for (
      var matchIndex = 0;
      matchIndex < rounds[roundIndex].length;
      matchIndex++
    ) {
      final previous = rounds[roundIndex - 1];
      final firstSourceIndex = matchIndex * 2;
      final secondSourceIndex = firstSourceIndex + 1;
      if (secondSourceIndex >= previous.length) {
        continue;
      }

      final firstSource = previous[firstSourceIndex];
      final secondSource = previous[secondSourceIndex];
      labels[rounds[roundIndex][matchIndex]] = (
        first: 'Gewinner Spiel ${matchNumbers[firstSource]}',
        second: 'Gewinner Spiel ${matchNumbers[secondSource]}',
      );
    }
  }
  return labels;
}

Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})>
_singleKnockoutSourceMatches(List<List<GroupMatch>> rounds) {
  final sources = <GroupMatch, ({GroupMatch? first, GroupMatch? second})>{};
  for (var roundIndex = 1; roundIndex < rounds.length; roundIndex++) {
    for (
      var matchIndex = 0;
      matchIndex < rounds[roundIndex].length;
      matchIndex++
    ) {
      final previous = rounds[roundIndex - 1];
      sources[rounds[roundIndex][matchIndex]] = (
        first: matchIndex * 2 < previous.length
            ? previous[matchIndex * 2]
            : null,
        second: matchIndex * 2 + 1 < previous.length
            ? previous[matchIndex * 2 + 1]
            : null,
      );
    }
  }
  return sources;
}

Map<GroupMatch, ({String? first, String? second})>
_singleKnockoutPlacementSourceLabels(
  List<List<GroupMatch>> rounds,
  List<GroupMatch> placementMatches,
  Map<GroupMatch, int> matchNumbers,
) {
  final sources = _singleKnockoutPlacementSourceMatches(
    rounds,
    placementMatches,
  );
  return {
    for (final entry in sources.entries)
      entry.key: (
        first: _placementSourceLabel(
          entry.key,
          entry.value.first,
          matchNumbers,
        ),
        second: _placementSourceLabel(
          entry.key,
          entry.value.second,
          matchNumbers,
        ),
      ),
  };
}

String? _placementSourceLabel(
  GroupMatch placementMatch,
  GroupMatch? sourceMatch,
  Map<GroupMatch, int> matchNumbers,
) {
  if (sourceMatch == null) {
    return null;
  }
  final label = placementMatch.label;
  if (label == 'Spiel um Platz 5') {
    return _winnerSourceLabel(sourceMatch, matchNumbers);
  }
  return _loserSourceLabel(sourceMatch, matchNumbers);
}

Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})>
_singleKnockoutPlacementSourceMatches(
  List<List<GroupMatch>> rounds,
  List<GroupMatch> placementMatches,
) {
  final sources = <GroupMatch, ({GroupMatch? first, GroupMatch? second})>{};
  if (placementMatches.isEmpty) {
    return sources;
  }

  final thirdPlaceMatches = placementMatches
      .where((match) => match.label == 'Spiel um Platz 3')
      .toList();
  if (thirdPlaceMatches.isNotEmpty && rounds.length >= 2) {
    final semifinals = rounds.last.length >= 2
        ? rounds.last
        : rounds[rounds.length - 2];
    sources[thirdPlaceMatches.first] = (
      first: semifinals.isNotEmpty ? semifinals[0] : null,
      second: semifinals.length > 1 ? semifinals[1] : null,
    );
  }

  final fifthSemis = placementMatches
      .where((match) => match.label?.startsWith('Platz 5 Halbfinale') ?? false)
      .toList();
  if (fifthSemis.isNotEmpty) {
    final quarterfinals = rounds.last.length >= 4
        ? rounds.last
        : rounds.length >= 3
        ? rounds[rounds.length - 3]
        : const <GroupMatch>[];
    for (var index = 0; index < fifthSemis.length; index++) {
      final sourceIndex = index * 2;
      sources[fifthSemis[index]] = (
        first: sourceIndex < quarterfinals.length
            ? quarterfinals[sourceIndex]
            : null,
        second: sourceIndex + 1 < quarterfinals.length
            ? quarterfinals[sourceIndex + 1]
            : null,
      );
    }
  }

  final fifthPlaceMatches = placementMatches
      .where((match) => match.label == 'Spiel um Platz 5')
      .toList();
  if (fifthPlaceMatches.isNotEmpty) {
    sources[fifthPlaceMatches.first] = (
      first: fifthSemis.isNotEmpty ? fifthSemis[0] : null,
      second: fifthSemis.length > 1 ? fifthSemis[1] : null,
    );
  }

  final seventhPlaceMatches = placementMatches
      .where((match) => match.label == 'Spiel um Platz 7')
      .toList();
  if (seventhPlaceMatches.isNotEmpty) {
    sources[seventhPlaceMatches.first] = (
      first: fifthSemis.isNotEmpty ? fifthSemis[0] : null,
      second: fifthSemis.length > 1 ? fifthSemis[1] : null,
    );
  }

  return sources;
}

Map<GroupMatch, ({String? first, String? second})> _doubleSourceLabels(
  List<List<GroupMatch>> rounds,
  Map<GroupMatch, int> matchNumbers,
) {
  final labels = <GroupMatch, ({String? first, String? second})>{};
  final winnersRoundCount = _doubleWinnersRoundCount(rounds);
  final losersRoundCount = _doubleLosersRoundCount(rounds);

  for (var roundNumber = 2; roundNumber <= winnersRoundCount; roundNumber++) {
    final previous = _doubleWinnersRoundMatches(
      rounds,
      roundNumber - 1,
      includeAutoAdvances: roundNumber == 2,
    );
    final current = _doubleWinnersRoundMatches(rounds, roundNumber);
    for (var index = 0; index < current.length; index++) {
      final firstSource = index * 2 < previous.length
          ? previous[index * 2]
          : null;
      final secondSource = index * 2 + 1 < previous.length
          ? previous[index * 2 + 1]
          : null;
      labels[current[index]] = (
        first: _winnerSourceLabel(firstSource, matchNumbers),
        second: _winnerSourceLabel(secondSource, matchNumbers),
      );
    }
  }

  final firstWinners = _doubleWinnersRoundMatches(
    rounds,
    1,
    includeAutoAdvances: true,
  );
  final firstLosers = _matchesWithLabel(rounds, _doubleLosersLabel(1));
  for (final match in firstLosers) {
    labels[match] = (first: null, second: null);
  }
  final firstWinnersWithLoserSource = [
    for (final match in firstWinners)
      if (match.label != _autoAdvanceLabel) match,
  ];
  if (firstLosers.isNotEmpty &&
      firstWinnersWithLoserSource.length <= firstLosers.length) {
    for (var index = 0; index < firstWinnersWithLoserSource.length; index++) {
      final targetIndex =
          (index * firstLosers.length) ~/ firstWinnersWithLoserSource.length;
      labels[firstLosers[targetIndex]] = (
        first: _loserSourceLabel(
          firstWinnersWithLoserSource[index],
          matchNumbers,
        ),
        second: null,
      );
    }
  } else {
    for (var index = 0; index < firstWinnersWithLoserSource.length; index++) {
      var targetIndex =
          (index * firstLosers.length) ~/ firstWinnersWithLoserSource.length;
      if (targetIndex >= firstLosers.length) {
        break;
      }
      var current =
          labels[firstLosers[targetIndex]] ?? (first: null, second: null);
      while (targetIndex < firstLosers.length &&
          current.first != null &&
          current.second != null) {
        targetIndex++;
        if (targetIndex < firstLosers.length) {
          current =
              labels[firstLosers[targetIndex]] ?? (first: null, second: null);
        }
      }
      if (targetIndex >= firstLosers.length) {
        break;
      }
      labels[firstLosers[targetIndex]] = current.first == null
          ? (
              first: _loserSourceLabel(
                firstWinnersWithLoserSource[index],
                matchNumbers,
              ),
              second: current.second,
            )
          : (
              first: current.first,
              second: _loserSourceLabel(
                firstWinnersWithLoserSource[index],
                matchNumbers,
              ),
            );
    }
  }

  for (var roundNumber = 2; roundNumber <= losersRoundCount; roundNumber++) {
    final current = _matchesWithLabel(rounds, _doubleLosersLabel(roundNumber));
    final previousLosers = _matchesWithLabel(
      rounds,
      _doubleLosersLabel(roundNumber - 1),
    );
    final incomingWinnersRound = roundNumber == losersRoundCount
        ? winnersRoundCount
        : ((roundNumber + 2) ~/ 2);
    final incomingWinners = _matchesWithLabel(
      rounds,
      _doubleWinnersLabel(incomingWinnersRound),
    );
    for (var index = 0; index < current.length; index++) {
      final previousIndex = previousLosers.length == current.length
          ? index
          : index * 2;
      final firstSource = previousIndex < previousLosers.length
          ? previousLosers[previousIndex]
          : null;
      final secondSource = previousLosers.length == current.length
          ? (index < incomingWinners.length ? incomingWinners[index] : null)
          : (previousIndex + 1 < previousLosers.length
                ? previousLosers[previousIndex + 1]
                : null);
      labels[current[index]] = (
        first: _winnerSourceLabel(firstSource, matchNumbers),
        second: previousLosers.length == current.length
            ? _loserSourceLabel(secondSource, matchNumbers)
            : _winnerSourceLabel(secondSource, matchNumbers),
      );
    }
  }

  final grandFinal = _matchesWithLabel(rounds, _doubleGrandFinalLabel);
  if (grandFinal.isNotEmpty) {
    final winnersFinal = _doubleWinnersRoundMatches(rounds, winnersRoundCount);
    final losersFinal = _matchesWithLabel(
      rounds,
      _doubleLosersLabel(losersRoundCount),
    );
    labels[grandFinal.first] = (
      first: winnersFinal.isEmpty
          ? null
          : _winnerSourceLabel(winnersFinal.first, matchNumbers),
      second: losersFinal.isEmpty
          ? (winnersRoundCount == 1 && winnersFinal.isNotEmpty
                ? _loserSourceLabel(winnersFinal.first, matchNumbers)
                : null)
          : _winnerSourceLabel(losersFinal.first, matchNumbers),
    );
  }

  return labels;
}

Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})> _doubleSourceMatches(
  List<List<GroupMatch>> rounds,
) {
  final sources = <GroupMatch, ({GroupMatch? first, GroupMatch? second})>{};
  final winnersRoundCount = _doubleWinnersRoundCount(rounds);
  final losersRoundCount = _doubleLosersRoundCount(rounds);

  for (var roundNumber = 2; roundNumber <= winnersRoundCount; roundNumber++) {
    final previous = _doubleWinnersRoundMatches(
      rounds,
      roundNumber - 1,
      includeAutoAdvances: roundNumber == 2,
    );
    final current = _doubleWinnersRoundMatches(rounds, roundNumber);
    for (var index = 0; index < current.length; index++) {
      sources[current[index]] = (
        first: index * 2 < previous.length ? previous[index * 2] : null,
        second: index * 2 + 1 < previous.length
            ? previous[index * 2 + 1]
            : null,
      );
    }
  }

  final firstWinners = _doubleWinnersRoundMatches(
    rounds,
    1,
    includeAutoAdvances: true,
  );
  final firstLosers = _matchesWithLabel(rounds, _doubleLosersLabel(1));
  for (final match in firstLosers) {
    sources[match] = (first: null, second: null);
  }
  final firstWinnersWithLoserSource = [
    for (final match in firstWinners)
      if (match.label != _autoAdvanceLabel) match,
  ];
  if (firstLosers.isNotEmpty &&
      firstWinnersWithLoserSource.length <= firstLosers.length) {
    for (var index = 0; index < firstWinnersWithLoserSource.length; index++) {
      final targetIndex =
          (index * firstLosers.length) ~/ firstWinnersWithLoserSource.length;
      sources[firstLosers[targetIndex]] = (
        first: firstWinnersWithLoserSource[index],
        second: null,
      );
    }
  } else {
    for (var index = 0; index < firstWinnersWithLoserSource.length; index++) {
      var targetIndex =
          (index * firstLosers.length) ~/ firstWinnersWithLoserSource.length;
      if (targetIndex >= firstLosers.length) {
        break;
      }
      var current =
          sources[firstLosers[targetIndex]] ?? (first: null, second: null);
      while (targetIndex < firstLosers.length &&
          current.first != null &&
          current.second != null) {
        targetIndex++;
        if (targetIndex < firstLosers.length) {
          current =
              sources[firstLosers[targetIndex]] ?? (first: null, second: null);
        }
      }
      if (targetIndex >= firstLosers.length) {
        break;
      }
      sources[firstLosers[targetIndex]] = current.first == null
          ? (first: firstWinnersWithLoserSource[index], second: current.second)
          : (first: current.first, second: firstWinnersWithLoserSource[index]);
    }
  }

  for (var roundNumber = 2; roundNumber <= losersRoundCount; roundNumber++) {
    final current = _matchesWithLabel(rounds, _doubleLosersLabel(roundNumber));
    final previousLosers = _matchesWithLabel(
      rounds,
      _doubleLosersLabel(roundNumber - 1),
    );
    final incomingWinnersRound = roundNumber == losersRoundCount
        ? winnersRoundCount
        : ((roundNumber + 2) ~/ 2);
    final incomingWinners = _matchesWithLabel(
      rounds,
      _doubleWinnersLabel(incomingWinnersRound),
    );
    for (var index = 0; index < current.length; index++) {
      final previousIndex = previousLosers.length == current.length
          ? index
          : index * 2;
      sources[current[index]] = (
        first: previousIndex < previousLosers.length
            ? previousLosers[previousIndex]
            : null,
        second: previousLosers.length == current.length
            ? (index < incomingWinners.length ? incomingWinners[index] : null)
            : (previousIndex + 1 < previousLosers.length
                  ? previousLosers[previousIndex + 1]
                  : null),
      );
    }
  }

  final grandFinal = _matchesWithLabel(rounds, _doubleGrandFinalLabel);
  if (grandFinal.isNotEmpty) {
    final winnersFinal = _doubleWinnersRoundMatches(rounds, winnersRoundCount);
    final losersFinal = _matchesWithLabel(
      rounds,
      _doubleLosersLabel(losersRoundCount),
    );
    sources[grandFinal.first] = (
      first: winnersFinal.isEmpty ? null : winnersFinal.first,
      second: losersFinal.isEmpty
          ? (winnersRoundCount == 1 && winnersFinal.isNotEmpty
                ? winnersFinal.first
                : null)
          : losersFinal.first,
    );
  }

  return sources;
}

String? _winnerSourceLabel(
  GroupMatch? match,
  Map<GroupMatch, int> matchNumbers,
) {
  if (match == null) {
    return null;
  }
  if (match.label == _autoAdvanceLabel) {
    return match.winner?.name ?? _autoAdvanceLabel;
  }
  final winner = match.winner;
  if (winner != null) {
    return winner.name;
  }
  final number = matchNumbers[match];
  return number == null ? null : 'Gewinner Spiel $number';
}

String? _loserSourceLabel(
  GroupMatch? match,
  Map<GroupMatch, int> matchNumbers,
) {
  if (match == null || match.label == _autoAdvanceLabel) {
    return null;
  }
  final loser = match.loser;
  if (loser != null) {
    return loser.name;
  }
  final number = matchNumbers[match];
  return number == null ? null : 'Verlierer Spiel $number';
}

Map<GroupMatch, ({String? first, String? second})> _lossLevelSourceLabels(
  List<List<GroupMatch>> rounds,
  Map<GroupMatch, int> matchNumbers,
) {
  final labels = <GroupMatch, ({String? first, String? second})>{};
  final sourceEdges = _lossLevelSourceEdges(rounds);
  for (final entry in sourceEdges.entries) {
    labels[entry.key] = (
      first: _sourceEdgeLabel(entry.value.first, matchNumbers),
      second: _sourceEdgeLabel(entry.value.second, matchNumbers),
    );
  }
  return labels;
}

Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})>
_lossLevelSourceMatches(List<List<GroupMatch>> rounds) {
  final edges = _lossLevelSourceEdges(rounds);
  return {
    for (final entry in edges.entries)
      entry.key: (
        first: entry.value.first?.match,
        second: entry.value.second?.match,
      ),
  };
}

Map<GroupMatch, ({_SourceEdge? first, _SourceEdge? second})>
_lossLevelSourceEdges(List<List<GroupMatch>> rounds) {
  final edges = TripleKoEngine.advance(rounds, update: false);
  _SourceEdge? convert(TripleSource? source) => source == null
      ? null
      : source.loser
      ? _SourceEdge.loser(source.match)
      : _SourceEdge.winner(source.match);
  return {
    for (final entry in edges.entries)
      entry.key: (
        first: convert(entry.value.first),
        second: convert(entry.value.second),
      ),
  };
}

String? _sourceEdgeLabel(_SourceEdge? edge, Map<GroupMatch, int> matchNumbers) {
  if (edge == null) {
    return null;
  }
  return edge.usesLoser
      ? _loserSourceLabel(edge.match, matchNumbers)
      : _winnerSourceLabel(edge.match, matchNumbers);
}

class _SourceEdge {
  const _SourceEdge.winner(this.match) : usesLoser = false;
  const _SourceEdge.loser(this.match) : usesLoser = true;

  final GroupMatch match;
  final bool usesLoser;
}

class _DoubleEliminationBracketView extends StatelessWidget {
  const _DoubleEliminationBracketView({
    required this.stage,
    required this.matchNumbers,
    required this.sourceLabels,
    required this.sourceMatches,
    required this.qualifyingRank,
    required this.onEditResult,
    required this.canEditResults,
    required this.isEditMode,
    this.onSwapSlot,
  });

  final KnockoutTournamentRunStage stage;
  final Map<GroupMatch, int> matchNumbers;
  final Map<GroupMatch, ({String? first, String? second})> sourceLabels;
  final Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})>
  sourceMatches;
  final int qualifyingRank;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResults;
  final bool isEditMode;
  final void Function(int fromSlotIndex, int toSlotIndex)? onSwapSlot;

  @override
  Widget build(BuildContext context) {
    final winnersRounds = _doubleBracketRounds(_doubleWinnersPrefix);
    final losersRounds = _doubleBracketRounds(_doubleLosersPrefix);
    final finalMatches = [
      ..._matchesWithLabel(stage.rounds, _doubleGrandFinalLabel),
      ..._matchesWithLabel(stage.rounds, _doubleResetFinalLabel),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BracketBandTitle(title: 'Winners Bracket'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: winnersRounds.length,
          columnWidth: 260,
          cardHeight: 204,
          firstRoundGap: 12,
          useBalancedColumnLayout: true,
          roundMatches: winnersRounds,
          sourceMatches: sourceMatches,
          roundTitles: [
            for (var index = 0; index < winnersRounds.length; index++)
              _bracketRoundTitle(index, winnersRounds.length),
          ],
          roundCards: [
            for (
              var roundIndex = 0;
              roundIndex < winnersRounds.length;
              roundIndex++
            )
              _matchCards(
                winnersRounds[roundIndex],
                roundIndex,
                winnersRounds.length,
              ),
          ],
        ),
        const SizedBox(height: 18),
        _BracketBandTitle(title: 'Losers Bracket'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: losersRounds.length,
          columnWidth: 260,
          cardHeight: 204,
          firstRoundGap: 12,
          useBalancedColumnLayout: true,
          roundMatches: losersRounds,
          sourceMatches: sourceMatches,
          roundTitles: [
            for (var index = 0; index < losersRounds.length; index++)
              _bracketRoundTitle(index, losersRounds.length),
          ],
          roundCards: [
            for (
              var roundIndex = 0;
              roundIndex < losersRounds.length;
              roundIndex++
            )
              _matchCards(
                losersRounds[roundIndex],
                roundIndex,
                losersRounds.length,
              ),
          ],
        ),
        const SizedBox(height: 18),
        _BracketBandTitle(title: 'Finale'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: finalMatches.length,
          columnWidth: 260,
          cardHeight: 204,
          firstRoundGap: 12,
          useBalancedColumnLayout: true,
          roundMatches: [
            for (final match in finalMatches) [match],
          ],
          sourceMatches: sourceMatches,
          roundTitles: const ['Finale'],
          roundCards: [
            for (var i = 0; i < finalMatches.length; i++)
              _matchCards([finalMatches[i]], i, finalMatches.length),
          ],
        ),
      ],
    );
  }

  List<List<GroupMatch>> _doubleBracketRounds(String prefix) {
    final highestRound = prefix == _doubleWinnersPrefix
        ? _doubleWinnersRoundCount(stage.rounds)
        : _doubleLosersRoundCount(stage.rounds);
    return [
      for (var roundNumber = 1; roundNumber <= highestRound; roundNumber++)
        prefix == _doubleWinnersPrefix
            ? _doubleWinnersRoundMatches(stage.rounds, roundNumber)
            : _matchesWithLabel(stage.rounds, _doubleLosersLabel(roundNumber)),
    ];
  }

  List<Widget> _matchCards(
    List<GroupMatch> matches,
    int roundIndex,
    int totalRounds,
  ) {
    return [
      for (var matchIndex = 0; matchIndex < matches.length; matchIndex++)
        _KnockoutBracketMatchCard(
          match: matches[matchIndex],
          matchNumber: matchNumbers[matches[matchIndex]] ?? matchIndex + 1,
          homeSourceLabel: sourceLabels[matches[matchIndex]]?.first,
          awaySourceLabel: sourceLabels[matches[matchIndex]]?.second,
          roundIndex: roundIndex,
          matchIndex: matchIndex,
          totalRounds: totalRounds,
          qualifyingRank: qualifyingRank,
          onEditResult: onEditResult,
          canEditResult: canEditResults,
          isEditMode: isEditMode,
          onSwapSlot: onSwapSlot,
        ),
    ];
  }
}

class _TripleEliminationBracketView extends StatelessWidget {
  const _TripleEliminationBracketView({
    required this.stage,
    required this.matchNumbers,
    required this.sourceLabels,
    required this.sourceMatches,
    required this.qualifyingRank,
    required this.onEditResult,
    required this.canEditResults,
    required this.isEditMode,
    this.onSwapSlot,
  });

  final KnockoutTournamentRunStage stage;
  final Map<GroupMatch, int> matchNumbers;
  final Map<GroupMatch, ({String? first, String? second})> sourceLabels;
  final Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})>
  sourceMatches;
  final int qualifyingRank;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResults;
  final bool isEditMode;
  final void Function(int fromSlotIndex, int toSlotIndex)? onSwapSlot;

  @override
  Widget build(BuildContext context) {
    final finalMatches = _matchesWithLabel(stage.rounds, _tripleFinalLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (
          var lossCount = 0;
          lossCount < stage.eliminationLossLimit;
          lossCount++
        ) ...[
          _BracketBandTitle(title: _lossLevelBracketLabel(lossCount)),
          const SizedBox(height: 8),
          _BracketTreeLayout(
            totalRounds: _lossLevelRounds(lossCount).length,
            columnWidth: 260,
            cardHeight: 204,
            firstRoundGap: 12,
            useBalancedColumnLayout: true,
            roundMatches: _lossLevelRounds(lossCount),
            sourceMatches: sourceMatches,
            roundTitles: [
              for (
                var roundIndex = 0;
                roundIndex < _lossLevelRounds(lossCount).length;
                roundIndex++
              )
                lossCount == 0
                    ? _bracketRoundTitle(
                        roundIndex,
                        _lossLevelRounds(lossCount).length,
                      )
                    : _bracketRoundTitle(
                        roundIndex,
                        _lossLevelRounds(lossCount).length,
                      ),
            ],
            roundCards: [
              for (
                var roundIndex = 0;
                roundIndex < _lossLevelRounds(lossCount).length;
                roundIndex++
              )
                _matchCards(
                  _lossLevelRounds(lossCount)[roundIndex],
                  roundIndex,
                  _lossLevelRounds(lossCount).length,
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        _BracketBandTitle(title: 'Finale'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: finalMatches.isEmpty ? 0 : 1,
          columnWidth: 260,
          cardHeight: 204,
          firstRoundGap: 12,
          useBalancedColumnLayout: true,
          roundMatches: [finalMatches],
          sourceMatches: sourceMatches,
          roundTitles: [for (var i = 0; i < finalMatches.length; i++) 'Finale'],
          roundCards: [_matchCards(finalMatches, 0, 1)],
        ),
      ],
    );
  }

  List<List<GroupMatch>> _lossLevelRounds(int lossCount) {
    final rounds = <List<GroupMatch>>[];
    var roundNumber = 1;
    while (true) {
      final matches = _matchesWithLabel(
        stage.rounds,
        _lossLevelMatchLabel(lossCount, roundNumber),
      );
      if (matches.isEmpty) {
        break;
      }
      rounds.add(matches);
      roundNumber++;
    }
    return rounds;
  }

  List<Widget> _matchCards(
    List<GroupMatch> matches,
    int roundIndex,
    int totalRounds,
  ) {
    return [
      for (var matchIndex = 0; matchIndex < matches.length; matchIndex++)
        _KnockoutBracketMatchCard(
          match: matches[matchIndex],
          matchNumber: matchNumbers[matches[matchIndex]] ?? matchIndex + 1,
          homeSourceLabel: sourceLabels[matches[matchIndex]]?.first,
          awaySourceLabel: sourceLabels[matches[matchIndex]]?.second,
          roundIndex: roundIndex,
          matchIndex: matchIndex,
          totalRounds: totalRounds,
          qualifyingRank: qualifyingRank,
          onEditResult: onEditResult,
          canEditResult: canEditResults,
          isEditMode: isEditMode,
          onSwapSlot: onSwapSlot,
        ),
    ];
  }
}

class _BracketBandTitle extends StatelessWidget {
  const _BracketBandTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

String _bracketRoundTitle(int roundIndex, int totalRounds) =>
    knockoutRoundName(roundIndex, totalRounds);

class _BracketTreeLayout extends StatelessWidget {
  const _BracketTreeLayout({
    required this.totalRounds,
    required this.roundTitles,
    required this.roundCards,
    required this.columnWidth,
    required this.cardHeight,
    required this.firstRoundGap,
    this.roundMatches,
    this.sourceMatches,
    this.useBalancedColumnLayout = false,
    this.scaleApplied = false,
  });

  static const double _headerHeight = 34;
  static const double _headerGap = 10;
  static const double _connectorWidth = 34;

  final int totalRounds;
  final List<String> roundTitles;
  final List<List<Widget>> roundCards;
  final List<List<GroupMatch>>? roundMatches;
  final Map<GroupMatch, ({GroupMatch? first, GroupMatch? second})>?
  sourceMatches;
  final double columnWidth;
  final double cardHeight;
  final double firstRoundGap;
  final bool useBalancedColumnLayout;
  final bool scaleApplied;

  double _columnContentHeight(int roundIndex) {
    final matchCount = roundCards[roundIndex].length;
    if (matchCount == 0) {
      return 0;
    }
    return matchCount * cardHeight + (matchCount - 1) * firstRoundGap;
  }

  double _contentHeight() {
    final sourceAwareCenters = _sourceAwareCenterYs();
    if (sourceAwareCenters != null) {
      var height = 0.0;
      for (final roundCenters in sourceAwareCenters) {
        for (final center in roundCenters) {
          final bottom = center - _headerHeight - _headerGap + cardHeight / 2;
          if (bottom > height) {
            height = bottom;
          }
        }
      }
      final baseHeight = _baseContentHeight();
      return height > baseHeight ? height : baseHeight;
    }

    return _baseContentHeight();
  }

  double _baseContentHeight() {
    if (!useBalancedColumnLayout) {
      final firstRoundCount = roundCards.first.length;
      return firstRoundCount * cardHeight +
          (firstRoundCount - 1) * firstRoundGap;
    }

    var height = 0.0;
    for (var roundIndex = 0; roundIndex < roundCards.length; roundIndex++) {
      final columnHeight = _columnContentHeight(roundIndex);
      if (columnHeight > height) {
        height = columnHeight;
      }
    }
    return height;
  }

  double _centerY(int roundIndex, int matchIndex) {
    final sourceAwareCenters = _sourceAwareCenterYs();
    if (sourceAwareCenters != null &&
        roundIndex < sourceAwareCenters.length &&
        matchIndex < sourceAwareCenters[roundIndex].length) {
      return sourceAwareCenters[roundIndex][matchIndex];
    }

    return _defaultCenterY(roundIndex, matchIndex, _baseContentHeight());
  }

  double _defaultCenterY(int roundIndex, int matchIndex, double contentHeight) {
    if (useBalancedColumnLayout) {
      final columnHeight = _columnContentHeight(roundIndex);
      final columnTop =
          _headerHeight + _headerGap + (contentHeight - columnHeight) / 2;
      return columnTop +
          matchIndex * (cardHeight + firstRoundGap) +
          cardHeight / 2;
    }

    final firstPitch = cardHeight + firstRoundGap;
    final span = 1 << roundIndex;
    final firstMatchIndex = matchIndex * span;
    final lastMatchIndex = firstMatchIndex + span - 1;
    final firstCenter =
        _headerHeight +
        _headerGap +
        firstMatchIndex * firstPitch +
        cardHeight / 2;
    final lastCenter =
        _headerHeight +
        _headerGap +
        lastMatchIndex * firstPitch +
        cardHeight / 2;
    return (firstCenter + lastCenter) / 2;
  }

  List<List<double>>? _sourceAwareCenterYs() {
    if (roundMatches == null || sourceMatches == null) {
      return null;
    }

    final matches = roundMatches!;
    final positions = <GroupMatch, ({int roundIndex, int matchIndex})>{};
    for (var roundIndex = 0; roundIndex < matches.length; roundIndex++) {
      for (
        var matchIndex = 0;
        matchIndex < matches[roundIndex].length;
        matchIndex++
      ) {
        positions[matches[roundIndex][matchIndex]] = (
          roundIndex: roundIndex,
          matchIndex: matchIndex,
        );
      }
    }

    final baseContentHeight = _baseContentHeight();
    final centers = [
      for (var roundIndex = 0; roundIndex < roundCards.length; roundIndex++)
        [
          for (
            var matchIndex = 0;
            matchIndex < roundCards[roundIndex].length;
            matchIndex++
          )
            _defaultCenterY(roundIndex, matchIndex, baseContentHeight),
        ],
    ];

    for (var roundIndex = 0; roundIndex < matches.length; roundIndex++) {
      for (
        var matchIndex = 0;
        matchIndex < matches[roundIndex].length;
        matchIndex++
      ) {
        final target = matches[roundIndex][matchIndex];
        final sources = sourceMatches![target];
        if (sources == null) {
          continue;
        }

        final sourceCenters = <double>[];
        for (final source in [sources.first, sources.second]) {
          final sourcePosition = source == null ? null : positions[source];
          if (sourcePosition == null ||
              sourcePosition.roundIndex >= roundIndex ||
              sourcePosition.roundIndex >= centers.length ||
              sourcePosition.matchIndex >=
                  centers[sourcePosition.roundIndex].length) {
            continue;
          }
          sourceCenters.add(
            centers[sourcePosition.roundIndex][sourcePosition.matchIndex],
          );
        }

        if (sourceCenters.isEmpty) {
          continue;
        }
        centers[roundIndex][matchIndex] =
            sourceCenters.reduce((sum, value) => sum + value) /
            sourceCenters.length;
      }
    }

    return centers;
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (!scaleApplied && scale > 1) {
      return _BracketTreeLayout(
        totalRounds: totalRounds,
        roundTitles: roundTitles,
        roundCards: roundCards,
        columnWidth: columnWidth * scale,
        cardHeight: cardHeight * scale,
        firstRoundGap: firstRoundGap * scale,
        roundMatches: roundMatches,
        sourceMatches: sourceMatches,
        useBalancedColumnLayout: useBalancedColumnLayout,
        scaleApplied: true,
      );
    }

    if (totalRounds == 0 || roundCards.isEmpty) {
      return const SizedBox.shrink();
    }

    final centerYs = _sourceAwareCenterYs();
    final height = _headerHeight + _headerGap + _contentHeight();
    final width =
        totalRounds * columnWidth + (totalRounds - 1) * _connectorWidth;

    return _BracketPanViewport(
      width: width,
      height: height,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BracketConnectorPainter(
                  totalRounds: totalRounds,
                  roundCards: roundCards,
                  connections: _connections(),
                  columnWidth: columnWidth,
                  connectorWidth: _connectorWidth,
                  cardHeight: cardHeight,
                  firstRoundGap: firstRoundGap,
                  headerHeight: _headerHeight,
                  headerGap: _headerGap,
                  useBalancedColumnLayout: useBalancedColumnLayout,
                  centerYs: centerYs,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            for (var roundIndex = 0; roundIndex < totalRounds; roundIndex++)
              Positioned(
                left: roundIndex * (columnWidth + _connectorWidth),
                top: 0,
                width: columnWidth,
                height: _headerHeight,
                child: _BracketRoundTitle(title: roundTitles[roundIndex]),
              ),
            for (
              var roundIndex = 0;
              roundIndex < roundCards.length;
              roundIndex++
            )
              for (
                var matchIndex = 0;
                matchIndex < roundCards[roundIndex].length;
                matchIndex++
              )
                Positioned(
                  left: roundIndex * (columnWidth + _connectorWidth),
                  top:
                      (centerYs?[roundIndex][matchIndex] ??
                          _centerY(roundIndex, matchIndex)) -
                      cardHeight / 2,
                  width: columnWidth,
                  height: cardHeight,
                  child: roundCards[roundIndex][matchIndex],
                ),
          ],
        ),
      ),
    );
  }

  List<_BracketConnection> _connections() {
    if (roundMatches == null || sourceMatches == null) {
      return _fallbackConnections();
    }

    final positions = <GroupMatch, ({int roundIndex, int matchIndex})>{};
    final matches = roundMatches!;
    final sourcesByMatch = sourceMatches!;
    for (var roundIndex = 0; roundIndex < matches.length; roundIndex++) {
      for (
        var matchIndex = 0;
        matchIndex < matches[roundIndex].length;
        matchIndex++
      ) {
        positions[matches[roundIndex][matchIndex]] = (
          roundIndex: roundIndex,
          matchIndex: matchIndex,
        );
      }
    }

    final connections = <_BracketConnection>[];
    for (var roundIndex = 0; roundIndex < matches.length; roundIndex++) {
      for (
        var matchIndex = 0;
        matchIndex < matches[roundIndex].length;
        matchIndex++
      ) {
        final target = matches[roundIndex][matchIndex];
        final sources = sourcesByMatch[target];
        if (sources == null) {
          continue;
        }
        for (final source in [sources.first, sources.second]) {
          final sourcePosition = source == null ? null : positions[source];
          if (sourcePosition == null ||
              sourcePosition.roundIndex >= roundIndex) {
            continue;
          }
          connections.add(
            _BracketConnection(
              fromRoundIndex: sourcePosition.roundIndex,
              fromMatchIndex: sourcePosition.matchIndex,
              toRoundIndex: roundIndex,
              toMatchIndex: matchIndex,
            ),
          );
        }
      }
    }
    return connections;
  }

  List<_BracketConnection> _fallbackConnections() {
    final connections = <_BracketConnection>[];
    for (var roundIndex = 0; roundIndex < roundCards.length - 1; roundIndex++) {
      for (
        var matchIndex = 0;
        matchIndex < roundCards[roundIndex].length;
        matchIndex++
      ) {
        final nextMatchIndex = matchIndex ~/ 2;
        if (nextMatchIndex >= roundCards[roundIndex + 1].length) {
          continue;
        }
        connections.add(
          _BracketConnection(
            fromRoundIndex: roundIndex,
            fromMatchIndex: matchIndex,
            toRoundIndex: roundIndex + 1,
            toMatchIndex: nextMatchIndex,
          ),
        );
      }
    }
    return connections;
  }
}

class _BracketPanViewport extends StatefulWidget {
  const _BracketPanViewport({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  State<_BracketPanViewport> createState() => _BracketPanViewportState();
}

class _BracketPanViewportState extends State<_BracketPanViewport> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  bool _isRightDragging = false;
  Offset? _lastPointerPosition;

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _startRightDrag(PointerDownEvent event) {
    if ((event.buttons & kSecondaryMouseButton) == 0) {
      return;
    }
    setState(() {
      _isRightDragging = true;
      _lastPointerPosition = event.position;
    });
  }

  void _updateRightDrag(PointerMoveEvent event) {
    if (!_isRightDragging ||
        (event.buttons & kSecondaryMouseButton) == 0 ||
        _lastPointerPosition == null) {
      return;
    }

    final delta = event.position - _lastPointerPosition!;
    _lastPointerPosition = event.position;
    _moveController(_horizontalController, -delta.dx);
    _moveController(_verticalController, -delta.dy);
  }

  void _endRightDrag(PointerEvent event) {
    if (!_isRightDragging) {
      return;
    }
    setState(() {
      _isRightDragging = false;
      _lastPointerPosition = null;
    });
  }

  void _moveController(ScrollController controller, double delta) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final nextOffset = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    controller.jumpTo(nextOffset);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewportHeight = min(widget.height, max(360.0, screenHeight * 0.72));

    return SizedBox(
      height: viewportHeight,
      child: Listener(
        onPointerDown: _startRightDrag,
        onPointerMove: _updateRightDrag,
        onPointerUp: _endRightDrag,
        onPointerCancel: _endRightDrag,
        child: MouseRegion(
          cursor: _isRightDragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.basic,
          child: Scrollbar(
            controller: _verticalController,
            child: SingleChildScrollView(
              key: const PageStorageKey('bracket-vertical'),
              controller: _verticalController,
              child: Scrollbar(
                controller: _horizontalController,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  key: const PageStorageKey('bracket-horizontal'),
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BracketRoundTitle extends StatelessWidget {
  const _BracketRoundTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _BracketConnectorPainter extends CustomPainter {
  const _BracketConnectorPainter({
    required this.totalRounds,
    required this.roundCards,
    required this.connections,
    required this.columnWidth,
    required this.connectorWidth,
    required this.cardHeight,
    required this.firstRoundGap,
    required this.headerHeight,
    required this.headerGap,
    required this.useBalancedColumnLayout,
    required this.centerYs,
    required this.color,
  });

  final int totalRounds;
  final List<List<Widget>> roundCards;
  final List<_BracketConnection> connections;
  final double columnWidth;
  final double connectorWidth;
  final double cardHeight;
  final double firstRoundGap;
  final double headerHeight;
  final double headerGap;
  final bool useBalancedColumnLayout;
  final List<List<double>>? centerYs;
  final Color color;

  double _columnContentHeight(int roundIndex) {
    final matchCount = roundCards[roundIndex].length;
    if (matchCount == 0) {
      return 0;
    }
    return matchCount * cardHeight + (matchCount - 1) * firstRoundGap;
  }

  double _contentHeight() {
    if (!useBalancedColumnLayout) {
      final firstRoundCount = roundCards.first.length;
      return firstRoundCount * cardHeight +
          (firstRoundCount - 1) * firstRoundGap;
    }

    var height = 0.0;
    for (var roundIndex = 0; roundIndex < roundCards.length; roundIndex++) {
      final columnHeight = _columnContentHeight(roundIndex);
      if (columnHeight > height) {
        height = columnHeight;
      }
    }
    return height;
  }

  double _centerY(int roundIndex, int matchIndex) {
    final sourceAwareCenters = centerYs;
    if (sourceAwareCenters != null &&
        roundIndex < sourceAwareCenters.length &&
        matchIndex < sourceAwareCenters[roundIndex].length) {
      return sourceAwareCenters[roundIndex][matchIndex];
    }

    if (useBalancedColumnLayout) {
      final contentHeight = _contentHeight();
      final columnHeight = _columnContentHeight(roundIndex);
      final columnTop =
          headerHeight + headerGap + (contentHeight - columnHeight) / 2;
      return columnTop +
          matchIndex * (cardHeight + firstRoundGap) +
          cardHeight / 2;
    }

    final firstPitch = cardHeight + firstRoundGap;
    final span = 1 << roundIndex;
    final firstMatchIndex = matchIndex * span;
    final lastMatchIndex = firstMatchIndex + span - 1;
    final firstCenter =
        headerHeight +
        headerGap +
        firstMatchIndex * firstPitch +
        cardHeight / 2;
    final lastCenter =
        headerHeight + headerGap + lastMatchIndex * firstPitch + cardHeight / 2;
    return (firstCenter + lastCenter) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final connection in connections) {
      if (connection.fromRoundIndex >= roundCards.length ||
          connection.toRoundIndex >= roundCards.length ||
          connection.fromMatchIndex >=
              roundCards[connection.fromRoundIndex].length ||
          connection.toMatchIndex >=
              roundCards[connection.toRoundIndex].length) {
        continue;
      }

      final startX =
          connection.fromRoundIndex * (columnWidth + connectorWidth) +
          columnWidth;
      final endX = connection.toRoundIndex * (columnWidth + connectorWidth);
      final midX = startX + (endX - startX) / 2;
      final startY = _centerY(
        connection.fromRoundIndex,
        connection.fromMatchIndex,
      );
      final endY = _centerY(connection.toRoundIndex, connection.toMatchIndex);

      final path = Path()
        ..moveTo(startX, startY)
        ..lineTo(midX, startY)
        ..lineTo(midX, endY)
        ..lineTo(endX, endY);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) {
    return oldDelegate.totalRounds != totalRounds ||
        oldDelegate.roundCards != roundCards ||
        oldDelegate.connections != connections ||
        oldDelegate.columnWidth != columnWidth ||
        oldDelegate.connectorWidth != connectorWidth ||
        oldDelegate.cardHeight != cardHeight ||
        oldDelegate.firstRoundGap != firstRoundGap ||
        oldDelegate.useBalancedColumnLayout != useBalancedColumnLayout ||
        oldDelegate.centerYs != centerYs ||
        oldDelegate.color != color;
  }
}

class _BracketConnection {
  const _BracketConnection({
    required this.fromRoundIndex,
    required this.fromMatchIndex,
    required this.toRoundIndex,
    required this.toMatchIndex,
  });

  final int fromRoundIndex;
  final int fromMatchIndex;
  final int toRoundIndex;
  final int toMatchIndex;
}

class _KnockoutBracketMatchCard extends StatelessWidget {
  const _KnockoutBracketMatchCard({
    required this.match,
    required this.matchNumber,
    required this.roundIndex,
    required this.matchIndex,
    required this.totalRounds,
    required this.qualifyingRank,
    required this.onEditResult,
    required this.canEditResult,
    required this.isEditMode,
    this.homeSourceLabel,
    this.awaySourceLabel,
    this.qualificationLabel,
    this.onSwapSlot,
  });

  final GroupMatch match;
  final int matchNumber;
  final int roundIndex;
  final int matchIndex;
  final int totalRounds;
  final int qualifyingRank;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResult;
  final bool isEditMode;
  final String? homeSourceLabel;
  final String? awaySourceLabel;
  final String? qualificationLabel;
  final void Function(int fromSlotIndex, int toSlotIndex)? onSwapSlot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final winner = match.winner;
    final resolvedQualificationLabel =
        qualificationLabel ?? _bracketQualificationLabel();
    final homeLabel = _emptySlotLabel(
      sourceLabel: homeSourceLabel,
      isEmpty: match.homePlayer == null,
      opponent: match.awayPlayer,
      allowsBye: match.allowsBye,
    );
    final awayLabel = _emptySlotLabel(
      sourceLabel: awaySourceLabel,
      isEmpty: match.awayPlayer == null,
      opponent: match.homePlayer,
      allowsBye: match.allowsBye,
    );

    return MatchStatisticsTapTarget(
      match: match,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _matchTitle(),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                IconButton.filledTonal(
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: canEditResult && match.hasPlayers
                      ? () => onEditResult(match)
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Ergebnis',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _BracketPlayerSlot(
              player: match.homePlayer,
              score: match.homePlayer == null ? null : match.homeScore,
              isWinner:
                  match.hasResult &&
                  _isRealBracketPlayer(match.homePlayer) &&
                  winner == match.homePlayer,
              label: homeLabel,
              slotIndex: matchIndex * 2,
              isEditable: isEditMode && roundIndex == 0,
              onSwapSlot: onSwapSlot,
            ),
            const SizedBox(height: 6),
            _BracketPlayerSlot(
              player: match.awayPlayer,
              score: match.awayPlayer == null ? null : match.awayScore,
              isWinner:
                  match.hasResult &&
                  _isRealBracketPlayer(match.awayPlayer) &&
                  winner == match.awayPlayer,
              label: awayLabel,
              slotIndex: matchIndex * 2 + 1,
              isEditable: isEditMode && roundIndex == 0,
              onSwapSlot: onSwapSlot,
            ),
            if (resolvedQualificationLabel != null) ...[
              const SizedBox(height: 8),
              _QualificationMarker(label: resolvedQualificationLabel),
            ],
          ],
        ),
      ),
    );
  }

  String? _bracketQualificationLabel() {
    return _bracketQualificationLabelFor(
      roundIndex: roundIndex,
      totalRounds: totalRounds,
      qualifyingRank: qualifyingRank,
    );
  }

  String _matchTitle() {
    if (_isPlacementMatchLabel(match.label)) {
      return match.label!;
    }
    return 'Spiel $matchNumber';
  }
}

String? _bracketQualificationLabelFor({
  required int roundIndex,
  required int totalRounds,
  required int qualifyingRank,
}) {
  if (qualifyingRank <= 0) {
    return null;
  }

  if (roundIndex == totalRounds - 1) {
    return qualifyingRank >= 2 ? 'Platz 1-2 weiter' : 'Sieger weiter';
  }

  if (roundIndex == totalRounds - 2) {
    if (qualifyingRank >= 4) return 'Platz 1-4 weiter';
    return 'Sieger weiter';
  }

  if (roundIndex == totalRounds - 3) {
    if (qualifyingRank >= 8) return 'Platz 1-8 weiter';
    return 'Sieger weiter';
  }

  return qualifyingRank > 1 ? 'Sieger weiter' : null;
}

String? _emptySlotLabel({
  required String? sourceLabel,
  required bool isEmpty,
  required TournamentPlayer? opponent,
  required bool allowsBye,
}) {
  if (!isEmpty) {
    return null;
  }
  if (_isRealBracketPlayer(opponent) &&
      (sourceLabel == null || sourceLabel == opponent!.name)) {
    return 'Freilos';
  }
  return sourceLabel ?? (allowsBye ? 'Freilos' : null);
}

bool _isRealBracketPlayer(TournamentPlayer? player) {
  if (player == null) {
    return false;
  }

  final name = player.name.trim();
  return name.isNotEmpty &&
      name != 'Freilos' &&
      name != 'offen' &&
      name != _autoAdvanceLabel &&
      !name.startsWith('Gewinner Spiel ') &&
      !name.startsWith('Verlierer Spiel ');
}

class _BracketPlayerSlot extends StatelessWidget {
  const _BracketPlayerSlot({
    required this.player,
    required this.score,
    required this.isWinner,
    this.label,
    this.slotIndex,
    this.isEditable = false,
    this.onSwapSlot,
  });

  final TournamentPlayer? player;
  final int? score;
  final bool isWinner;
  final String? label;
  final int? slotIndex;
  final bool isEditable;
  final void Function(int fromSlotIndex, int toSlotIndex)? onSwapSlot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOpen = player == null;
    final displayLabel = label ?? player?.name ?? 'offen';

    final baseSlot = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isWinner
            ? colorScheme.primaryContainer
            : isEditable
            ? colorScheme.secondaryContainer.withValues(alpha: 0.35)
            : colorScheme.surfaceContainerLowest,
        border: Border.all(
          color: isWinner
              ? colorScheme.primary
              : isEditable
              ? colorScheme.secondary
              : colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isOpen ? colorScheme.onSurfaceVariant : null,
                fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            score == null ? '-' : '$score',
            style: TextStyle(
              color: isOpen ? colorScheme.onSurfaceVariant : null,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    Widget slot = baseSlot;
    if (isEditable && slotIndex != null) {
      slot = DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != slotIndex,
        onAcceptWithDetails: (details) {
          onSwapSlot?.call(details.data, slotIndex!);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: isHovering
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.22),
                        blurRadius: 8,
                      ),
                    ]
                  : const [],
            ),
            child: baseSlot,
          );
        },
      );
    }

    if (isEditable && player != null && slotIndex != null) {
      return Draggable<int>(
        data: slotIndex!,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 220, child: slot),
        ),
        childWhenDragging: Opacity(opacity: 0.45, child: slot),
        child: slot,
      );
    }

    return slot;
  }
}

class _QualificationMarker extends StatelessWidget {
  const _QualificationMarker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
