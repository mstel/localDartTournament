part of '../../../../tournament_workspace.dart';

const double _previewBracketCardHeight = 160;

class _KnockoutPreview extends StatelessWidget {
  const _KnockoutPreview({
    required this.participantCount,
    this.placementPlaces = const [],
    required this.bracketSize,
    required this.byeCount,
    required this.eliminationLossLimit,
    required this.seedingMode,
    required this.slotOrder,
    required this.participantLabels,
    required this.allowCrossSeed,
    required this.drawOnStart,
    required this.onSeedingModeChanged,
    required this.onDrawOnStartChanged,
    required this.onSwapSlot,
    required this.onResetSlots,
  });

  final int? participantCount;
  final List<int> placementPlaces;
  final int? bracketSize;
  final int byeCount;
  final int eliminationLossLimit;
  final String seedingMode;
  final List<int?> slotOrder;
  final List<String> participantLabels;
  final bool allowCrossSeed;
  final bool drawOnStart;
  final ValueChanged<String> onSeedingModeChanged;
  final ValueChanged<bool> onDrawOnStartChanged;
  final void Function(int fromIndex, int toIndex) onSwapSlot;
  final VoidCallback onResetSlots;

  @override
  Widget build(BuildContext context) {
    if (participantCount == null || bracketSize == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Text('Mindestens 2 Teilnehmer.'),
      );
    }

    final resolvedParticipantCount = participantCount!;
    final resolvedBracketSize = bracketSize!;
    final effectiveSeedingMode = allowCrossSeed ? seedingMode : 'random';
    final slots = slotOrder.length == resolvedBracketSize
        ? slotOrder
        : List<int?>.generate(
            resolvedBracketSize,
            (index) => index < resolvedParticipantCount ? index + 1 : null,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('$resolvedParticipantCount Weiter')),
            Chip(label: Text('${resolvedBracketSize}er Feld')),
            Chip(
              label: Text(
                eliminationLossLimit >= 3
                    ? '$byeCount automatisch gesetzt'
                    : '$byeCount Freilose',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (allowCrossSeed)
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'cross',
                icon: Icon(Icons.swap_horiz),
                label: Text('Cross seeded'),
              ),
              ButtonSegment(
                value: 'random',
                icon: Icon(Icons.shuffle),
                label: Text('Zufall'),
              ),
            ],
            selected: {effectiveSeedingMode},
            onSelectionChanged: (selection) {
              onSeedingModeChanged(selection.first);
            },
          )
        else
          const Chip(
            avatar: Icon(Icons.shuffle, size: 18),
            label: Text('Zufall'),
          ),
        if (effectiveSeedingMode == 'random') ...[
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('knockout-draw-on-start-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Auslosungsrad beim Turnierstart'),
            subtitle: const Text(
              'Die Positionen werden erst ausgelost, wenn du das Turnier anlegst.',
            ),
            value: drawOnStart,
            onChanged: onDrawOnStartChanged,
          ),
        ],
        if (effectiveSeedingMode == 'cross' && byeCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            eliminationLossLimit >= 3
                ? 'Cross Seed setzt bestplatzierte Teilnehmer automatisch in die erste volle Runde.'
                : 'Cross Seed vergibt Freilose automatisch an die bestplatzierten Teilnehmer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Bracket-Vorschau',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: onResetSlots,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Auto'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (eliminationLossLimit == 2)
          _DoubleEliminationPreview(
            bracketSize: resolvedBracketSize,
            slotOrder: slots,
            participantLabels: participantLabels,
            qualifyingRank: 0,
            onSwapSlot: onSwapSlot,
          )
        else if (eliminationLossLimit >= 3)
          _TripleEliminationPreview(
            lossLimit: eliminationLossLimit,
            bracketSize: resolvedBracketSize,
            slotOrder: slots,
            participantLabels: participantLabels,
            qualifyingRank: 0,
            onSwapSlot: onSwapSlot,
          )
        else if (placementPlaces.isNotEmpty)
          Builder(
            builder: (context) {
              final players = [
                for (var i = 0; i < resolvedParticipantCount; i++)
                  TournamentPlayer(
                    name: i < participantLabels.length
                        ? participantLabels[i]
                        : 'Teilnehmer ${i + 1}',
                    isGenerated: true,
                  ),
              ];
              final rounds = _buildKnockoutRoundsForPlayers(
                players,
                slotOrder: slots,
              );
              final placements = PlacementEngine.build(
                rounds,
                placementPlaces.where((p) => p < players.length),
              );
              return _KnockoutBracketView(
                stage: KnockoutTournamentRunStage(
                  name: 'Vorschau',
                  rounds: rounds,
                ),
                qualifyingRank: 0,
                placementMatches: placements,
                onEditResult: (_) {},
                canEditResults: false,
                isEditMode: true,
                onSwapSlot: onSwapSlot,
              );
            },
          )
        else
          _CompactKnockoutPreviewTree(
            bracketSize: resolvedBracketSize,
            slotOrder: slots,
            participantLabels: participantLabels,
            onSwapSlot: onSwapSlot,
            showOnlyFirstRound: eliminationLossLimit > 1,
            qualifyingRank: 0,
          ),
      ],
    );
  }
}

