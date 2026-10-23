part of '../../../../tournament_workspace.dart';

class TournamentCreationPage extends StatefulWidget {
  const TournamentCreationPage({super.key});

  @override
  State<TournamentCreationPage> createState() => _TournamentCreationPageState();
}

class _TournamentCreationPageState extends State<TournamentCreationPage> {
  bool _showEntryChoices = true;
  bool _countsForRanking = false;
  bool _rankingSetupTouched = false;
  final List<String> _localRankingIds = [];
  final _tournamentNameController = TextEditingController();
  final _playerNameController = TextEditingController();
  final _playerCountController = TextEditingController(text: '8');
  final _stageNameController = TextEditingController();
  final _groupCountController = TextEditingController(text: '2');
  final _groupQualifierCountController = TextEditingController(text: '8');
  final _bestOfQualifierCountController = TextEditingController(text: '0');
  final _database = LocalAppDatabase();
  late final Future<List<LocalRanking>> _localRankings = _database
      .loadLocalRankings();
  final Set<int> _selectedExtraGroups = {};
  final List<TournamentPlayer> _players = [];
  int _plannedBoardCount = 4;
  final List<TournamentStage> _stages = [];
  final List<String> _groupTieBreakers = List<String>.from(
    defaultGroupTieBreakers,
  );
  final GroupTieBreakerPreferences _groupTieBreakerPreferences =
      GroupTieBreakerPreferences();
  Future<void> _groupTieBreakerSaveQueue = Future<void>.value();
  bool _groupTieBreakersTouched = false;
  final List<int> _groupRoundRobinRepeats = [];
  final List<int?> _groupMaxGamesPerPlayer = [];

  List<int?> _gameLimitsForGroupSizes(List<int> sizes) => [
    for (var i = 0; i < sizes.length; i++)
      _playTypesForGroupSizes(sizes)[i] == 'round_robin' &&
              i < _groupMaxGamesPerPlayer.length
          ? _groupMaxGamesPerPlayer[i]
          : null,
  ];
  void _setGroupGameLimit(int index, int? limit) => setState(() {
    while (_groupMaxGamesPerPlayer.length <= index) {
      _groupMaxGamesPerPlayer.add(null);
    }
    _groupMaxGamesPerPlayer[index] = limit;
  });
  final List<String> _groupPlayTypes = [];
  final List<int> _fixedQualifiersByGroup = [];
  int? _manualExtraRank;
  int? _manualExtraCount;
  bool _autoAdjustQualification = true;
  int? _editingStageIndex;
  String _groupPlayType = 'round_robin';
  GroupPlayerAllocationMode _groupAllocationMode =
      GroupPlayerAllocationMode.strengthLevels;
  List<int?>? _manualKnockoutSlotOrder;
  final Set<int> _placementPlaces = {};
  bool _finalEndsTournament = true;
  int _kratzerLives = 3;
  int get _selectedLossLimit =>
      _selectedStageType == 'kratzer' ||
          (!_finalEndsTournament &&
              _isKnockoutStageType(_selectedStageType) &&
              _selectedStageType != 'single_knockout')
      ? _kratzerLives
      : _lossLimitForStageType(_selectedStageType);
  String _selectedStageType = 'groups';
  String _knockoutSeedingMode = 'cross';
  bool _groupDrawOnStart = false;
  bool _knockoutDrawOnStart = false;
  bool _stageNameWasEdited = false;
  bool _isOpeningPlayerPicker = false;
  bool _isCreatingTournament = false;
  TournamentGameFormat _stageGameFormat = const TournamentGameFormat();

  @override
  void initState() {
    super.initState();
    _stageNameController.text = _defaultStageName();
    unawaited(_loadGroupTieBreakers());
    unawaited(_applyDefaultRanking());
  }

  Future<void> _loadGroupTieBreakers() async {
    try {
      final saved = await _groupTieBreakerPreferences.load();
      if (!mounted || _groupTieBreakersTouched) return;
      setState(() {
        _groupTieBreakers
          ..clear()
          ..addAll(saved);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tie-Breaker konnten nicht geladen werden: $error'),
        ),
      );
    }
  }