class _TripleEliminationPreview extends StatelessWidget {
  const _TripleEliminationPreview({
    this.lossLimit = 3,
    required this.bracketSize,
    required this.slotOrder,
    required this.participantLabels,
    required this.qualifyingRank,
    required this.onSwapSlot,
  });

  final int lossLimit;
  final int bracketSize;
  final List<int?> slotOrder;
  final List<String> participantLabels;
  final int qualifyingRank;
  final void Function(int fromIndex, int toIndex) onSwapSlot;

  @override
  Widget build(BuildContext context) {
    final previewPlayers = [
      for (var index = 0; index < participantLabels.length; index++)
        TournamentPlayer(name: participantLabels[index], isGenerated: true),
    ];
    final rounds = _buildTripleEliminationRoundsFromSlots(
      previewPlayers,
      slotOrder,
      lossLimit: lossLimit,
    );
    final matchNumbers = _stageMatchNumbers(rounds);
    final sourceLabels = _lossLevelSourceLabels(rounds, matchNumbers);
    final sourceMatches = _lossLevelSourceMatches(rounds);
    final lossRounds = [
      for (var lossCount = 0; lossCount < lossLimit; lossCount++)
        [
          for (
            var roundNumber = 1;
            roundNumber <= _lossLevelRoundCount(rounds, lossCount);
            roundNumber++
          )
            lossCount == 0 && roundNumber == 1
                ? rounds.first
                : _matchesWithLabel(
                    rounds,
                    _lossLevelMatchLabel(lossCount, roundNumber),
                  ),
        ],
    ];
    final finalMatches = _matchesWithLabel(rounds, _tripleFinalLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var lossCount = 0; lossCount < lossLimit; lossCount++) ...[
          _BracketBandTitle(title: _lossLevelBracketLabel(lossCount)),
          const SizedBox(height: 8),
          _BracketTreeLayout(
            totalRounds: lossRounds[lossCount].length,
            roundTitles: [
              for (
                var roundNumber = 1;
                roundNumber <= lossRounds[lossCount].length;
                roundNumber++
              )
                lossCount == 0
                    ? _bracketRoundTitle(
                        roundNumber - 1,
                        lossRounds[lossCount].length,
                      )
                    : _bracketRoundTitle(
                        roundNumber - 1,
                        lossRounds[lossCount].length,
                      ),
            ],
            roundCards: [
              for (
                var roundIndex = 0;
                roundIndex < lossRounds[lossCount].length;
                roundIndex++
              )
                _previewCardsFor(
                  lossRounds[lossCount][roundIndex],
                  rounds,
                  matchNumbers,
                  sourceLabels,
                  roundIndex: roundIndex,
                  totalRounds: lossRounds[lossCount].length,
                ),
            ],
            roundMatches: lossRounds[lossCount],
            sourceMatches: sourceMatches,
            columnWidth: 170,
            cardHeight: _previewBracketCardHeight,
            firstRoundGap: 10,
            useBalancedColumnLayout: true,
          ),
          const SizedBox(height: 16),
        ],
        const _BracketBandTitle(title: 'Finale'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: 1,
          roundTitles: const ['Finale'],
          roundCards: [
            _previewCardsFor(
              finalMatches,
              rounds,
              matchNumbers,
              sourceLabels,
              roundIndex: 0,
              totalRounds: 1,
            ),
          ],
          roundMatches: [finalMatches],
          sourceMatches: sourceMatches,
          columnWidth: 170,
          cardHeight: _previewBracketCardHeight,
          firstRoundGap: 10,
          useBalancedColumnLayout: true,
        ),
      ],
    );
  }

  List<Widget> _previewCardsFor(
    List<GroupMatch> matches,
    List<List<GroupMatch>> rounds,
    Map<GroupMatch, int> matchNumbers,
    Map<GroupMatch, ({String? first, String? second})> sourceLabels, {
    required int roundIndex,
    required int totalRounds,
  }) {
    final qualificationLabel = _bracketQualificationLabelFor(
      roundIndex: roundIndex,
      totalRounds: totalRounds,
      qualifyingRank: qualifyingRank,
    );
    return [
      for (final match in matches)
        if (rounds.isNotEmpty && rounds.first.contains(match))
          _BracketPreviewMatch(
            matchNumber: matchNumbers[match] ?? 0,
            topSlotIndex: rounds.first.indexOf(match) * 2,
            bottomSlotIndex: rounds.first.indexOf(match) * 2 + 1,
            slotOrder: slotOrder,
            participantLabels: participantLabels,
            qualificationLabel: qualificationLabel,
            onSwapSlot: onSwapSlot,
          )
        else
          _BracketPreviewPlaceholderMatch(
            matchNumber: matchNumbers[match] ?? 0,
            topLabel: _previewAdvancementLabel(sourceLabels[match]?.first),
            bottomLabel: _previewAdvancementLabel(sourceLabels[match]?.second),
            qualificationLabel: qualificationLabel,
          ),
    ];
  }
}

String _previewAdvancementLabel(String? sourceLabel) =>
    sourceLabel == null || sourceLabel == 'Freilos'
    ? 'Qualifikant offen'
    : sourceLabel;

class _DoubleEliminationPreview extends StatelessWidget {
  const _DoubleEliminationPreview({
    required this.bracketSize,
    required this.slotOrder,
    required this.participantLabels,
    required this.qualifyingRank,
    required this.onSwapSlot,
  });

  final int bracketSize;
  final List<int?> slotOrder;
  final List<String> participantLabels;
  final int qualifyingRank;
  final void Function(int fromIndex, int toIndex) onSwapSlot;

  @override
  Widget build(BuildContext context) {
    final previewPlayers = [
      for (var index = 0; index < participantLabels.length; index++)
        TournamentPlayer(name: participantLabels[index], isGenerated: true),
    ];
    final rounds = _buildDoubleEliminationRoundsFromSlots(
      previewPlayers,
      slotOrder,
    );
    final matchNumbers = _stageMatchNumbers(rounds);
    final sourceLabels = _doubleSourceLabels(rounds, matchNumbers);
    final sourceMatches = _doubleSourceMatches(rounds);
    final winnersRounds = [
      for (
        var roundNumber = 1;
        roundNumber <= _doubleWinnersRoundCount(rounds);
        roundNumber++
      )
        _doubleWinnersRoundMatches(rounds, roundNumber),
    ];
    final losersRounds = [
      for (
        var roundNumber = 1;
        roundNumber <= _doubleLosersRoundCount(rounds);
        roundNumber++
      )
        _matchesWithLabel(rounds, _doubleLosersLabel(roundNumber)),
    ];
    final finalMatches = _matchesWithLabel(rounds, _doubleGrandFinalLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BracketBandTitle(title: 'Winners Bracket'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: winnersRounds.length,
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
              _previewCardsFor(
                winnersRounds[roundIndex],
                rounds,
                matchNumbers,
                sourceLabels,
                roundIndex: roundIndex,
                totalRounds: winnersRounds.length,
              ),
          ],
          roundMatches: winnersRounds,
          sourceMatches: sourceMatches,
          columnWidth: 170,
          cardHeight: _previewBracketCardHeight,
          firstRoundGap: 10,
          useBalancedColumnLayout: true,
        ),
        const SizedBox(height: 16),
        const _BracketBandTitle(title: 'Losers Bracket'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: losersRounds.length,
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
              _previewCardsFor(
                losersRounds[roundIndex],
                rounds,
                matchNumbers,
                sourceLabels,
                roundIndex: roundIndex,
                totalRounds: losersRounds.length,
              ),
          ],
          roundMatches: losersRounds,
          sourceMatches: sourceMatches,
          columnWidth: 170,
          cardHeight: _previewBracketCardHeight,
          firstRoundGap: 10,
          useBalancedColumnLayout: true,
        ),
        const SizedBox(height: 16),
        const _BracketBandTitle(title: 'Finale'),
        const SizedBox(height: 8),
        _BracketTreeLayout(
          totalRounds: finalMatches.isEmpty ? 0 : 1,
          roundTitles: const ['Finale'],
          roundCards: [
            _previewCardsFor(
              finalMatches,
              rounds,
              matchNumbers,
              sourceLabels,
              roundIndex: 0,
              totalRounds: 1,
            ),
          ],
          roundMatches: [finalMatches],
          sourceMatches: sourceMatches,
          columnWidth: 170,
          cardHeight: _previewBracketCardHeight,
          firstRoundGap: 10,
          useBalancedColumnLayout: true,
        ),
      ],
    );
  }

  List<Widget> _previewCardsFor(
    List<GroupMatch> matches,
    List<List<GroupMatch>> rounds,
    Map<GroupMatch, int> matchNumbers,
    Map<GroupMatch, ({String? first, String? second})> sourceLabels, {
    required int roundIndex,
    required int totalRounds,
  }) {
    final qualificationLabel = _bracketQualificationLabelFor(
      roundIndex: roundIndex,
      totalRounds: totalRounds,
      qualifyingRank: qualifyingRank,
    );
    return [
      for (final match in matches)
        if (rounds.isNotEmpty && rounds.first.contains(match))
          _BracketPreviewMatch(
            matchNumber: matchNumbers[match] ?? 0,
            topSlotIndex: rounds.first.indexOf(match) * 2,
            bottomSlotIndex: rounds.first.indexOf(match) * 2 + 1,
            slotOrder: slotOrder,
            participantLabels: participantLabels,
            qualificationLabel: qualificationLabel,
            onSwapSlot: onSwapSlot,
          )
        else
          _BracketPreviewPlaceholderMatch(
            matchNumber: matchNumbers[match] ?? 0,
            topLabel: _previewAdvancementLabel(sourceLabels[match]?.first),
            bottomLabel: _previewAdvancementLabel(sourceLabels[match]?.second),
            qualificationLabel: qualificationLabel,
          ),
    ];
  }
}