  void _saveGroupTieBreakers() {
    final selection = List<String>.from(_groupTieBreakers);
    _groupTieBreakerSaveQueue = _groupTieBreakerSaveQueue.then((_) async {
      try {
        await _groupTieBreakerPreferences.save(selection);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tie-Breaker konnten nicht gespeichert werden: $error',
            ),
          ),
        );
      }
    });
  }

  Future<void> _applyDefaultRanking() async {
    final rankings = await _localRankings;
    if (!mounted || _rankingSetupTouched) return;
    LocalRanking? preferred;
    for (final ranking in rankings) {
      if (ranking.isDefaultForStatistics) {
        preferred = ranking;
        break;
      }
    }
    if (preferred == null) return;
    setState(() {
      _countsForRanking = true;
      _localRankingIds
        ..clear()
        ..add(preferred!.id);
    });
  }

  @override
  void dispose() {
    _tournamentNameController.dispose();
    _playerNameController.dispose();
    _playerCountController.dispose();
    _stageNameController.dispose();
    _groupCountController.dispose();
    _groupQualifierCountController.dispose();
    _bestOfQualifierCountController.dispose();
    super.dispose();
  }

  List<int> _calculateGroupSizes() {
    final groupCount = int.tryParse(_groupCountController.text);
    if (groupCount == null || groupCount < 1 || _players.isEmpty) {
      return const [];
    }

    final cappedGroupCount = groupCount > _players.length
        ? _players.length
        : groupCount;
    final baseSize = _players.length ~/ cappedGroupCount;
    final remainder = _players.length % cappedGroupCount;

    return List.generate(
      cappedGroupCount,
      (index) => baseSize + (index < remainder ? 1 : 0),
    );
  }

  List<int> _roundRobinRepeatsForGroupSizes(List<int> groupSizes) {
    return [
      for (var index = 0; index < groupSizes.length; index++)
        (_playTypesForGroupSizes(groupSizes)[index] == 'swiss'
            ? (index < _groupRoundRobinRepeats.length
                      ? _groupRoundRobinRepeats[index]
                      : 3)
                  .clamp(1, SwissEngine.maximumRounds(groupSizes[index]))
            : index < _groupRoundRobinRepeats.length
            ? _groupRoundRobinRepeats[index]
            : 1),
    ];
  }

  List<String> _playTypesForGroupSizes(List<int> groupSizes) {
    return [
      for (var index = 0; index < groupSizes.length; index++)
        index < _groupPlayTypes.length
            ? _groupPlayTypes[index]
            : _groupPlayType,
    ];
  }

  void _setDefaultGroupPlayType(String playType) {
    final groupSizes = _calculateGroupSizes();
    setState(() {
      _groupPlayType = playType;
      _groupPlayTypes
        ..clear()
        ..addAll(List.filled(groupSizes.length, playType));
    });
  }

  void _setGroupPlayType(int groupIndex, String playType) {
    final groupSizes = _calculateGroupSizes();
    if (groupIndex < 0 || groupIndex >= groupSizes.length) {
      return;
    }

    setState(() {
      while (_groupPlayTypes.length < groupSizes.length) {
        _groupPlayTypes.add(_groupPlayType);
      }
      _groupPlayTypes[groupIndex] = playType;
    });
  }

  void _changeGroupRoundRobinRepeats(int groupIndex, int delta) {
    final groupSizes = _calculateGroupSizes();
    if (groupIndex < 0 || groupIndex >= groupSizes.length) {
      return;
    }

    setState(() {
      final current = _roundRobinRepeatsForGroupSizes(groupSizes);
      while (_groupRoundRobinRepeats.length < groupSizes.length) {
        _groupRoundRobinRepeats.add(current[_groupRoundRobinRepeats.length]);
      }
      final nextValue = _groupRoundRobinRepeats[groupIndex] + delta;
      _groupRoundRobinRepeats[groupIndex] = nextValue < 1 ? 1 : nextValue;
    });
  }

  int _currentStageMatchCount() {
    if (_isKnockoutStageType(_selectedStageType)) {
      return _eliminationMatchEstimate(
            _knockoutParticipantCount() ?? 0,
            _selectedLossLimit,
          ) +
          (_selectedLossLimit == 1
              ? _optionalPlacementMatchCount(
                  _knockoutParticipantCount() ?? 0,
                  _placementPlaces,
                )
              : 0);
    }

    final groupSizes = _calculateGroupSizes();
    final repeats = _roundRobinRepeatsForGroupSizes(groupSizes);
    final playTypes = _playTypesForGroupSizes(groupSizes);
    final qualificationPlan = _groupQualificationPlan();
    var totalMatches = 0;
    for (var index = 0; index < groupSizes.length; index++) {
      totalMatches += playTypes[index] == 'swiss'
          ? (groupSizes[index] ~/ 2) * repeats[index]
          : playTypes[index] == 'round_robin'
          ? _roundRobinMatchCount(
              groupSizes[index],
              repeats[index],
              maxGamesPerPlayer: _gameLimitsForGroupSizes(groupSizes)[index],
            )
          : playTypes[index] == 'mini_knockout' && _placementPlaces.isNotEmpty
          ? groupSizes[index] -
                1 +
                _optionalPlacementMatchCount(groupSizes[index], {
                  ..._placementPlaces,
                  if (_requiredRankForCurrentGroup(
                        index,
                        qualificationPlan,
                      ).isOdd &&
                      _requiredRankForCurrentGroup(index, qualificationPlan) >=
                          3)
                    _requiredRankForCurrentGroup(index, qualificationPlan),
                })
          : _groupEliminationMatchEstimate(
              groupSizes[index],
              _lossLimitForGroupPlayType(playTypes[index]),
              _requiredRankForCurrentGroup(index, qualificationPlan),
            );
    }

    return totalMatches;
  }

  List<String> _currentStageMatchDetails() {
    if (_isKnockoutStageType(_selectedStageType)) {
      final participants = _knockoutParticipantCount() ?? 0;
      final byeCount = _knockoutByeCount();
      return [
        '$participants Teilnehmer',
        _selectedLossLimit == 3
            ? '$byeCount automatisch gesetzt'
            : '$byeCount Freilose',
        if (_selectedLossLimit > 1) '$_selectedLossLimit Niederlage(n) bis Aus',
      ];
    }

    final groupSizes = _calculateGroupSizes();
    final repeats = _roundRobinRepeatsForGroupSizes(groupSizes);
    final playTypes = _playTypesForGroupSizes(groupSizes);
    final qualificationPlan = _groupQualificationPlan();
    return [
      for (var index = 0; index < groupSizes.length; index++)
        playTypes[index] == 'swiss'
            ? '${groupLabel(index + 1)} ${repeats[index]} Runden · ${(groupSizes[index] ~/ 2) * repeats[index]} Spiele'
            : playTypes[index] == 'round_robin'
            ? '${groupLabel(index + 1)} ${_roundRobinMatchCount(groupSizes[index], repeats[index], maxGamesPerPlayer: _gameLimitsForGroupSizes(groupSizes)[index])} Spiele${_gameLimitsForGroupSizes(groupSizes)[index] == null ? '' : ' · maximal ${_gameLimitsForGroupSizes(groupSizes)[index]} pro Spieler'}'
            : '${groupLabel(index + 1)} ${_groupEliminationMatchEstimate(groupSizes[index], _lossLimitForGroupPlayType(playTypes[index]), _requiredRankForCurrentGroup(index, qualificationPlan))}',
    ];
  }

  int _requiredRankForCurrentGroup(
    int groupIndex,
    QualificationPlan? qualificationPlan,
  ) {
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

  int? _groupQualifierCount() {
    final participantCount = int.tryParse(_groupQualifierCountController.text);
    if (participantCount == null || participantCount < 2) {
      return null;
    }

    return participantCount;
  }

  int? _inheritedParticipantCount() {
    final previousStage = _previousStageForCurrentForm();
    if (previousStage == null) {
      return _players.length;
    }

    return previousStage.qualifiedParticipantCount ??
        previousStage.knockoutParticipantCount ??
        _players.length;
  }

  int? _knockoutParticipantCount() {
    final participantCount = _inheritedParticipantCount();
    if (participantCount == null || participantCount < 2) {
      return null;
    }

    return participantCount;
  }

  int? _knockoutBracketSize() {
    final participantCount = _knockoutParticipantCount();
    if (participantCount == null) {
      return null;
    }

    var bracketSize = 2;
    while (bracketSize < participantCount) {
      bracketSize *= 2;
    }

    return bracketSize;
  }

  int _knockoutByeCount() {
    final participantCount = _knockoutParticipantCount();
    final bracketSize = _knockoutBracketSize();
    if (participantCount == null || bracketSize == null) {
      return 0;
    }

    return bracketSize - participantCount;
  }

  List<int?> _automaticKnockoutSlotOrder(
    int participantCount,
    int bracketSize,
  ) {
    if (_effectiveKnockoutSeedingMode() == 'random') {
      return _randomKnockoutSlotOrder(participantCount, bracketSize);
    }

    return _crossSeededKnockoutSlotOrder(participantCount, bracketSize);
  }

  List<int?> _randomKnockoutSlotOrder(int participantCount, int bracketSize) {
    final shuffledSeeds = <int>[
      for (var seed = 1; seed <= participantCount; seed++) seed,
    ]..shuffle(Random());

    var seedIndex = 0;
    return [
      for (final bracketSeed in _seedOrderForSize(bracketSize))
        bracketSeed <= participantCount ? shuffledSeeds[seedIndex++] : null,
    ];
  }

  List<int?> _crossSeededKnockoutSlotOrder(
    int participantCount,
    int bracketSize,
  ) {
    final seedSources = _knockoutSeedSources(participantCount);
    final strengthOrderedSources = List<_KnockoutSeedSource>.from(seedSources)
      ..sort(_compareKnockoutSeedStrength);
    final byeCount = bracketSize - participantCount;

    if (byeCount == 0) {
      final pairs = <List<_KnockoutSeedSource>>[];
      final remaining = List<_KnockoutSeedSource>.from(strengthOrderedSources);

      while (remaining.isNotEmpty) {
        final stronger = remaining.removeAt(0);
        var opponentIndex = remaining.lastIndexWhere((candidate) {
          return !_sameKnownGroup(stronger, candidate);
        });
        if (opponentIndex == -1) {
          opponentIndex = remaining.length - 1;
        }
        final weaker = remaining.removeAt(opponentIndex);
        pairs.add([stronger, weaker]);
      }

      return [
        for (final pair in pairs) ...[pair[0].seed, pair[1].seed],
      ];
    }

    return [
      for (final bracketSeed in _seedOrderForSize(bracketSize))
        bracketSeed <= participantCount
            ? strengthOrderedSources[bracketSeed - 1].seed
            : null,
    ];
  }

  List<int> _defaultFixedQualifiersForPlan(
    List<int> groupSizes,
    QualificationPlan? plan,
  ) {
    if (plan == null) {
      return List.filled(groupSizes.length, 0);
    }

    return [
      for (final groupSize in groupSizes)
        plan.fixedPerGroup > groupSize ? groupSize : plan.fixedPerGroup,
    ];
  }

  List<int> _currentFixedQualifiersByGroup(
    List<int> groupSizes,
    QualificationPlan? fallbackPlan,
  ) {
    if (_fixedQualifiersByGroup.length == groupSizes.length) {
      return [
        for (var index = 0; index < groupSizes.length; index++)
          _fixedQualifiersByGroup[index].clamp(0, groupSizes[index]).toInt(),
      ];
    }

    return _defaultFixedQualifiersForPlan(groupSizes, fallbackPlan);
  }

  int _compareKnockoutSeedStrength(
    _KnockoutSeedSource a,
    _KnockoutSeedSource b,
  ) {
    final placeCompare = a.place.compareTo(b.place);
    if (placeCompare != 0) {
      return placeCompare;
    }
    final groupCompare = (a.groupNumber ?? 999).compareTo(b.groupNumber ?? 999);
    if (groupCompare != 0) {
      return groupCompare;
    }
    return a.seed.compareTo(b.seed);
  }

  bool _sameKnownGroup(_KnockoutSeedSource a, _KnockoutSeedSource b) {
    return a.groupNumber != null && a.groupNumber == b.groupNumber;
  }

  List<_KnockoutSeedSource> _knockoutSeedSources(int participantCount) {
    final previousStage = _previousStageForCurrentForm();
    final groupPlan = _storedGroupQualificationPlan(previousStage);
    if (previousStage == null ||
        previousStage.type != 'groups' ||
        previousStage.groupSizes.isEmpty) {
      return [
        for (var seed = 1; seed <= participantCount; seed++)
          _KnockoutSeedSource(seed: seed, groupNumber: null, place: seed),
      ];
    }

    final sources = <_KnockoutSeedSource>[];
    var seed = 1;
    if (groupPlan == null) {
      for (
        var groupIndex = 0;
        groupIndex < previousStage.groupSizes.length;
        groupIndex++
      ) {
        for (
          var place = 1;
          place <= previousStage.groupSizes[groupIndex];
          place++
        ) {
          sources.add(
            _KnockoutSeedSource(
              seed: seed,
              groupNumber: groupIndex + 1,
              place: place,
            ),
          );
          seed++;
        }
      }
    } else {
      for (
        var groupIndex = 0;
        groupIndex < previousStage.groupSizes.length;
        groupIndex++
      ) {
        final fixedForGroup = groupIndex < groupPlan.fixedByGroup.length
            ? groupPlan.fixedByGroup[groupIndex]
            : groupPlan.fixedPerGroup;
        for (var place = 1; place <= fixedForGroup; place++) {
          sources.add(
            _KnockoutSeedSource(
              seed: seed,
              groupNumber: groupIndex + 1,
              place: place,
            ),
          );
          seed++;
        }
      }
      for (final groupNumber in groupPlan.extraGroups) {
        sources.add(
          _KnockoutSeedSource(
            seed: seed,
            groupNumber: groupNumber,
            place: groupPlan.extraRank,
          ),
        );
        seed++;
      }
    }

    while (sources.length < participantCount) {
      sources.add(
        _KnockoutSeedSource(
          seed: sources.length + 1,
          groupNumber: null,
          place: sources.length + 1,
        ),
      );
    }

    return sources.take(participantCount).toList();
  }

  bool _isValidKnockoutSlotOrder(
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

  bool _slotOrderGivesBestSeedsByes(
    List<int?> slotOrder,
    int participantCount,
    int bracketSize,
  ) {
    final byeCount = bracketSize - participantCount;
    if (byeCount <= 0) {
      return true;
    }

    final expectedByeSeeds = _strongestByeSeeds(participantCount, byeCount);
    final actualByeSeeds = <int>{};
    for (var index = 0; index < slotOrder.length; index += 2) {
      final first = slotOrder[index];
      final second = index + 1 < slotOrder.length ? slotOrder[index + 1] : null;
      if (first == null && second != null) {
        actualByeSeeds.add(second);
      } else if (second == null && first != null) {
        actualByeSeeds.add(first);
      }
    }

    return actualByeSeeds.length == expectedByeSeeds.length &&
        actualByeSeeds.containsAll(expectedByeSeeds);
  }

  Set<int> _strongestByeSeeds(int participantCount, int byeCount) {
    final seedSources = _knockoutSeedSources(participantCount);
    seedSources.sort((a, b) {
      final placeCompare = a.place.compareTo(b.place);
      if (placeCompare != 0) {
        return placeCompare;
      }
      final groupCompare = (a.groupNumber ?? 999).compareTo(
        b.groupNumber ?? 999,
      );
      if (groupCompare != 0) {
        return groupCompare;
      }
      return a.seed.compareTo(b.seed);
    });

    return seedSources.take(byeCount).map((source) => source.seed).toSet();
  }

  List<int?> _knockoutSlotOrder() {
    final participantCount = _knockoutParticipantCount();
    final bracketSize = _knockoutBracketSize();
    if (participantCount == null || bracketSize == null) {
      return const [];
    }

    final manualOrder = _manualKnockoutSlotOrder;
    final seedingMode = _effectiveKnockoutSeedingMode();
    if (manualOrder != null &&
        _isValidKnockoutSlotOrder(manualOrder, participantCount, bracketSize) &&
        _slotOrderAvoidsByePair(manualOrder) &&
        (seedingMode != 'cross' ||
            _slotOrderGivesBestSeedsByes(
              manualOrder,
              participantCount,
              bracketSize,
            ))) {
      return List<int?>.from(manualOrder);
    }

    return _automaticKnockoutSlotOrder(participantCount, bracketSize);
  }

  bool _slotOrderAvoidsByePair(List<int?> slotOrder) {
    for (var index = 0; index < slotOrder.length; index += 2) {
      final first = slotOrder[index];
      final second = index + 1 < slotOrder.length ? slotOrder[index + 1] : null;
      if (first == null && second == null) {
        return false;
      }
    }
    return true;
  }

  List<String> _knockoutParticipantLabels() {
    final participantCount = _knockoutParticipantCount();
    if (participantCount == null) {
      return const [];
    }

    final previousStage = _previousStageForCurrentForm();
    final groupPlan = _storedGroupQualificationPlan(previousStage);
    if (previousStage == null ||
        previousStage.type != 'groups' ||
        previousStage.groupSizes.isEmpty) {
      return [
        for (var index = 0; index < participantCount; index++)
          'Platz ${index + 1}',
      ];
    }

    final labels = <String>[];
    if (groupPlan == null) {
      for (
        var groupIndex = 0;
        groupIndex < previousStage.groupSizes.length;
        groupIndex++
      ) {
        for (
          var place = 1;
          place <= previousStage.groupSizes[groupIndex];
          place++
        ) {
          labels.add('$place. ${groupLabel(groupIndex + 1)}');
        }
      }
    } else {
      for (
        var groupIndex = 0;
        groupIndex < previousStage.groupSizes.length;
        groupIndex++
      ) {
        final fixedForGroup = groupIndex < groupPlan.fixedByGroup.length
            ? groupPlan.fixedByGroup[groupIndex]
            : groupPlan.fixedPerGroup;
        for (var place = 1; place <= fixedForGroup; place++) {
          labels.add('$place. ${groupLabel(groupIndex + 1)}');
        }
      }
      for (final groupNumber in groupPlan.extraGroups) {
        labels.add('${groupPlan.extraRank}. ${groupLabel(groupNumber)}');
      }
    }

    while (labels.length < participantCount) {
      labels.add('Platz ${labels.length + 1}');
    }

    return labels.take(participantCount).toList();
  }

  void _swapKnockoutSlots(int fromIndex, int toIndex) {
    final slots = _knockoutSlotOrder();
    if (fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= slots.length ||
        toIndex >= slots.length) {
      return;
    }

    setState(() {
      final moved = slots[fromIndex];
      slots[fromIndex] = slots[toIndex];
      slots[toIndex] = moved;
      _manualKnockoutSlotOrder = slots;
    });
  }

  void _resetKnockoutSlots() {
    setState(() {
      if (_effectiveKnockoutSeedingMode() == 'random') {
        final participantCount = _knockoutParticipantCount();
        final bracketSize = _knockoutBracketSize();
        _manualKnockoutSlotOrder =
            participantCount == null || bracketSize == null
            ? null
            : _randomKnockoutSlotOrder(participantCount, bracketSize);
      } else {
        _manualKnockoutSlotOrder = null;
      }
    });
  }

  void _setKnockoutSeedingMode(String mode) {
    setState(() {
      _knockoutSeedingMode = _hasGroupSeedSources() ? mode : 'random';
      if (_knockoutSeedingMode == 'random') {
        final participantCount = _knockoutParticipantCount();
        final bracketSize = _knockoutBracketSize();
        _manualKnockoutSlotOrder =
            participantCount == null || bracketSize == null
            ? null
            : _randomKnockoutSlotOrder(participantCount, bracketSize);
      } else {
        _manualKnockoutSlotOrder = null;
        _knockoutDrawOnStart = false;
      }
    });
  }

  void _setKnockoutDrawOnStart(bool enabled) {
    setState(() {
      _knockoutDrawOnStart =
          _effectiveKnockoutSeedingMode() == 'random' && enabled;
    });
  }

  bool _hasGroupSeedSources() {
    final previousStage = _previousStageForCurrentForm();
    return previousStage != null &&
        previousStage.type == 'groups' &&
        previousStage.groupSizes.isNotEmpty;
  }

  String _effectiveKnockoutSeedingMode() {
    return _hasGroupSeedSources() ? _knockoutSeedingMode : 'random';
  }

  Widget _responsiveFormRow({
    required Widget leading,
    required Widget trailing,
    bool alignTrailingEndOnNarrow = false,
    double breakpoint = 560,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            breakpoint * (MediaQuery.textScalerOf(context).scale(16) / 16)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              leading,
              const SizedBox(height: 12),
              alignTrailingEndOnNarrow
                  ? Align(alignment: Alignment.centerRight, child: trailing)
                  : trailing,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leading),
            const SizedBox(width: 12),
            alignTrailingEndOnNarrow ? trailing : Expanded(child: trailing),
          ],
        );
      },
    );
  }

  TournamentStage? _latestGroupStage() {
    final endIndex = _editingStageIndex ?? _stages.length;
    for (var index = endIndex - 1; index >= 0; index--) {
      final stage = _stages[index];
      if (stage.type == 'groups' && stage.groupSizes.isNotEmpty) {
        return stage;
      }
    }

    return null;
  }

  TournamentStage? _previousStageForCurrentForm() {
    final editingIndex = _editingStageIndex;
    if (editingIndex != null) {
      return editingIndex == 0 ? null : _stages[editingIndex - 1];
    }

    return _stages.isEmpty ? null : _stages.last;
  }

  String _stageTypeLabel(String type) {
    return switch (type) {
      'single_knockout' => 'K.-o.-Runde',
      'double_knockout' => 'Doppel-K.-o.',
      'triple_knockout' => 'Triple-K.-o.',
      'kratzer' => 'Kratzer-Modus',
      _ => 'Gruppenphase',
    };
  }

  String _defaultStageName([String? stageType]) {
    final type = stageType ?? _selectedStageType;
    final baseName = _stageTypeLabel(type);
    final sameTypeCount = _stages.where((stage) => stage.type == type).length;
    return sameTypeCount == 0 ? baseName : '$baseName ${sameTypeCount + 1}';
  }

  void _setDefaultStageNameIfNeeded([String? stageType]) {
    if (_stageNameWasEdited && _stageNameController.text.trim().isNotEmpty) {
      return;
    }

    _stageNameController.text = _defaultStageName(stageType);
    _stageNameController.selection = TextSelection.collapsed(
      offset: _stageNameController.text.length,
    );
  }

  QualificationPlan? _qualificationPlanForGroupSizes(
    List<int> groupSizes,
    int? participantCount,
  ) {
    if (participantCount == null) {
      return null;
    }

    final groupCount = groupSizes.length;
    if (groupCount == 0) {
      return null;
    }

    final maxQualifiers = groupSizes.fold<int>(0, (sum, size) => sum + size);
    final cappedParticipantCount = participantCount > maxQualifiers
        ? maxQualifiers
        : participantCount;
    final fixedPerGroup = cappedParticipantCount ~/ groupCount;
    final automaticExtraCount = cappedParticipantCount % groupCount;
    final hasManualFixed = _fixedQualifiersByGroup.length == groupSizes.length;
    final fixedByGroup = hasManualFixed
        ? _currentFixedQualifiersByGroup(groupSizes, null)
        : [
            for (final groupSize in groupSizes)
              fixedPerGroup > groupSize ? groupSize : fixedPerGroup,
          ];
    final fixedTotal = fixedByGroup.fold<int>(0, (sum, value) => sum + value);
    final extraCount = !_autoAdjustQualification && hasManualFixed
        ? (_manualExtraCount ?? 0).clamp(0, groupCount).toInt()
        : hasManualFixed
        ? (cappedParticipantCount - fixedTotal).clamp(0, groupCount).toInt()
        : automaticExtraCount;
    final extraRank = hasManualFixed
        ? (_manualExtraRank ?? fixedPerGroup + 1)
        : fixedPerGroup + 1;
    final eligibleGroupSize = extraCount == 0
        ? null
        : groupSizes
              .where((size) => size >= extraRank)
              .fold<int>(0, (largest, size) => size > largest ? size : largest);
    final eligibleGroups = extraCount == 0
        ? const <int>[]
        : [
            for (var index = 0; index < groupSizes.length; index++)
              if (groupSizes[index] >= extraRank) index + 1,
          ];
    final automaticExtraGroups = eligibleGroupSize == null
        ? const <int>[]
        : [
            for (var index = 0; index < groupSizes.length; index++)
              if (groupSizes[index] == eligibleGroupSize) index + 1,
          ];
    final manualExtraGroups =
        _selectedExtraGroups
            .where((groupNumber) => eligibleGroups.contains(groupNumber))
            .toList()
          ..sort();
    final extraGroups =
        manualExtraGroups.isNotEmpty || !_autoAdjustQualification
        ? manualExtraGroups
        : automaticExtraGroups;

    return QualificationPlan(
      totalQualifiers: cappedParticipantCount,
      fixedPerGroup: fixedPerGroup,
      extraCount: extraCount,
      extraRank: extraRank,
      eligibleGroupSize: eligibleGroupSize,
      extraGroups: extraGroups,
      fixedByGroup: fixedByGroup,
    );
  }

  QualificationPlan? _groupQualificationPlan() {
    return _qualificationPlanForGroupSizes(
      _calculateGroupSizes(),
      _groupQualifierCount(),
    );
  }

  QualificationPlan? _storedGroupQualificationPlan(TournamentStage? stage) {
    if (stage == null || stage.groupSizes.isEmpty) {
      return null;
    }

    final participantCount = stage.qualifiedParticipantCount;
    if (participantCount == null) {
      return null;
    }

    final groupCount = stage.groupSizes.length;
    final maxQualifiers = stage.groupSizes.fold<int>(
      0,
      (sum, size) => sum + size,
    );
    final cappedParticipantCount = participantCount > maxQualifiers
        ? maxQualifiers
        : participantCount;
    final fixedPerGroup = cappedParticipantCount ~/ groupCount;
    final storedFixedByGroup = stage.fixedQualifiersByGroup.length == groupCount
        ? [
            for (var index = 0; index < groupCount; index++)
              stage.fixedQualifiersByGroup[index]
                  .clamp(0, stage.groupSizes[index])
                  .toInt(),
          ]
        : [
            for (final groupSize in stage.groupSizes)
              fixedPerGroup > groupSize ? groupSize : fixedPerGroup,
          ];
    final fixedTotal = storedFixedByGroup.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final automaticExtraCount = (cappedParticipantCount - fixedTotal)
        .clamp(0, groupCount)
        .toInt();
    final extraCount = stage.qualificationAutoAdjust
        ? automaticExtraCount
        : (stage.extraQualifierCount ?? automaticExtraCount)
              .clamp(0, groupCount)
              .toInt();
    final extraRank = stage.extraQualifierRank ?? fixedPerGroup + 1;
    final eligibleGroupSize = extraCount == 0
        ? null
        : stage.groupSizes
              .where((size) => size >= extraRank)
              .fold<int>(0, (largest, size) => size > largest ? size : largest);

    return QualificationPlan(
      totalQualifiers: cappedParticipantCount,
      fixedPerGroup: fixedPerGroup,
      extraCount: extraCount,
      extraRank: extraRank,
      eligibleGroupSize: eligibleGroupSize,
      extraGroups: stage.qualifiersByGroup,
      fixedByGroup: storedFixedByGroup,
    );
  }

  void _addPlayer() {
    final playerName = _playerNameController.text.trim();
    if (playerName.isEmpty) {
      return;
    }

    setState(() {
      _players.add(TournamentPlayer(name: playerName, isGenerated: false));
      _playerNameController.clear();
    });
  }

  void _generatePlayers() {
    final requestedCount = int.tryParse(_playerCountController.text);
    if (requestedCount == null || requestedCount < 1) {
      return;
    }

    setState(() {
      _players
        ..clear()
        ..addAll(
          List.generate(
            requestedCount,
            (index) => TournamentPlayer.generated(index + 1),
          ),
        );
    });
  }

  Future<void> _selectPlayersFromDatabase() async {
    if (_isOpeningPlayerPicker) {
      return;
    }

    setState(() {
      _isOpeningPlayerPicker = true;
    });

    try {
      final profiles = await _database.loadPlayerProfiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _isOpeningPlayerPicker = false;
      });
      final selectedProfiles = await showDialog<List<PlayerProfile>>(
        context: context,
        builder: (context) => PlayerProfilePickerDialog(
          profiles: profiles,
          createPlayer: (firstName, lastName) => _database.createPlayerProfile(
            firstName: firstName,
            lastName: lastName,
          ),
          selectedProfileIds: {
            for (final player in _players.expand((p) => p.individuals))
              if (player.profileId != null) player.profileId!,
          },
        ),
      );
      if (selectedProfiles == null || !mounted) {
        return;
      }
      setState(() {
        final guestPlayers = _players
            .where((player) => player.profileId == null)
            .toList(growable: false);
        _players
          ..clear()
          ..addAll(guestPlayers)
          ..addAll(
            selectedProfiles
                .map(
                  (profile) => TournamentPlayer(
                    profileId: profile.id,
                    name: profile.displayName,
                    isGenerated: false,
                    compactName: profile.compactDisplayName,
                  ),
                )
                .where(
                  (p) => !guestPlayers
                      .expand((t) => t.individuals)
                      .any((m) => m.profileId == p.profileId),
                ),
          );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isOpeningPlayerPicker = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Spieler konnten nicht aus der Datenbank geladen werden.',
          ),
        ),
      );
    }
  }

  void _removePlayer(int index) {
    setState(() {
      _players.removeAt(index);
    });
  }

  void _mergePlayers(int source, int target) {
    try {
      final team = TournamentPlayer.team([_players[target], _players[source]]);
      setState(() {
        _players[target] = team;
        _players.removeAt(source);
      });
    } on ArgumentError catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  void _splitTeam(int index) {
    setState(() {
      final members = _players.removeAt(index).individuals;
      _players.insertAll(index, members);
    });
  }

  Future<void> _renamePlayer(int index) async {
    if (index < 0 ||
        index >= _players.length ||
        _players[index].profileId != null ||
        _players[index].isTeam) {
      return;
    }
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => RenamePlayerDialog(player: _players[index]),
    );

    if (newName == null || newName.trim().isEmpty) {
      return;
    }

    setState(() {
      _players[index] = _players[index].copyWith(
        name: newName.trim(),
        isGenerated: false,
      );
    });
  }

  Widget _placementSelection() {
    final sizes = _selectedStageType == 'groups'
        ? _calculateGroupSizes()
        : <int>[_knockoutParticipantCount() ?? 0];
    final maximum = sizes.fold<int>(0, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Optionale Platzierungsspiele'),
        const Text(
          'Mehrere Plätze auswählbar. Nötige Vorrunden werden automatisch ergänzt. In Mini-KO-Gruppen gilt die Auswahl je Gruppe.',
        ),
        Wrap(
          spacing: 8,
          children: [
            for (var place = 3; place < maximum; place += 2)
              FilterChip(
                label: Text('Platz $place'),
                selected: _placementPlaces.contains(place),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _placementPlaces.add(place);
                  } else {
                    _placementPlaces.remove(place);
                  }
                }),
              ),
          ],
        ),
        if (maximum < 4) const Text('Ab 4 Teilnehmern verfügbar.'),
        const SizedBox(height: 12),
      ],
    );
  }

  void _saveStage() {
    if (_selectedStageType == 'groups' &&
        !hasValidGroupSizes(_calculateGroupSizes())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Jede Gruppe benötigt mindestens 3 Spieler. Bitte weniger Gruppen wählen oder Spieler ergänzen.',
          ),
        ),
      );
      return;
    }
    if (_stageGameFormat.bestOfLegs.isEven &&
        (_stageGameFormat.bestOfSets > 1 ||
            _selectedStageType != 'groups' ||
            !['round_robin', 'swiss'].contains(_groupPlayType) ||
            _groupPlayTypes.any(
              (type) => !['round_robin', 'swiss'].contains(type),
            ))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gerade Leg-Längen sind nur für Jeder-gegen-jeden oder Swiss ohne Sets möglich.',
          ),
        ),
      );
      return;
    }
    final stageName = _stageNameController.text.trim();
    if (stageName.isEmpty) {
      return;
    }

    setState(() {
      final stage = _currentStageConfiguration();

      final editingIndex = _editingStageIndex;
      if (editingIndex == null) {
        _stages.add(stage);
      } else {
        _stages[editingIndex] = stage;
      }

      _resetStageForm();
    });
  }

  TournamentStage _currentStageConfiguration() {
    final latestGroupStage = _latestGroupStage();
    final groupQualificationPlan = _selectedStageType == 'groups'
        ? _groupQualificationPlan()
        : null;
    final inheritedQualificationPlan = _isKnockoutStageType(_selectedStageType)
        ? _storedGroupQualificationPlan(latestGroupStage)
        : null;
    return TournamentStage(
      name: _stageNameController.text.trim(),
      type: _selectedStageType,
      placementPlaces:
          (_selectedStageType == 'single_knockout' ||
              _selectedStageType == 'groups')
          ? (_placementPlaces.toList()..sort())
          : const [],
      finalEndsTournament:
          _selectedStageType != 'kratzer' && _finalEndsTournament,
      knockoutLives: _isKnockoutStageType(_selectedStageType)
          ? _selectedLossLimit
          : null,
      groupCount: _selectedStageType == 'groups'
          ? _calculateGroupSizes().length
          : null,
      groupSizes: _selectedStageType == 'groups'
          ? _calculateGroupSizes()
          : const [],
      groupPlayType: _selectedStageType == 'groups'
          ? _groupPlayType
          : 'round_robin',
      groupPlayTypes: _selectedStageType == 'groups'
          ? _playTypesForGroupSizes(_calculateGroupSizes())
          : const [],
      groupRoundRobinRepeats: _selectedStageType == 'groups'
          ? _roundRobinRepeatsForGroupSizes(_calculateGroupSizes())
          : const [],
      groupTieBreakers: _selectedStageType == 'groups'
          ? List.unmodifiable(_groupTieBreakers)
          : defaultGroupTieBreakers,
      groupMaxGamesPerPlayer: _selectedStageType == 'groups'
          ? _gameLimitsForGroupSizes(_calculateGroupSizes())
          : const [],
      groupDrawOnStart: _selectedStageType == 'groups'
          ? _groupDrawOnStart
          : false,
      groupSlotOrder: const [],
      knockoutParticipantCount: _isKnockoutStageType(_selectedStageType)
          ? _knockoutParticipantCount()
          : null,
      knockoutBracketSize: _isKnockoutStageType(_selectedStageType)
          ? _knockoutBracketSize()
          : null,
      knockoutByeCount: _isKnockoutStageType(_selectedStageType)
          ? _knockoutByeCount()
          : 0,
      knockoutSlotOrder: _isKnockoutStageType(_selectedStageType)
          ? (_knockoutDrawOnStart && _effectiveKnockoutSeedingMode() == 'random'
                ? const []
                : _knockoutSlotOrder())
          : const [],
      knockoutSeedingMode: _isKnockoutStageType(_selectedStageType)
          ? _effectiveKnockoutSeedingMode()
          : 'cross',
      knockoutDrawOnStart: _isKnockoutStageType(_selectedStageType)
          ? _knockoutDrawOnStart && _effectiveKnockoutSeedingMode() == 'random'
          : false,
      qualifiersByGroup: _selectedStageType == 'groups'
          ? groupQualificationPlan?.extraGroups ?? const []
          : const [],
      fixedQualifiersByGroup: _selectedStageType == 'groups'
          ? groupQualificationPlan?.fixedByGroup ?? const []
          : const [],
      extraQualifierRank: _selectedStageType == 'groups'
          ? groupQualificationPlan?.extraRank
          : null,
      extraQualifierCount: _selectedStageType == 'groups'
          ? groupQualificationPlan?.extraCount
          : null,
      qualificationAutoAdjust: _selectedStageType == 'groups'
          ? _autoAdjustQualification
          : true,
      qualifiedParticipantCount: _selectedStageType == 'groups'
          ? groupQualificationPlan?.totalQualifiers
          : null,
      qualificationSummary: _selectedStageType == 'groups'
          ? groupQualificationPlan?.summary
          : inheritedQualificationPlan?.summary,
      gameFormat: _stageGameFormat,
    );
  }

  void _resetStageForm() {
    _editingStageIndex = null;
    _stageNameWasEdited = false;
    _selectedStageType = 'groups';
    _placementPlaces.clear();
    _finalEndsTournament = true;
    _kratzerLives = 3;
    _groupPlayType = 'round_robin';
    _groupPlayTypes.clear();
    _groupRoundRobinRepeats.clear();
    _groupMaxGamesPerPlayer.clear();
    _fixedQualifiersByGroup.clear();
    _manualExtraRank = null;
    _manualExtraCount = null;
    _bestOfQualifierCountController.text = '0';
    _autoAdjustQualification = true;
    _selectedExtraGroups.clear();
    _groupTieBreakers
      ..clear()
      ..addAll(defaultGroupTieBreakers);
    _manualKnockoutSlotOrder = null;
    _knockoutSeedingMode = 'cross';
    _groupDrawOnStart = false;
    _knockoutDrawOnStart = false;
    _stageGameFormat = const TournamentGameFormat();
    _setDefaultStageNameIfNeeded();
  }

  void _editStage(int index) {
    final stage = _stages[index];
    setState(() {
      _editingStageIndex = index;
      _selectedStageType = stage.type;
      _placementPlaces
        ..clear()
        ..addAll(stage.placementPlaces);
      _finalEndsTournament = stage.finalEndsTournament;
      _kratzerLives = stage.lossLimit;
      _stageNameController.text = stage.name;
      _stageNameController.selection = TextSelection.collapsed(
        offset: _stageNameController.text.length,
      );
      _stageNameWasEdited = true;
      _stageGameFormat = stage.gameFormat;

      if (stage.type == 'groups') {
        _groupCountController.text = '${stage.groupSizes.length}';
        _groupQualifierCountController.text =
            '${stage.qualifiedParticipantCount ?? stage.groupSizes.fold<int>(0, (sum, size) => sum + size)}';
        _selectedExtraGroups
          ..clear()
          ..addAll(stage.qualifiersByGroup);
        _groupPlayType = stage.groupPlayType;
        _groupPlayTypes
          ..clear()
          ..addAll(stage.groupPlayTypes);
        _groupRoundRobinRepeats
          ..clear()
          ..addAll(stage.groupRoundRobinRepeats);
        _groupMaxGamesPerPlayer
          ..clear()
          ..addAll(stage.groupMaxGamesPerPlayer);
        _groupTieBreakers
          ..clear()
          ..addAll(stage.groupTieBreakers);
        _fixedQualifiersByGroup
          ..clear()
          ..addAll(stage.fixedQualifiersByGroup);
        _manualExtraRank = stage.extraQualifierRank;
        _manualExtraCount = stage.extraQualifierCount;
        _bestOfQualifierCountController.text =
            '${stage.extraQualifierCount ?? 0}';
        _autoAdjustQualification = stage.qualificationAutoAdjust;
        _groupDrawOnStart = stage.groupDrawOnStart;
        _groupAllocationMode = stage.groupDrawOnStart
            ? GroupPlayerAllocationMode.random
            : GroupPlayerAllocationMode.strengthLevels;
      } else {
        _selectedExtraGroups.clear();
        _groupPlayTypes.clear();
        _groupRoundRobinRepeats.clear();
        _groupMaxGamesPerPlayer.clear();
        _fixedQualifiersByGroup.clear();
        _manualExtraRank = null;
        _manualExtraCount = null;
        _bestOfQualifierCountController.text = '0';
        _autoAdjustQualification = true;
        _groupTieBreakers
          ..clear()
          ..addAll(defaultGroupTieBreakers);
        _groupDrawOnStart = false;
      }

      if (_isKnockoutStageType(stage.type)) {
        _knockoutSeedingMode = stage.knockoutSeedingMode;
        _manualKnockoutSlotOrder = stage.knockoutSlotOrder.isEmpty
            ? null
            : List<int?>.from(stage.knockoutSlotOrder);
        _knockoutDrawOnStart = stage.knockoutDrawOnStart;
      } else {
        _knockoutSeedingMode = 'cross';
        _manualKnockoutSlotOrder = null;
        _knockoutDrawOnStart = false;
      }
    });
  }

  void _removeStage(int index) {
    setState(() {
      _stages.removeAt(index);
      if (_editingStageIndex == index) {
        _resetStageForm();
      } else if (_editingStageIndex != null && _editingStageIndex! > index) {
        _editingStageIndex = _editingStageIndex! - 1;
      }
    });
  }

  Future<void> _openFormatPlanner() async {
    final suggestion = await showDialog<TournamentFormatSuggestion>(
      context: context,
      builder: (_) => const TournamentFormatPlannerDialog(),
    );
    if (suggestion == null || !mounted) return;
    if (suggestion.configurations.isNotEmpty) {
      if (_players.isNotEmpty &&
          _players.length != suggestion.participantCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Die Spielerzahl im Finder muss zu den ausgewählten Spielern passen.',
            ),
          ),
        );
        return;
      }
      setState(() {
        if (_players.isEmpty) {
          _players.addAll(
            List.generate(
              suggestion.participantCount,
              (i) => TournamentPlayer.generated(i + 1),
            ),
          );
        }
        _stages
          ..clear()
          ..addAll(suggestion.configurations);
        _plannedBoardCount = suggestion.boardCount.clamp(1, 64);
        _playerCountController.text = '${suggestion.participantCount}';
        _resetStageForm();
        _showEntryChoices = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vorschlag übernommen. Spieler, Etappen und Spielformate bleiben bearbeitbar.',
          ),
        ),
      );
      return;
    }
    // Preserve selected players; local drafts can start with named placeholders.
    final inferredPlayerCount = _players.isNotEmpty
        ? _players.length
        : suggestion.participantCount;
    final groups = suggestion.stages.first.groupCount;
    final sizes = List.generate(
      groups,
      (index) =>
          inferredPlayerCount ~/ groups +
          (index < inferredPlayerCount % groups ? 1 : 0),
    );
    if (groups > 0 && !hasValidGroupSizes(sizes)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Der Vorschlag passt nicht zur aktuellen Spielerzahl: mindestens 3 Spieler je Gruppe erforderlich.',
          ),
        ),
      );
      return;
    }
    final qualifiersByGroup = [
      for (final size in sizes) min(size, suggestion.qualifiersPerGroup),
    ];
    final qualifierCount = qualifiersByGroup.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    setState(() {
      if (_players.isEmpty) {
        _players.addAll(
          List.generate(
            inferredPlayerCount,
            (index) => TournamentPlayer.generated(index + 1),
          ),
        );
      }
      _stageGameFormat = suggestion.stages.first.format;
      _plannedBoardCount = suggestion.boardCount.clamp(1, 64);
      _playerCountController.text = '$inferredPlayerCount';
      _groupCountController.text = '$groups';
      _stages
        ..clear()
        ..add(
          groups == 0
              ? TournamentStage(
                  name: 'K.-o.-Finale',
                  type: 'single_knockout',
                  knockoutParticipantCount: inferredPlayerCount,
                  knockoutBracketSize: _plannerNextPowerOfTwo(
                    inferredPlayerCount,
                  ),
                  knockoutByeCount:
                      _plannerNextPowerOfTwo(inferredPlayerCount) -
                      inferredPlayerCount,
                  gameFormat: suggestion.stages.first.format,
                )
              : TournamentStage(
                  name: groups == 1 ? 'Ligaphase' : 'Gruppenphase',
                  type: 'groups',
                  groupCount: groups,
                  groupSizes: sizes,
                  groupPlayType: 'round_robin',
                  groupPlayTypes: List.filled(groups, 'round_robin'),
                  groupRoundRobinRepeats: List.filled(groups, 1),
                  qualifiedParticipantCount: groups == 1
                      ? null
                      : qualifierCount,
                  fixedQualifiersByGroup: groups == 1
                      ? const []
                      : qualifiersByGroup,
                  qualificationSummary: groups == 1
                      ? null
                      : 'Bis zu ${suggestion.qualifiersPerGroup} Beste jeder Gruppe',
                  gameFormat: suggestion.stages.first.format,
                ),
        );
      if (suggestion.stages.length > 1) {
        _stages.add(
          TournamentStage(
            name: 'K.-o.-Finale',
            type: 'single_knockout',
            knockoutParticipantCount: qualifierCount,
            knockoutBracketSize: _plannerNextPowerOfTwo(qualifierCount),
            knockoutByeCount:
                _plannerNextPowerOfTwo(qualifierCount) - qualifierCount,
            gameFormat: suggestion.stages.last.format,
          ),
        );
      }
      _resetStageForm();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _players.isEmpty
              ? 'Vorschlag übernommen. Bitte zuerst die Spieler auswählen.'
              : 'Vorschlag übernommen. Du kannst Spieler, Etappen und Spielformate weiter anpassen.',
        ),
      ),
    );
    setState(() => _showEntryChoices = false);
  }

  int _plannerNextPowerOfTwo(int value) {
    var result = 1;
    while (result < value) {
      result *= 2;
    }
    return result;
  }

  Future<void> _createTournament() async {
    if (_isCreatingTournament) return;
    if (_stages.any(
      (stage) =>
          stage.type == 'groups' && !hasValidGroupSizes(stage.groupSizes),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Jede Gruppe benötigt mindestens 3 Spieler. Bitte die Etappen anpassen.',
          ),
        ),
      );
      return;
    }
    if (_stages.isEmpty || _players.isEmpty) {
      return;
    }

    late final CreatedTournament tournament;
    setState(() => _isCreatingTournament = true);
    try {
      final controller = const TournamentCreationController();
      final name = _tournamentNameController.text.trim().isEmpty
          ? 'Neues Turnier'
          : _tournamentNameController.text.trim();
      final stages = List<TournamentStage>.unmodifiable(_stages);
      final groupRatings =
          _groupAllocationMode == GroupPlayerAllocationMode.random
          ? const <String, int>{}
          : await _loadGroupRatings();
      final runStages = _buildRunStages(stages: stages, ratings: groupRatings);
      tournament = controller.createTournament(
        boardCount: _plannedBoardCount,
        countsForRanking: _countsForRanking,
        rankingIds: _localRankingIds,
        name: name,
        players: _players,
        stages: stages,
        runStages: runStages,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCreatingTournament = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Turnier konnte nicht gespeichert werden: $error'),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _isCreatingTournament = false);
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => TournamentRunPage(tournament: tournament),
      ),
    );
  }

  Future<Map<String, int>> _loadGroupRatings() async {
    if (_players.every((player) => player.profileId == null)) {
      return const {};
    }
    final rankings = (await _localRankings)
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              (_localRankingIds.isEmpty ||
                  _localRankingIds.contains(ranking.id)),
        )
        .toList();
    final ratingsByPlayer = <String, List<int>>{};
    for (final ranking in rankings) {
      final snapshot = await LocalRankingEloService(
        database: _database,
      ).calculate(ranking);
      for (final entry in snapshot.entries) {
        ratingsByPlayer.putIfAbsent(entry.id, () => []).add(entry.rating);
      }
    }
    return {
      for (final entry in ratingsByPlayer.entries)
        entry.key:
            (entry.value.reduce((sum, rating) => sum + rating) /
                    entry.value.length)
                .round(),
    };
  }

  List<TournamentRunStage> _buildRunStages({
    List<TournamentStage>? stages,
    Map<String, int> ratings = const {},
  }) {
    final sourceStages = stages ?? _stages;
    final runStages = <TournamentRunStage>[];
    var incomingPlayers = List<TournamentPlayer>.from(_players);

    for (var stageIndex = 0; stageIndex < sourceStages.length; stageIndex++) {
      final stage = sourceStages[stageIndex];
      final requiredRank = _requiredRankAfterStage(
        stageIndex,
        incomingPlayers.length,
        stages: sourceStages,
      );
      if (stage.type == 'groups') {
        final groupParticipantCount = stage.groupSizes.fold<int>(
          0,
          (sum, size) => sum + size,
        );
        final groupPlayers = stage.groupSlotOrder.isNotEmpty
            ? incomingPlayers.take(groupParticipantCount).toList()
            : stage.groupDrawOnStart
            ? incomingPlayers.take(groupParticipantCount).toList()
            : const GroupPlayerAllocationEngine().allocate(
                players: incomingPlayers,
                groupSizes: stage.groupSizes,
                mode: _groupAllocationMode,
                ratings: ratings,
              );
        final groups = _buildTournamentGroupsForPlayers(
          stage,
          groupPlayers,
          requiredRankForGroup: _requiredRankForGroup,
        );
        runStages.add(
          GroupTournamentRunStage(
            name: stage.name,
            groupPlayType: stage.groupPlayType,
            groups: groups,
            qualificationPlan: _storedGroupQualificationPlan(stage),
            tieBreakers: stage.groupTieBreakers,
          ),
        );
        incomingPlayers = incomingPlayers
            .take(stage.qualifiedParticipantCount ?? incomingPlayers.length)
            .toList();
      } else if (_isKnockoutStageType(stage.type)) {
        final participantCount =
            stage.knockoutParticipantCount ?? incomingPlayers.length;
        final participants = incomingPlayers.take(participantCount).toList();
        final lossLimit = stage.lossLimit;
        final rounds = lossLimit == 1
            ? _buildKnockoutRounds(
                participants,
                slotOrder: stage.knockoutSlotOrder,
              )
            : lossLimit == 2
            ? _buildDoubleEliminationRounds(
                participants,
                slotOrder: stage.knockoutSlotOrder,
              )
            : _buildTripleEliminationRounds(
                participants,
                lossLimit: lossLimit,
                slotOrder: stage.knockoutSlotOrder,
              );
        runStages.add(
          KnockoutTournamentRunStage(
            name: stage.name,
            rounds: rounds,
            placementMatches: lossLimit == 1
                ? stage.placementPlaces.isEmpty
                      ? _buildPlacementMatches(
                          participants.length,
                          requiredRank,
                        )
                      : PlacementEngine.build(rounds, {
                          ...stage.placementPlaces.where(
                            (p) => p < participants.length,
                          ),
                          if (requiredRank >= 3 &&
                              requiredRank.isOdd &&
                              requiredRank < participants.length)
                            requiredRank,
                        })
                : const [],
            eliminationLossLimit: lossLimit,
            finalEndsTournament: stage.finalEndsTournament,
          ),
        );
        incomingPlayers = participants
            .take((participants.length + 1) ~/ 2)
            .toList();
      }
    }

    return runStages;
  }

  int _requiredRankAfterStage(
    int stageIndex,
    int availablePlayers, {
    List<TournamentStage>? stages,
  }) {
    final sourceStages = stages ?? _stages;
    if (stageIndex >= sourceStages.length - 1) {
      return 1;
    }

    final nextStage = sourceStages[stageIndex + 1];
    final requiredPlayers = nextStage.type == 'groups'
        ? nextStage.groupSizes.fold<int>(0, (sum, size) => sum + size)
        : nextStage.knockoutParticipantCount ?? availablePlayers;
    return requiredPlayers.clamp(1, availablePlayers).toInt();
  }

  int _requiredRankForGroup(TournamentStage stage, int groupIndex) {
    final plan = _storedGroupQualificationPlan(stage);
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

  List<GroupMatch> _buildPlacementMatches(
    int participantCount,
    int requiredRank,
  ) {
    return _buildPlacementMatchesForPlayers(participantCount, requiredRank);
  }

  List<List<GroupMatch>> _buildKnockoutRounds(
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
        _isValidKnockoutSlotOrder(slotOrder, players.length, bracketSize) &&
            _slotOrderAvoidsByePair(slotOrder)
        ? List<int?>.from(slotOrder)
        : _automaticKnockoutSlotOrder(players.length, bracketSize);
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

    var matchesInRound = firstRound.length ~/ 2;
    var roundNumber = 2;
    while (matchesInRound >= 1) {
      rounds.add(
        List.generate(matchesInRound, (_) => GroupMatch(round: roundNumber)),
      );
      matchesInRound ~/= 2;
      roundNumber++;
    }

    _advanceKnockoutWinnersInRounds(rounds);
    return rounds;
  }

  List<List<GroupMatch>> _buildDoubleEliminationRounds(
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
        _isValidKnockoutSlotOrder(slotOrder, players.length, bracketSize) &&
            _slotOrderAvoidsByePair(slotOrder)
        ? List<int?>.from(slotOrder)
        : _automaticKnockoutSlotOrder(players.length, bracketSize);
    return _buildDoubleEliminationRoundsFromSlots(players, slots);
  }

  List<List<GroupMatch>> _buildTripleEliminationRounds(
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
        _isValidKnockoutSlotOrder(slotOrder, players.length, bracketSize) &&
            _slotOrderAvoidsByePair(slotOrder)
        ? List<int?>.from(slotOrder)
        : _automaticKnockoutSlotOrder(players.length, bracketSize);
    return _buildTripleEliminationRoundsFromSlots(
      players,
      slots,
      lossLimit: lossLimit,
    );
  }

  void _advanceKnockoutWinnersInRounds(List<List<GroupMatch>> rounds) {
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

  void _setExtraGroupSelection(
    int groupNumber,
    bool selected,
    List<int> currentGroups,
  ) {
    setState(() {
      if (_selectedExtraGroups.isEmpty && currentGroups.isNotEmpty) {
        _selectedExtraGroups.addAll(currentGroups);
      }

      if (selected) {
        _selectedExtraGroups.add(groupNumber);
      } else {
        _selectedExtraGroups.remove(groupNumber);
      }
    });
  }

  void _setQualificationAutoAdjust(bool enabled) {
    final groupSizes = _calculateGroupSizes();
    final plan = _groupQualificationPlan();
    setState(() {
      _autoAdjustQualification = enabled;
      if (!enabled &&
          _fixedQualifiersByGroup.length != groupSizes.length &&
          plan != null) {
        _fixedQualifiersByGroup
          ..clear()
          ..addAll(_defaultFixedQualifiersForPlan(groupSizes, plan));
        _selectedExtraGroups
          ..clear()
          ..addAll(plan.extraGroups);
        _manualExtraRank = plan.extraRank;
      }
      if (enabled && plan != null) {
        _manualExtraCount = null;
        _bestOfQualifierCountController.text = '${plan.extraCount}';
      } else if (!enabled && plan != null) {
        _manualExtraCount = plan.extraCount;
        _bestOfQualifierCountController.text = '${plan.extraCount}';
      }
    });
  }

  void _setBestOfQualifierCount(String value) {
    final parsed = int.tryParse(value);
    setState(() {
      _manualExtraCount = parsed == null || parsed < 0 ? 0 : parsed;
    });
  }

  void _cycleQualificationPlace(int groupNumber, int place) {
    final groupSizes = _calculateGroupSizes();
    final plan = _groupQualificationPlan();
    if (groupNumber < 1 ||
        groupNumber > groupSizes.length ||
        place < 1 ||
        place > groupSizes[groupNumber - 1] ||
        plan == null) {
      return;
    }

    setState(() {
      final fixed = _currentFixedQualifiersByGroup(groupSizes, plan);
      final groupIndex = groupNumber - 1;
      final isFixed = place <= fixed[groupIndex];
      final isExtra =
          place == plan.extraRank && plan.extraGroups.contains(groupNumber);

      if (isExtra) {
        _selectedExtraGroups.remove(groupNumber);
      } else if (isFixed) {
        fixed[groupIndex] = place - 1;
        _manualExtraRank = place;
        _selectedExtraGroups.add(groupNumber);
      } else {
        fixed[groupIndex] = place;
        _selectedExtraGroups.remove(groupNumber);
      }

      _fixedQualifiersByGroup
        ..clear()
        ..addAll(fixed);
      if (_autoAdjustQualification) {
        final safeTotal = fixed.fold<int>(0, (sum, value) => sum + value);
        final currentExtraCount =
            plan.extraCount == 0 && _selectedExtraGroups.isNotEmpty
            ? 1
            : plan.extraCount.clamp(0, _selectedExtraGroups.length).toInt();
        _bestOfQualifierCountController.text = '$currentExtraCount';
        _groupQualifierCountController.text =
            '${safeTotal + currentExtraCount}';
      }
    });
  }

  Future<void> _moveGroupTieBreaker(int index, int direction) async {
    final targetIndex = index + direction;
    if (targetIndex < 0 || targetIndex >= _groupTieBreakers.length) {
      return;
    }

    setState(() {
      _groupTieBreakersTouched = true;
      final moved = _groupTieBreakers.removeAt(index);
      _groupTieBreakers.insert(targetIndex, moved);
    });
    _saveGroupTieBreakers();
    await _groupTieBreakerSaveQueue;
  }

  @override
  Widget build(BuildContext context) {
    return _buildAuthorized(context);
  }

  Widget _buildAuthorized(BuildContext context) {
    if (_showEntryChoices) {
      return Scaffold(
        appBar: AppBar(title: const Text('Turnier erstellen')),
        body: CreationEntryChoices(
          onLeague: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const LeagueMatchPage()),
          ),
          onFind: _openFormatPlanner,
          onExpert: () => setState(() => _showEntryChoices = false),
        ),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final groupSizes = _calculateGroupSizes();
    final latestGroupStage = _latestGroupStage();
    final knockoutParticipantCount = _knockoutParticipantCount();
    final knockoutBracketSize = _knockoutBracketSize();
    final knockoutByeCount = _knockoutByeCount();
    final groupQualificationPlan = _groupQualificationPlan();
    final inheritedQualificationPlan = _storedGroupQualificationPlan(
      latestGroupStage,
    );
    if (_autoAdjustQualification &&
        groupQualificationPlan != null &&
        _bestOfQualifierCountController.text !=
            '${groupQualificationPlan.extraCount}') {
      _bestOfQualifierCountController.text =
          '${groupQualificationPlan.extraCount}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Turnier erstellen')),
      body: SafeArea(
        child: AdaptiveContentList(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Turnier konfigurieren',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Lege Teilnehmer und Ablauf fest. Weitere Optionen öffnest du bei Bedarf.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openFormatPlanner,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Passende Turnierform finden'),
            ),
            const SizedBox(height: 24),
            ExpertSetupSection(
              title: '1 · Name & Teilnehmer',
              summary: '${_players.length} Teilnehmer ausgewählt',
              initiallyExpanded: true,
              children: [
                TextField(
                  key: const ValueKey('tournament-name-field'),
                  controller: _tournamentNameController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Turniername',
                    prefixIcon: Icon(Icons.emoji_events_outlined),
                  ),
                ),
                const SizedBox(height: 32),
                SwitchListTile(
                  title: const Text('Für Rangliste/n berücksichtigen'),
                  subtitle: const Text(
                    'Nur ausgewählte Ranglisten erhalten Ergebnisse dieses Turniers.',
                  ),
                  value: _countsForRanking,
                  onChanged: (value) => setState(() {
                    _rankingSetupTouched = true;
                    _countsForRanking = value;
                    if (!value) _localRankingIds.clear();
                  }),
                ),
                if (_countsForRanking)
                  FutureBuilder<List<LocalRanking>>(
                    future: _localRankings,
                    builder: (context, snapshot) {
                      final rankings = snapshot.data ?? const <LocalRanking>[];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ranglisten auswählen',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const LinearProgressIndicator(),
                              if (rankings.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text(
                                    'Lege zuerst eine Rangliste im Hauptmenü an.',
                                  ),
                                ),
                              for (final ranking in rankings)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(ranking.name),
                                  value: _localRankingIds.contains(ranking.id),
                                  onChanged: (selected) => setState(() {
                                    _rankingSetupTouched = true;
                                    if (selected == true) {
                                      _localRankingIds.add(ranking.id);
                                    } else {
                                      _localRankingIds.remove(ranking.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                Text(
                  'Spieler',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _responsiveFormRow(
                  alignTrailingEndOnNarrow: true,
                  leading: TextField(
                    controller: _playerNameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Spielername',
                      prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                    ),
                    onSubmitted: (_) => _addPlayer(),
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: _addPlayer,
                        icon: const Icon(Icons.add),
                        tooltip: 'Spieler hinzufügen',
                      ),
                      OutlinedButton.icon(
                        onPressed: _isOpeningPlayerPicker
                            ? null
                            : _selectPlayersFromDatabase,
                        icon: _isOpeningPlayerPicker
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.playlist_add_check_outlined),
                        label: const Text('Auswählen'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _responsiveFormRow(
                  leading: TextField(
                    controller: _playerCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Anzahl',
                    ),
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: _generatePlayers,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Spieler erzeugen'),
                  ),
                  breakpoint: 420,
                ),
                const SizedBox(height: 24),
                TeamParticipantList(
                  players: _players,
                  onRename: _renamePlayer,
                  onRemove: _removePlayer,
                  onMerge: _mergePlayers,
                  onSplit: _splitTeam,
                ),
                const SizedBox(height: 32),
              ],
            ),
            ExpertSetupSection(
              title: '2 · Turnierablauf',
              summary:
                  '${_stages.length} Etappen gespeichert · Gruppen, KO und Spielregeln',
              children: [
                Text(
                  'Etappen',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _responsiveFormRow(
                  alignTrailingEndOnNarrow: true,
                  leading: TextField(
                    key: const ValueKey('stage-name-field'),
                    controller: _stageNameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Etappenname',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    onChanged: (_) {
                      _stageNameWasEdited = true;
                    },
                    onSubmitted: (_) => _saveStage(),
                  ),
                  trailing: IconButton.filled(
                    onPressed: _saveStage,
                    icon: Icon(
                      _editingStageIndex == null ? Icons.add : Icons.check,
                    ),
                    tooltip: _editingStageIndex == null
                        ? 'Etappe hinzufügen'
                        : 'Etappe speichern',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: false,
                  itemHeight: null,
                  key: const ValueKey('stage-type-field'),
                  initialValue: _selectedStageType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Etappentyp',
                    prefixIcon: Icon(Icons.schema_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'groups',
                      child: Text('Gruppenphase'),
                    ),
                    DropdownMenuItem(
                      value: 'kratzer',
                      child: Text('Kratzer-Modus'),
                    ),
                    DropdownMenuItem(
                      value: 'single_knockout',
                      child: Text('K.-o.-Runde'),
                    ),
                    DropdownMenuItem(
                      value: 'double_knockout',
                      child: Text('Doppel-KO'),
                    ),
                    DropdownMenuItem(
                      value: 'triple_knockout',
                      child: Text('Triple-KO'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _selectedStageType = value;
                      _finalEndsTournament = value != 'kratzer';
                      _kratzerLives = _lossLimitForStageType(
                        value,
                      ).clamp(2, 10);
                      _setDefaultStageNameIfNeeded(value);
                    });
                  },
                ),
                const SizedBox(height: 12),
                if ((_isKnockoutStageType(_selectedStageType) &&
                        _selectedStageType != 'single_knockout') ||
                    (_selectedStageType == 'groups' &&
                        (_lossLimitForGroupPlayType(_groupPlayType) > 1 ||
                            _groupPlayTypes.any(
                              (t) => _lossLimitForGroupPlayType(t) > 1,
                            )))) ...[
                  if (_selectedStageType != 'kratzer')
                    SwitchListTile(
                      key: const ValueKey('final-ends-tournament'),
                      title: const Text('Ein großes Finale entscheidet'),
                      subtitle: const Text(
                        'Der Verlierer des großen Finales scheidet unabhängig von übrigen Leben aus.',
                      ),
                      value: _finalEndsTournament,
                      onChanged: (value) =>
                          setState(() => _finalEndsTournament = value),
                    ),
                  if (_selectedStageType == 'kratzer' ||
                      (!_finalEndsTournament && _selectedStageType != 'groups'))
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      isDense: false,
                      itemHeight: null,
                      key: ValueKey('kratzer-lives-$_kratzerLives'),
                      initialValue: _kratzerLives,
                      decoration: const InputDecoration(
                        labelText: 'Kratzer-Modus: Leben',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var lives = 2; lives <= 10; lives++)
                          DropdownMenuItem(
                            value: lives,
                            child: Text('$lives Leben'),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _kratzerLives = value ?? 3),
                    ),
                ],
                if (_selectedStageType == 'single_knockout' ||
                    (_selectedStageType == 'groups' &&
                        (_groupPlayType == 'mini_knockout' ||
                            _groupPlayTypes.contains('mini_knockout'))))
                  _placementSelection(),
                ExpertSetupSection(
                  title: 'Spielregeln anpassen',
                  summary: _stageGameFormat.label,
                  children: [
                    _StageGameFormatSetup(
                      value: _stageGameFormat,
                      onChanged: (value) =>
                          setState(() => _stageGameFormat = value),
                    ),
                  ],
                ),
                if (_selectedStageType == 'groups') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    key: const ValueKey('group-play-type-field'),
                    initialValue: _groupPlayType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Spieltyp',
                      prefixIcon: Icon(Icons.sports_score_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'swiss',
                        child: Text('Schweizer System'),
                      ),
                      DropdownMenuItem(
                        value: 'round_robin',
                        child: Text('Jeder gegen jeden'),
                      ),
                      DropdownMenuItem(
                        value: 'mini_knockout',
                        child: Text('Mini-KO in der Gruppe'),
                      ),
                      DropdownMenuItem(
                        value: 'double_knockout',
                        child: Text('Doppel-KO in der Gruppe'),
                      ),
                      DropdownMenuItem(
                        value: 'triple_knockout',
                        child: Text('Triple-KO in der Gruppe'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      _setDefaultGroupPlayType(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _responsiveFormRow(
                    leading: TextField(
                      key: const ValueKey('group-count-field'),
                      controller: _groupCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Gruppen',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    trailing: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GroupSizePreview(groupSizes: groupSizes),
                    ),
                    breakpoint: 520,
                  ),
                  const SizedBox(height: 12),
                  ExpertSetupSection(
                    title: 'Gruppenoptionen',
                    summary:
                        'Verteilung, Spieltypen, Auslosung und Wiederholungen',
                    initiallyExpanded: true,
                    children: [
                      DropdownButtonFormField<GroupPlayerAllocationMode>(
                        key: const ValueKey('group-player-allocation'),
                        isExpanded: true,
                        initialValue: _groupAllocationMode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Gruppeneinteilung',
                          prefixIcon: Icon(Icons.groups_2_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.strengthLevels,
                            child: Text('Wertungsstufen bündeln'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.balanced,
                            child: Text('Stärken gleichmäßig verteilen'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.random,
                            child: Text(
                              'Zufällig verteilen · Auslosungsrad beim Start',
                            ),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null) {
                            setState(() {
                              _groupAllocationMode = mode;
                              _groupDrawOnStart =
                                  mode == GroupPlayerAllocationMode.random;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Wertungsstufen bündeln sortiert nach Wertung und '
                        'bildet nacheinander Gruppenblöcke. Die stärksten '
                        'Wertungen starten dabei in der ersten Gruppe.',
                      ),
                      const SizedBox(height: 12),
                      GroupPlayTypeSetup(
                        groupSizes: groupSizes,
                        playTypes: _playTypesForGroupSizes(groupSizes),
                        onChanged: _setGroupPlayType,
                      ),
                      if (_playTypesForGroupSizes(groupSizes).any(
                        (type) => type == 'round_robin' || type == 'swiss',
                      )) ...[
                        const SizedBox(height: 12),
                        RoundRobinRepeatsSetup(
                          groupSizes: groupSizes,
                          playTypes: _playTypesForGroupSizes(groupSizes),
                          repeats: _roundRobinRepeatsForGroupSizes(groupSizes),
                          onChangeRepeats: _changeGroupRoundRobinRepeats,
                        ),
                        GroupGameLimitSetup(
                          groupSizes: groupSizes,
                          playTypes: _playTypesForGroupSizes(groupSizes),
                          repeats: _roundRobinRepeatsForGroupSizes(groupSizes),
                          limits: _gameLimitsForGroupSizes(groupSizes),
                          onChanged: _setGroupGameLimit,
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                  StageMatchCountPreview(
                    matchCount: _currentStageMatchCount(),
                    details: _currentStageMatchDetails(),
                  ),
                  const SizedBox(height: 12),
                  _responsiveFormRow(
                    leading: TextField(
                      key: const ValueKey('group-qualifier-count-field'),
                      controller: _groupQualifierCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Weiter',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    trailing: ExpertSetupSection(
                      title: 'Qualifikation im Detail',
                      summary:
                          'Plätze, Best-of-Vergleich und automatische Anpassung',
                      children: [
                        _GroupQualificationSetup(
                          groupSizes: groupSizes,
                          groupPlayTypes: _playTypesForGroupSizes(groupSizes),
                          qualificationPlan: groupQualificationPlan,
                          autoAdjust: _autoAdjustQualification,
                          bestOfQualifierCountController:
                              _bestOfQualifierCountController,
                          onSetExtraGroup: _setExtraGroupSelection,
                          onCyclePlace: _cycleQualificationPlace,
                          onAutoAdjustChanged: _setQualificationAutoAdjust,
                          onBestOfQualifierCountChanged:
                              _setBestOfQualifierCount,
                        ),
                      ],
                    ),
                    breakpoint: 620,
                  ),
                  const SizedBox(height: 12),
                  ExpertSetupSection(
                    title: 'Gleichstand entscheiden',
                    summary: 'Reihenfolge der Tabellenkriterien anpassen',
                    children: [
                      GroupTieBreakerSetup(
                        tieBreakers: _groupTieBreakers,
                        onMoveTieBreaker: _moveGroupTieBreaker,
                      ),
                    ],
                  ),
                ],
                if (_isKnockoutStageType(_selectedStageType)) ...[
                  const SizedBox(height: 12),
                  _InheritedKnockoutSetup(
                    placementPlaces: _placementPlaces.toList(),
                    previousStage: _previousStageForCurrentForm(),
                    qualificationPlan: inheritedQualificationPlan,
                    participantCount: knockoutParticipantCount,
                    bracketSize: knockoutBracketSize,
                    byeCount: knockoutByeCount,
                    eliminationLossLimit: _selectedLossLimit,
                    seedingMode: _effectiveKnockoutSeedingMode(),
                    slotOrder: _knockoutSlotOrder(),
                    participantLabels: _knockoutParticipantLabels(),
                    allowCrossSeed: _hasGroupSeedSources(),
                    drawOnStart:
                        _knockoutDrawOnStart &&
                        _effectiveKnockoutSeedingMode() == 'random',
                    onSeedingModeChanged: _setKnockoutSeedingMode,
                    onDrawOnStartChanged: _setKnockoutDrawOnStart,
                    onSwapSlot: _swapKnockoutSlots,
                    onResetSlots: _resetKnockoutSlots,
                  ),
                ],
                if (_isKnockoutStageType(_selectedStageType)) ...[
                  const SizedBox(height: 12),
                  StageMatchCountPreview(
                    matchCount: _currentStageMatchCount(),
                    details: _currentStageMatchDetails(),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saveStage,
                  icon: Icon(
                    _editingStageIndex == null ? Icons.add : Icons.check,
                  ),
                  label: Text(
                    _editingStageIndex == null
                        ? 'Etappe hinzufügen'
                        : 'Änderungen speichern',
                  ),
                ),
                const SizedBox(height: 16),
                _StageList(
                  stages: _stages,
                  editingStageIndex: _editingStageIndex,
                  onEditStage: _editStage,
                  onRemoveStage: _removeStage,
                ),
              ],
            ),
            ExpertSetupSection(
              title: '3 · Prüfen & anlegen',
              summary:
                  '${_players.length} Teilnehmer · ${_stages.length} Etappen · $_plannedBoardCount Boards',
              children: [
                ConfigurationDurationBar(
                  stages: [
                    if (_stages.isEmpty) _currentStageConfiguration(),
                    for (var i = 0; i < _stages.length; i++)
                      i == _editingStageIndex
                          ? _currentStageConfiguration()
                          : _stages[i],
                  ],
                  editing: _editingStageIndex != null || _stages.isEmpty,
                  boards: _plannedBoardCount,
                  onBoardsChanged: (boards) =>
                      setState(() => _plannedBoardCount = boards),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 24),
                if (_players.isEmpty || _stages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _players.isEmpty
                          ? 'Zum Anlegen fehlen die Teilnehmer. Bitte oben Spieler hinzufügen oder auswählen.'
                          : 'Zum Anlegen fehlt eine Etappe. Bitte eine Etappe hinzufügen oder einen Vorschlag übernehmen.',
                    ),
                  ),
                FilledButton.icon(
                  onPressed:
                      _players.isEmpty ||
                          _stages.isEmpty ||
                          _isCreatingTournament
                      ? null
                      : _createTournament,
                  icon: _isCreatingTournament
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _isCreatingTournament
                        ? 'Wird angelegt …'
                        : 'Turnier anlegen',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