class _CompactKnockoutPreviewTree extends StatelessWidget {
  const _CompactKnockoutPreviewTree({
    required this.bracketSize,
    required this.slotOrder,
    required this.participantLabels,
    required this.onSwapSlot,
    this.showOnlyFirstRound = false,
    this.qualifyingRank = 1,
  });

  final int bracketSize;
  final List<int?> slotOrder;
  final List<String> participantLabels;
  final void Function(int fromIndex, int toIndex) onSwapSlot;
  final bool showOnlyFirstRound;
  final int qualifyingRank;

  @override
  Widget build(BuildContext context) {
    final roundSizes = <int>[];
    var matchesInRound = bracketSize ~/ 2;
    var remainingSlots = bracketSize;
    final safeQualifyingRank = qualifyingRank < 1 ? 1 : qualifyingRank;
    while (matchesInRound >= 1) {
      roundSizes.add(matchesInRound);
      if (showOnlyFirstRound) {
        break;
      }
      remainingSlots = matchesInRound;
      if (remainingSlots <= safeQualifyingRank) {
        break;
      }
      matchesInRound ~/= 2;
    }

    return _BracketTreeLayout(
      totalRounds: roundSizes.length,
      columnWidth: 160,
      cardHeight: _previewBracketCardHeight,
      firstRoundGap: 10,
      roundTitles: [
        for (var roundIndex = 0; roundIndex < roundSizes.length; roundIndex++)
          showOnlyFirstRound
              ? 'Runde 1'
              : _bracketRoundTitle(roundIndex, roundSizes.length),
      ],
      roundCards: [
        for (var roundIndex = 0; roundIndex < roundSizes.length; roundIndex++)
          [
            for (
              var matchIndex = 0;
              matchIndex < roundSizes[roundIndex];
              matchIndex++
            )
              if (roundIndex == 0)
                _BracketPreviewMatch(
                  matchNumber: matchIndex + 1,
                  topSlotIndex: matchIndex * 2,
                  bottomSlotIndex: matchIndex * 2 + 1,
                  slotOrder: slotOrder,
                  participantLabels: participantLabels,
                  qualificationLabel: _bracketQualificationLabelFor(
                    roundIndex: roundIndex,
                    totalRounds: roundSizes.length,
                    qualifyingRank: qualifyingRank,
                  ),
                  onSwapSlot: onSwapSlot,
                )
              else
                _BracketPreviewPlaceholderMatch(
                  matchNumber: matchIndex + 1,
                  topLabel: 'Gewinner Spiel ${matchIndex * 2 + 1}',
                  bottomLabel: 'Gewinner Spiel ${matchIndex * 2 + 2}',
                  qualificationLabel: _bracketQualificationLabelFor(
                    roundIndex: roundIndex,
                    totalRounds: roundSizes.length,
                    qualifyingRank: qualifyingRank,
                  ),
                ),
          ],
      ],
    );
  }
}

class _BracketPreviewPlaceholderMatch extends StatelessWidget {
  const _BracketPreviewPlaceholderMatch({
    required this.matchNumber,
    this.topLabel = 'Freilos',
    this.bottomLabel = 'Freilos',
    this.qualificationLabel,
  });

  final int matchNumber;
  final String topLabel;
  final String bottomLabel;
  final String? qualificationLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Spiel $matchNumber',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          _BracketPreviewOpenSlot(label: topLabel),
          const SizedBox(height: 5),
          _BracketPreviewOpenSlot(label: bottomLabel),
          if (qualificationLabel != null) ...[
            const SizedBox(height: 6),
            _QualificationMarker(label: qualificationLabel!),
          ],
        ],
      ),
    );
  }
}

class _BracketPreviewOpenSlot extends StatelessWidget {
  const _BracketPreviewOpenSlot({this.label = 'Freilos'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label),
    );
  }
}

class _BracketPreviewMatch extends StatelessWidget {
  const _BracketPreviewMatch({
    required this.matchNumber,
    required this.topSlotIndex,
    required this.bottomSlotIndex,
    required this.slotOrder,
    required this.participantLabels,
    required this.onSwapSlot,
    this.qualificationLabel,
  });

  final int matchNumber;
  final int topSlotIndex;
  final int bottomSlotIndex;
  final List<int?> slotOrder;
  final List<String> participantLabels;
  final void Function(int fromIndex, int toIndex) onSwapSlot;
  final String? qualificationLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Spiel $matchNumber',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          _BracketPreviewSlot(
            slotIndex: topSlotIndex,
            slotCount: slotOrder.length,
            seed: _seedAt(topSlotIndex),
            label: _slotLabel(_seedAt(topSlotIndex)),
            onSwapSlot: onSwapSlot,
          ),
          const SizedBox(height: 5),
          _BracketPreviewSlot(
            slotIndex: bottomSlotIndex,
            slotCount: slotOrder.length,
            seed: _seedAt(bottomSlotIndex),
            label: _slotLabel(_seedAt(bottomSlotIndex)),
            onSwapSlot: onSwapSlot,
          ),
          if (qualificationLabel != null) ...[
            const SizedBox(height: 6),
            _QualificationMarker(label: qualificationLabel!),
          ],
        ],
      ),
    );
  }

  int? _seedAt(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= slotOrder.length) {
      return null;
    }
    return slotOrder[slotIndex];
  }

  String _slotLabel(int? seed) {
    if (seed == null) {
      return 'Freilos';
    }

    final labelIndex = seed - 1;
    if (labelIndex >= 0 && labelIndex < participantLabels.length) {
      return participantLabels[labelIndex];
    }

    return 'Platz $seed';
  }
}

class _BracketPreviewSlot extends StatelessWidget {
  const _BracketPreviewSlot({
    required this.slotIndex,
    required this.slotCount,
    required this.seed,
    required this.label,
    required this.onSwapSlot,
  });

  final int slotIndex;
  final int slotCount;
  final int? seed;
  final String label;
  final void Function(int fromIndex, int toIndex) onSwapSlot;

  @override
  Widget build(BuildContext context) {
    final isBye = seed == null;
    final isRealSlot = slotIndex >= 0 && slotIndex < slotCount;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: isBye
            ? colorScheme.surfaceContainerHighest
            : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isBye ? colorScheme.outlineVariant : colorScheme.primary,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isBye
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 24, height: 28),
            padding: EdgeInsets.zero,
            onPressed: !isRealSlot || slotIndex == 0
                ? null
                : () => onSwapSlot(slotIndex, slotIndex - 1),
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            tooltip: 'Slot nach oben',
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 24, height: 28),
            padding: EdgeInsets.zero,
            onPressed: !isRealSlot || slotIndex >= slotCount - 1
                ? null
                : () => onSwapSlot(slotIndex, slotIndex + 1),
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            tooltip: 'Slot nach unten',
          ),
        ],
      ),
    );
  }
}

class _GroupQualificationSetup extends StatelessWidget {
  const _GroupQualificationSetup({
    required this.groupSizes,
    required this.groupPlayTypes,
    required this.qualificationPlan,
    required this.autoAdjust,
    required this.bestOfQualifierCountController,
    required this.onSetExtraGroup,
    required this.onCyclePlace,
    required this.onAutoAdjustChanged,
    required this.onBestOfQualifierCountChanged,
  });

  final List<int> groupSizes;
  final List<String> groupPlayTypes;
  final QualificationPlan? qualificationPlan;
  final bool autoAdjust;
  final TextEditingController bestOfQualifierCountController;
  final void Function(int groupNumber, bool selected, List<int> currentGroups)
  onSetExtraGroup;
  final void Function(int groupNumber, int place) onCyclePlace;
  final ValueChanged<bool> onAutoAdjustChanged;
  final ValueChanged<String> onBestOfQualifierCountChanged;

  int _selectedQualifierCount(QualificationPlan plan) {
    final fixedTotal = plan.fixedByGroup.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    return fixedTotal + plan.extraCount.clamp(0, plan.extraGroups.length);
  }

  List<String> _validationMessages(QualificationPlan? plan) {
    if (autoAdjust || plan == null) {
      return const [];
    }

    final selectedCount = _selectedQualifierCount(plan);
    final fixedTotal = plan.fixedByGroup.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    if (fixedTotal > plan.totalQualifiers) {
      return [
        'Es sind ${fixedTotal - plan.totalQualifiers} feste Plätze zu viel markiert.',
      ];
    }

    if (plan.extraGroups.length < plan.extraCount) {
      return [
        'Es fehlen ${plan.extraCount - plan.extraGroups.length} Gruppen für den Beste-${plan.extraCount}-Vergleich.',
      ];
    }

    if (selectedCount == plan.totalQualifiers) {
      return const [];
    }

    if (selectedCount < plan.totalQualifiers) {
      return [
        'Es kommen noch ${plan.totalQualifiers - selectedCount} Spieler zu wenig weiter. Erhöhe "Beste-N Weiter" oder markiere feste Plätze.',
      ];
    }

    return [
      'Es kommen ${selectedCount - plan.totalQualifiers} Spieler zu viel weiter. Reduziere "Beste-N Weiter" oder feste Plätze.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (groupSizes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Erst Spieler und Gruppen anlegen.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Weiterkommensregel',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.auto_fix_high_outlined),
                label: Text('Automatik'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.tune_outlined),
                label: Text('Manuell'),
              ),
            ],
            selected: {autoAdjust},
            onSelectionChanged: (selection) {
              onAutoAdjustChanged(selection.first);
            },
          ),
        ),
        const SizedBox(height: 8),
        QualificationRuleSummary(qualificationPlan: qualificationPlan),
        if (qualificationPlan != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 180,
            child: TextField(
              controller: bestOfQualifierCountController,
              enabled: !autoAdjust,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Beste-N Weiter',
                prefixIcon: Icon(Icons.workspace_premium_outlined),
              ),
              onChanged: onBestOfQualifierCountChanged,
            ),
          ),
        ],
        for (final message in _validationMessages(qualificationPlan)) ...[
          const SizedBox(height: 8),
          QualificationErrorBanner(message: message),
        ],
        const SizedBox(height: 12),
        QualificationGroupPreview(
          groupSizes: groupSizes,
          qualificationPlan: qualificationPlan,
          onCyclePlace: onCyclePlace,
        ),
        _GroupEliminationPreviewSection(
          groupSizes: groupSizes,
          groupPlayTypes: groupPlayTypes,
          qualificationPlan: qualificationPlan,
        ),
        if (qualificationPlan != null && qualificationPlan!.extraCount > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Gruppen im Beste-${qualificationPlan!.extraCount}-Vergleich',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < groupSizes.length; index++)
                FilterChip(
                  key: ValueKey('extra-group-chip-${index + 1}'),
                  label: Text(groupLabel(index + 1)),
                  selected: qualificationPlan!.extraGroups.contains(index + 1),
                  onSelected: groupSizes[index] < qualificationPlan!.extraRank
                      ? null
                      : (selected) => onSetExtraGroup(
                          index + 1,
                          selected,
                          qualificationPlan!.extraGroups,
                        ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GroupEliminationPreviewSection extends StatelessWidget {
  const _GroupEliminationPreviewSection({
    required this.groupSizes,
    required this.groupPlayTypes,
    required this.qualificationPlan,
  });

  final List<int> groupSizes;
  final List<String> groupPlayTypes;
  final QualificationPlan? qualificationPlan;

  @override
  Widget build(BuildContext context) {
    final previewGroups = [
      for (var index = 0; index < groupSizes.length; index++)
        if (_isEliminationGroupPlayType(_playTypeFor(index)) &&
            groupSizes[index] >= 2)
          index,
    ];

    if (previewGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Spieltyp-Vorschau der Gruppen',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final groupIndex in previewGroups) ...[
                  _GroupEliminationPreviewCard(
                    groupNumber: groupIndex + 1,
                    playerCount: groupSizes[groupIndex],
                    playType: _playTypeFor(groupIndex),
                    qualifyingRank: _qualifyingRankFor(groupIndex),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _playTypeFor(int groupIndex) {
    if (groupIndex >= 0 && groupIndex < groupPlayTypes.length) {
      return groupPlayTypes[groupIndex];
    }
    return 'round_robin';
  }

  int _qualifyingRankFor(int groupIndex) {
    final plan = qualificationPlan;
    if (plan == null) {
      return 1;
    }

    final fixedForGroup = groupIndex < plan.fixedByGroup.length
        ? plan.fixedByGroup[groupIndex]
        : plan.fixedPerGroup;
    final groupNumber = groupIndex + 1;
    final extraRank = plan.extraGroups.contains(groupNumber)
        ? plan.extraRank
        : 0;
    final requiredRank = fixedForGroup > extraRank ? fixedForGroup : extraRank;
    return requiredRank < 1 ? 1 : requiredRank;
  }
}

class _GroupEliminationPreviewCard extends StatelessWidget {
  const _GroupEliminationPreviewCard({
    required this.groupNumber,
    required this.playerCount,
    required this.playType,
    required this.qualifyingRank,
  });

  final int groupNumber;
  final int playerCount;
  final String playType;
  final int qualifyingRank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bracketSize = _nextPowerOfTwo(playerCount);
    final labels = [
      for (var index = 0; index < playerCount; index++) 'Platz ${index + 1}',
    ];
    final slots = [
      for (final seed in _seedOrderForSize(bracketSize))
        seed <= playerCount ? seed : null,
    ];
    final lossLimit = _lossLimitForGroupPlayType(playType);
    final width = switch (lossLimit) {
      3 => 720.0,
      2 => 660.0,
      _ => 520.0,
    };

    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                groupLabel(groupNumber),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Chip(label: Text(_groupPlayTypeLabel(playType))),
              Chip(label: Text('$playerCount Spieler')),
              Chip(label: Text('${bracketSize}er Feld')),
              if (bracketSize > playerCount)
                Chip(label: Text('${bracketSize - playerCount} Freilose')),
            ],
          ),
          const SizedBox(height: 10),
          _GroupEliminationBracketPreview(
            lossLimit: lossLimit,
            bracketSize: bracketSize,
            slotOrder: slots,
            participantLabels: labels,
            qualifyingRank: qualifyingRank,
          ),
        ],
      ),
    );
  }
}

class _GroupEliminationBracketPreview extends StatelessWidget {
  const _GroupEliminationBracketPreview({
    required this.lossLimit,
    required this.bracketSize,
    required this.slotOrder,
    required this.participantLabels,
    required this.qualifyingRank,
  });

  final int lossLimit;
  final int bracketSize;
  final List<int?> slotOrder;
  final List<String> participantLabels;
  final int qualifyingRank;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: switch (lossLimit) {
        3 => _TripleEliminationPreview(
          bracketSize: bracketSize,
          slotOrder: slotOrder,
          participantLabels: participantLabels,
          qualifyingRank: qualifyingRank,
          onSwapSlot: (_, _) {},
        ),
        2 => _DoubleEliminationPreview(
          bracketSize: bracketSize,
          slotOrder: slotOrder,
          participantLabels: participantLabels,
          qualifyingRank: qualifyingRank,
          onSwapSlot: (_, _) {},
        ),
        _ => _CompactKnockoutPreviewTree(
          bracketSize: bracketSize,
          slotOrder: slotOrder,
          participantLabels: participantLabels,
          onSwapSlot: (_, _) {},
          qualifyingRank: qualifyingRank,
        ),
      },
    );
  }
}

class _InheritedKnockoutSetup extends StatelessWidget {
  const _InheritedKnockoutSetup({
    required this.previousStage,
    this.placementPlaces = const [],
    required this.qualificationPlan,
    required this.participantCount,
    required this.bracketSize,
    required this.byeCount,
    required this.eliminationLossLimit,
    required this.seedingMode,
    required this.slotOrder,
    required this.participantLabels,
    required this.allowCrossSeed,
    required this.drawOnStart,
    required this.onSeedingModeChanged,
    required this.onDrawOnStartChanged,
    required this.onSwapSlot,
    required this.onResetSlots,
  });

  final TournamentStage? previousStage;
  final List<int> placementPlaces;
  final QualificationPlan? qualificationPlan;
  final int? participantCount;
  final int? bracketSize;
  final int byeCount;
  final int eliminationLossLimit;
  final String seedingMode;
  final List<int?> slotOrder;
  final List<String> participantLabels;
  final bool allowCrossSeed;
  final bool drawOnStart;
  final ValueChanged<String> onSeedingModeChanged;
  final ValueChanged<bool> onDrawOnStartChanged;
  final void Function(int fromIndex, int toIndex) onSwapSlot;
  final VoidCallback onResetSlots;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          previousStage == null
              ? 'Start mit allen Spielern'
              : 'Übernahme aus vorheriger Etappe',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (previousStage == null)
          const Text('Alle angelegten Spieler nehmen teil.')
        else if (qualificationPlan != null)
          QualificationRuleSummary(qualificationPlan: qualificationPlan)
        else
          Text(
            previousStage!.qualificationSummary ?? 'Alle Teilnehmer weiter.',
          ),
        const SizedBox(height: 8),
        _KnockoutPreview(
          placementPlaces: placementPlaces,
          participantCount: participantCount,
          bracketSize: bracketSize,
          byeCount: byeCount,
          eliminationLossLimit: eliminationLossLimit,
          seedingMode: seedingMode,
          slotOrder: slotOrder,
          participantLabels: participantLabels,
          allowCrossSeed: allowCrossSeed,
          drawOnStart: drawOnStart,
          onSeedingModeChanged: onSeedingModeChanged,
          onDrawOnStartChanged: onDrawOnStartChanged,
          onSwapSlot: onSwapSlot,
          onResetSlots: onResetSlots,
        ),
      ],
    );
  }
}

class _StageList extends StatelessWidget {
  const _StageList({
    required this.stages,
    required this.editingStageIndex,
    required this.onEditStage,
    required this.onRemoveStage,
  });

  final List<TournamentStage> stages;
  final int? editingStageIndex;
  final void Function(int index) onEditStage;
  final void Function(int index) onRemoveStage;

  String _typeLabel(String type) {
    return switch (type) {
      'single_knockout' => 'K.-o.-Runde',
      'double_knockout' => 'Doppel-K.-o.',
      'triple_knockout' => 'Triple-K.-o.',
      'kratzer' => 'Kratzer-Modus',
      _ => 'Gruppen/Liga',
    };
  }

  String _repeatDetails(TournamentStage stage) {
    if (stage.groupRoundRobinRepeats.isEmpty) {
      return '';
    }

    final details = [
      for (var index = 0; index < stage.groupSizes.length; index++)
        if (_groupPlayTypeForStage(stage, index) == 'swiss')
          '${groupLabel(index + 1)} ${_roundRobinRepeatForStage(stage, index)} Swiss-Runden'
        else if (_groupPlayTypeForStage(stage, index) == 'round_robin')
          '${groupLabel(index + 1)} ${index < stage.groupRoundRobinRepeats.length ? stage.groupRoundRobinRepeats[index] : 1}x${stage.maxGamesForGroup(index) == null ? '' : ' · maximal ${stage.maxGamesForGroup(index)} Spiele pro Spieler'}',
    ].join(', ');

    return details.isEmpty ? '' : ' - Begegnungen: $details';
  }

  int _stageMatchCount(TournamentStage stage) {
    if (_isKnockoutStageType(stage.type)) {
      return _eliminationMatchEstimate(
            stage.knockoutParticipantCount ?? 0,
            stage.lossLimit,
          ) +
          (stage.lossLimit == 1
              ? _optionalPlacementMatchCount(
                  stage.knockoutParticipantCount ?? 0,
                  stage.placementPlaces,
                )
              : 0);
    }

    var totalMatches = 0;
    for (var index = 0; index < stage.groupSizes.length; index++) {
      final repeatCount = _roundRobinRepeatForStage(stage, index);
      final playType = _groupPlayTypeForStage(stage, index);
      totalMatches += playType == 'swiss'
          ? (stage.groupSizes[index] ~/ 2) * repeatCount
          : playType == 'round_robin'
          ? _roundRobinMatchCount(
              stage.groupSizes[index],
              repeatCount,
              maxGamesPerPlayer: stage.maxGamesForGroup(index),
            )
          : playType == 'mini_knockout' && stage.placementPlaces.isNotEmpty
          ? stage.groupSizes[index] -
                1 +
                _optionalPlacementMatchCount(stage.groupSizes[index], {
                  ...stage.placementPlaces,
                  if (_requiredRankForStoredStageGroup(stage, index).isOdd &&
                      _requiredRankForStoredStageGroup(stage, index) >= 3)
                    _requiredRankForStoredStageGroup(stage, index),
                })
          : _groupEliminationMatchEstimate(
              stage.groupSizes[index],
              _lossLimitForGroupPlayType(playType),
              _requiredRankForStoredStageGroup(stage, index),
            );
    }

    return totalMatches;
  }

  int _requiredRankForStoredStageGroup(TournamentStage stage, int groupIndex) {
    final groupCount = stage.groupCount ?? stage.groupSizes.length;
    final fixedForGroup = groupIndex < stage.fixedQualifiersByGroup.length
        ? stage.fixedQualifiersByGroup[groupIndex]
        : groupCount == 0
        ? 1
        : (stage.qualifiedParticipantCount ?? 1) ~/ groupCount;
    final groupNumber = groupIndex + 1;
    final extraRank = stage.qualifiersByGroup.contains(groupNumber)
        ? stage.extraQualifierRank ?? fixedForGroup + 1
        : 0;
    final requiredRank = fixedForGroup > extraRank ? fixedForGroup : extraRank;
    return requiredRank < 1 ? 1 : requiredRank;
  }

  String _matchCountDetails(TournamentStage stage) {
    return ' - ${stage.placementPlaces.isEmpty ? '' : 'bis zu '}${_stageMatchCount(stage)} Spiele';
  }

  String _stageDetails(TournamentStage stage) {
    if (stage.type != 'groups' || stage.groupSizes.isEmpty) {
      if (_isKnockoutStageType(stage.type) &&
          stage.knockoutParticipantCount != null &&
          stage.knockoutBracketSize != null) {
        final qualifierText = stage.qualificationSummary == null
            ? ''
            : ' - ${stage.qualificationSummary}';
        final seedingText = stage.knockoutSeedingMode == 'random'
            ? ' - Zufall'
            : ' - Cross seeded';
        final drawText = stage.knockoutDrawOnStart
            ? ' - Auslosungsrad aktiv'
            : '';

        return '${_typeLabel(stage.type)} - '
            '${stage.knockoutParticipantCount} Teilnehmer, '
            '${stage.knockoutBracketSize}er Feld, '
            '${stage.lossLimit == 3 ? '${stage.knockoutByeCount} automatisch gesetzt' : '${stage.knockoutByeCount} Freilose'}'
            '${stage.lossLimit > 1
                ? stage.finalEndsTournament
                      ? ' - Ein großes Finale entscheidet'
                      : ' - Kratzer-Modus: ${stage.lossLimit} Leben'
                : ''}'
            '${stage.placementPlaces.isEmpty ? '' : ' - Platzierungsspiele: ${stage.placementPlaces.join(', ')}'}'
            '$seedingText'
            '$drawText'
            '${_matchCountDetails(stage)}'
            '$qualifierText';
      }

      return _typeLabel(stage.type);
    }

    final sizes = stage.groupSizes
        .asMap()
        .entries
        .map((entry) => '${groupLabel(entry.key + 1)}: ${entry.value}')
        .join(', ');

    final qualifierText = stage.qualificationSummary == null
        ? ''
        : ' - ${stage.qualificationSummary}';
    final playTypeText =
        ' - Spieltypen: ${stage.groupSizes.asMap().entries.map((entry) {
          return '${groupLabel(entry.key + 1)} ${_groupPlayTypeLabel(_groupPlayTypeForStage(stage, entry.key))}';
        }).join(', ')}';
    final repeatText = _repeatDetails(stage);
    final drawText = stage.groupDrawOnStart ? ' - Auslosungsrad aktiv' : '';
    final tieBreakerText =
        ' - Tie-Breaker: ${stage.groupTieBreakers.map(tieBreakerLabel).join(', ')}';

    return '${_typeLabel(stage.type)} - $sizes$playTypeText$repeatText$drawText${_matchCountDetails(stage)}$qualifierText$tieBreakerText';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (stages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Noch keine Etappen hinzugefügt.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${stages.length} Etappen im Turnier',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < stages.length; index++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: editingStageIndex == index
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(stages[index].name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_stageDetails(stages[index])),
                  Text(stages[index].gameFormat.label),
                ],
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: () => onEditStage(index),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Etappe bearbeiten',
                  ),
                  IconButton(
                    onPressed: () => onRemoveStage(index),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Etappe entfernen',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
