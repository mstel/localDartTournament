part of '../../../../tournament_workspace.dart';

enum _TournamentSaveChoice { update, create }

class TournamentCreationPage extends StatefulWidget {
  const TournamentCreationPage({
    super.key,
    this.tournamentStorage,
    this.existingTournament,
    this.skipEntryChoices = false,
  });

  final TournamentStorage? tournamentStorage;
  final CreatedTournament? existingTournament;
  final bool skipEntryChoices;

  @override
  State<TournamentCreationPage> createState() => _TournamentCreationPageState();
}

class _TournamentCreationPageState extends State<TournamentCreationPage> {
  bool _showEntryChoices = true;
  bool _countsForRanking = false;
  bool _rankingSetupTouched = false;
  bool _hasSelectedEloRanking = false;
  bool _loadingEloRatingsForSeeding = false;
  Map<String, int> _eloRatingsByPlayerId = const {};
  final List<String> _localRankingIds = [];
  final _tournamentNameController = TextEditingController();
  final _nameParticipantSectionController = ExpansibleController();
  final _structureSectionController = ExpansibleController();
  final _summarySectionController = ExpansibleController();
  final _playerNameController = TextEditingController();
  final _playerCountController = TextEditingController(text: '8');
  final _groupCountController = TextEditingController(text: '2');
  final _groupQualifierCountController = TextEditingController(text: '8');
  final _bestOfQualifierCountController = TextEditingController(text: '0');
  final _database = LocalAppDatabase();
  late final Future<List<LocalRanking>> _localRankings = _database
      .loadLocalRankings();
  final Set<int> _selectedExtraGroups = {};
  final List<TournamentPlayer> _players = [];
  int _plannedBoardCount = 4;
  ConfigurationEstimate? _configurationEstimate;
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
  final List<int> _fixedQualifiersByGroup = [];
  int? _manualExtraRank;
  int? _manualExtraCount;
  bool _autoAdjustQualification = true;
  String _qualificationAdvancementPolicy = 'larger_group';
  bool _allowGroupTieBreakDeciders = false;
  TournamentGameFormat _tieBreakGameFormat = const TournamentGameFormat(
    bestOfLegs: 1,
  );
  int? _editingStageIndex;
  GroupPlayerAllocationMode _groupAllocationMode =
      GroupPlayerAllocationMode.strengthLevels;
  List<int?>? _manualGroupSlotOrder;
  List<int?>? _manualKnockoutSlotOrder;
  final Set<int> _placementPlaces = {};
  bool _finalEndsTournament = true;
  int? _knockoutAdvancingCount;
  bool _playKnockoutFully = true;
  int _kratzerLives = 3;
  int get _selectedLossLimit => _selectedStageType == 'kratzer'
      ? _kratzerLives
      : _lossLimitForStageType(_selectedStageType);
  bool get _canEditKratzerStartingScratches {
    final existing = widget.existingTournament;
    return existing == null ||
        (existing.startedAt == null &&
            !existing.runStages.whereType<KnockoutTournamentRunStage>().any(
              (stage) =>
                  stage.isKratzer &&
                  stage.matches.any((match) => match.scratchedPlayer != null),
            ));
  }

  String _selectedStageType = 'groups';
  bool get _isGroupStageForm =>
      _selectedStageType == 'groups' || _selectedStageType == 'swiss';
  String get _selectedGroupPlayType =>
      _selectedStageType == 'swiss' ? 'swiss' : 'round_robin';
  String _knockoutSeedingMode = 'cross';
  bool get _hasTeamParticipants => _players.any((player) => player.isTeam);
  bool get _effectiveCountsForRanking =>
      _countsForRanking && !_hasTeamParticipants;
  List<String> get _effectiveRankingIds =>
      _effectiveCountsForRanking ? _localRankingIds : const [];
  bool _groupDrawOnStart = false;
  String _kratzerBoardDistribution = 'balanced';
  bool _kratzerPreferSameScratchCount = false;
  bool _kratzerPlayUntilElimination = false;
  bool _kratzerBonusLifeFor180 = false;
  bool _kratzerBonusLifeForHighFinish = false;
  bool _kratzerHandicapsEnabled = false;
  bool _isOpeningPlayerPicker = false;
  bool _isCreatingTournament = false;
  DateTime _tournamentDate = DateUtils.dateOnly(DateTime.now());
  TournamentGameFormat _stageGameFormat = const TournamentGameFormat();

  @override
  void initState() {
    super.initState();
    _showEntryChoices = !widget.skipEntryChoices;
    final existing = widget.existingTournament;
    if (existing != null) {
      _showEntryChoices = false;
      _countsForRanking = existing.countsForRanking;
      _rankingSetupTouched = true;
      _localRankingIds.addAll(existing.rankingIds);
      _tournamentNameController.text = existing.name;
      _tournamentDate = DateUtils.dateOnly(existing.effectiveDate.toLocal());
      _players.addAll(existing.players);
      _playerCountController.text = '${existing.players.length}';
      _plannedBoardCount = existing.boardCount;
      _stages.addAll(existing.stages);
      if (_stages.isNotEmpty) {
        _editStage(0);
      }
    }
    unawaited(_loadGroupTieBreakers());
    unawaited(_applyDefaultRanking());
    unawaited(_refreshEloRankingAvailability());
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
    unawaited(_refreshEloRankingAvailability());
  }

  Future<void> _configureRankingSelection(bool enabled) async {
    if (!enabled) {
      setState(() {
        _rankingSetupTouched = true;
        _countsForRanking = false;
        _hasSelectedEloRanking = false;
        _localRankingIds.clear();
      });
      return;
    }

    final rankings = await _localRankings;
    if (!mounted) return;
    final selected = Set<String>.from(_localRankingIds);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ranglistenwertung'),
          content: SizedBox(
            width: 440,
            child: rankings.isEmpty
                ? const Text('Lege zuerst eine Rangliste im Hauptmenü an.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final ranking in rankings)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(ranking.name),
                          value: selected.contains(ranking.id),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selected.add(ranking.id);
                            } else {
                              selected.remove(ranking.id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Übernehmen'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      if (_localRankingIds.isEmpty) {
        setState(() => _countsForRanking = false);
      }
      return;
    }
    setState(() {
      _rankingSetupTouched = true;
      _countsForRanking = true;
      _localRankingIds
        ..clear()
        ..addAll(result);
    });
    unawaited(_refreshEloRankingAvailability());
  }

  Future<void> _refreshEloRankingAvailability() async {
    final rankings = await _localRankings;
    if (!mounted) return;
    final available =
        _effectiveCountsForRanking &&
        rankings.any(
          (ranking) =>
              ranking.type == RankingType.elo &&
              _localRankingIds.contains(ranking.id),
        );
    if (available == _hasSelectedEloRanking) return;
    setState(() => _hasSelectedEloRanking = available);
  }

  Future<void> _loadEloRatingsForSeeding() async {
    setState(() => _loadingEloRatingsForSeeding = true);
    try {
      final ratings = await _loadGroupRatings();
      if (!mounted) return;
      setState(() => _eloRatingsByPlayerId = ratings);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ELO-Setzliste konnte nicht geladen werden: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingEloRatingsForSeeding = false);
    }
  }

  Future<void> _saveTournamentNameDraft() async {
    final name = _tournamentNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Turniername darf nicht leer sein.')),
      );
      return;
    }
    _tournamentNameController.text = name;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Der Turniername wird beim Speichern übernommen.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickTournamentName() async {
    try {
      final tournaments =
          await (widget.tournamentStorage ?? TournamentStorage())
                .loadTournaments()
            ..sort((a, b) {
              final aDate =
                  a.tournamentDate ??
                  a.startedAt ??
                  a.finishedAt ??
                  a.createdAt;
              final bDate =
                  b.tournamentDate ??
                  b.startedAt ??
                  b.finishedAt ??
                  b.createdAt;
              return bDate.compareTo(aDate);
            });
      if (!mounted) return;
      final selected = await showDialog<CreatedTournament>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Name eines anderen Turniers öffnen'),
          content: SizedBox(
            width: 480,
            height: 360,
            child: tournaments.isEmpty
                ? const Center(
                    child: Text('Keine anderen Turniere gespeichert.'),
                  )
                : ListView.separated(
                    itemCount: tournaments.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tournament = tournaments[index];
                      return ListTile(
                        title: Text(tournament.name),
                        subtitle: Text(
                          (tournament.tournamentDate ?? tournament.createdAt)
                              .toLocal()
                              .toString()
                              .split(' ')
                              .first,
                        ),
                        onTap: () => Navigator.pop(context, tournament),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      _tournamentNameController.text = selected.name;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Turniere konnten nicht geladen werden: $error'),
        ),
      );
    }
  }

  Future<void> _pickTournamentSettings() async {
    try {
      final tournaments =
          await (widget.tournamentStorage ?? TournamentStorage())
              .loadTournaments();
      final candidates =
          tournaments
              .where((tournament) => tournament.leagueMatch == null)
              .toList()
            ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
      if (!mounted) return;
      final selected = await showDialog<CreatedTournament>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Einstellungen eines anderen Turniers öffnen'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: candidates.isEmpty
                ? const Center(
                    child: Text('Keine passenden Turniere gespeichert.'),
                  )
                : ListView.separated(
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tournament = candidates[index];
                      return ListTile(
                        title: Text(tournament.name),
                        subtitle: Text(
                          '${tournament.players.length} Teilnehmer · '
                          '${tournament.stages.length} Phasen · '
                          '${tournament.boardCount} Boards',
                        ),
                        onTap: () => Navigator.pop(context, tournament),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      setState(() {
        _players
          ..clear()
          ..addAll(
            selected.players.map(
              (player) => TournamentPlayer.fromJson(player.toJson()),
            ),
          );
        _playerCountController.text = '${_players.length}';
        _plannedBoardCount = selected.boardCount;
        _stages
          ..clear()
          ..addAll(
            selected.stages.map(
              (stage) => TournamentStage.fromJson(stage.toJson()),
            ),
          );
        _editingStageIndex = null;
        _manualGroupSlotOrder = null;
        _manualKnockoutSlotOrder = null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Turniereinstellungen konnten nicht geladen werden: $error',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _tournamentNameController.dispose();
    _playerNameController.dispose();
    _playerCountController.dispose();
    _groupCountController.dispose();
    _groupQualifierCountController.dispose();
    _bestOfQualifierCountController.dispose();
    _nameParticipantSectionController.dispose();
    _structureSectionController.dispose();
    _summarySectionController.dispose();
    super.dispose();
  }

  List<int> _calculateGroupSizes() {
    if (_selectedStageType == 'swiss') {
      final participantCount = _inheritedParticipantCount() ?? _players.length;
      return participantCount > 0 ? [participantCount] : const [];
    }

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

  bool get _canConfigureManualGroups =>
      (_editingStageIndex ?? _stages.length) == 0;

  Future<void> _selectGroupAllocationMode(
    GroupPlayerAllocationMode mode,
  ) async {
    if (mode != GroupPlayerAllocationMode.manual) {
      setState(() {
        _groupAllocationMode = mode;
        _groupDrawOnStart = false;
      });
      return;
    }

    final groupSizes = _calculateGroupSizes();
    final participantCount = groupSizes.fold<int>(0, (sum, size) => sum + size);
    if (!_canConfigureManualGroups ||
        _players.isEmpty ||
        participantCount != _players.length ||
        !hasValidGroupSizes(groupSizes)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Benutzerdefinierte Gruppen können für die erste Gruppenetappe festgelegt werden. '
            'Spätere Phasen lassen sich nach dem Weiterkommen anpassen.',
          ),
        ),
      );
      return;
    }

    List<List<TournamentPlayer>> initialGroups;
    final savedOrder = _manualGroupSlotOrder;
    if (_groupAllocationMode == GroupPlayerAllocationMode.manual &&
        savedOrder != null &&
        savedOrder.length == participantCount) {
      initialGroups = GroupDrawAssignment.partitionDraw(
        items: _players,
        slotOrder: savedOrder,
        groupSizes: groupSizes,
      );
    } else {
      final previousMode =
          _groupAllocationMode == GroupPlayerAllocationMode.manual
          ? GroupPlayerAllocationMode.strengthLevels
          : _groupAllocationMode;
      final Map<String, int> ratings;
      try {
        ratings = previousMode == GroupPlayerAllocationMode.random
            ? const <String, int>{}
            : await _loadGroupRatings();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gruppen konnten nicht vorbereitet werden: $error'),
          ),
        );
        return;
      }
      if (!mounted) return;
      final arranged = const GroupPlayerAllocationEngine().allocate(
        players: _players,
        groupSizes: groupSizes,
        mode: previousMode,
        ratings: ratings,
      );
      initialGroups = GroupDrawAssignment.partition(arranged, groupSizes);
    }

    final groups = await showDialog<List<List<TournamentPlayer>>>(
      context: context,
      builder: (context) =>
          GroupPlayerAllocationDialog(initialGroups: initialGroups),
    );
    if (!mounted || groups == null) return;
    final groupOrder = groups.expand((group) => group).toList();
    final playerIndexes = groupOrder
        .map((player) => _players.indexOf(player) + 1)
        .toList();
    if (playerIndexes.length != participantCount ||
        playerIndexes.any((playerIndex) => playerIndex < 1) ||
        playerIndexes.toSet().length != participantCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Die manuelle Gruppeneinteilung ist ungültig. Bitte erneut versuchen.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _groupAllocationMode = GroupPlayerAllocationMode.manual;
      _groupDrawOnStart = false;
      _manualGroupSlotOrder = playerIndexes;
    });
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
    return List.filled(groupSizes.length, _selectedGroupPlayType);
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
    if (_selectedStageType == 'kratzer') {
      return const KratzerEngine().estimatedGameCount(
        playerCount: _knockoutParticipantCount() ?? 0,
        lives: _selectedLossLimit,
        boards: _plannedBoardCount,
        playersPerBoard: int.tryParse(_kratzerBoardDistribution),
      );
    }
    if (_isKnockoutStageType(_selectedStageType)) {
      final participantCount = _knockoutParticipantCount() ?? 0;
      final placementMatchCount = switch (_selectedLossLimit) {
        1 => _optionalPlacementMatchCount(participantCount, _placementPlaces),
        2 => PlacementEngine.buildDoubleElimination(
          _buildDoubleEliminationRounds(
            List.generate(
              participantCount,
              (index) => TournamentPlayer.generated(index + 1),
            ),
            slotOrder: _knockoutSlotOrder(),
          ),
          _placementPlaces,
        ).length,
        >= 3 => PlacementEngine.buildTripleElimination(
          _buildTripleEliminationRounds(
            List.generate(
              participantCount,
              (index) => TournamentPlayer.generated(index + 1),
            ),
            lossLimit: _selectedLossLimit,
            slotOrder: _knockoutSlotOrder(),
          ),
          _placementPlaces,
          lossLimit: _selectedLossLimit,
        ).length,
        _ => 0,
      };
      return _eliminationMatchEstimate(participantCount, _selectedLossLimit) +
          placementMatchCount;
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

  bool get _hasKratzerStage =>
      _selectedStageType == 'kratzer' ||
      _stages.any((stage) => stage.type == 'kratzer');

  List<String> _currentStageMatchDetails() {
    if (_selectedStageType == 'kratzer') {
      final participants = _knockoutParticipantCount() ?? 0;
      final boards = _plannedBoardCount;
      final playersPerBoard = int.tryParse(_kratzerBoardDistribution);
      final usedBoards = playersPerBoard == null
          ? (participants ~/ 3).clamp(0, boards)
          : participants < 3
          ? 0
          : (participants ~/ playersPerBoard).clamp(1, boards);
      return [
        '$participants aktive Teilnehmende',
        if (participants < 3) 'Für den Start sind mindestens 3 nötig',
        '$usedBoards von $boards Boards pro Runde',
        playersPerBoard == null
            ? '3–6 Teilnehmer je Board, gleichmäßig verteilt'
            : '$playersPerBoard Teilnehmer je Board',
        '${const KratzerEngine().estimatedGameCount(playerCount: participants, lives: _selectedLossLimit, boards: boards, playersPerBoard: playersPerBoard)} Partien bis zur letzten Person (Verlaufsschätzung)',
      ];
    }
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
            ? '${groupLabel(index + 1)} ${repeats[index]} Runden · ${(groupSizes[index] ~/ 2) * repeats[index]} Begegnungen'
            : playTypes[index] == 'round_robin'
            ? '${groupLabel(index + 1)} ${_roundRobinMatchCount(groupSizes[index], repeats[index], maxGamesPerPlayer: _gameLimitsForGroupSizes(groupSizes)[index])} Begegnungen${_gameLimitsForGroupSizes(groupSizes)[index] == null ? '' : ' · maximal ${_gameLimitsForGroupSizes(groupSizes)[index]} pro Teilnehmer'}'
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
      return _seedOrderForSize(
        bracketSize,
      ).map((seed) => seed <= participantCount ? seed : null).toList();
    }
    if (_effectiveKnockoutSeedingMode() == 'random_cross') {
      return _randomCrossSeededKnockoutSlotOrder(participantCount, bracketSize);
    }
    if (_effectiveKnockoutSeedingMode() == 'elo') {
      final rankedPlayers =
          List<int>.generate(participantCount, (index) => index + 1)
            ..sort((a, b) {
              final aId = _players[a - 1].profileId;
              final bId = _players[b - 1].profileId;
              final rating = (_eloRatingsByPlayerId[bId] ?? 1000).compareTo(
                _eloRatingsByPlayerId[aId] ?? 1000,
              );
              return rating != 0 ? rating : a.compareTo(b);
            });
      final rankBySeed = <int, int>{
        for (var rank = 0; rank < rankedPlayers.length; rank++)
          rank + 1: rankedPlayers[rank],
      };
      return [
        for (final bracketSeed in _seedOrderForSize(bracketSize))
          bracketSeed <= participantCount ? rankBySeed[bracketSeed] : null,
      ];
    }

    return _crossSeededKnockoutSlotOrder(participantCount, bracketSize);
  }

  List<int?> _randomCrossSeededKnockoutSlotOrder(
    int participantCount,
    int bracketSize,
  ) {
    if (bracketSize > participantCount) {
      return _crossSeededKnockoutSlotOrder(participantCount, bracketSize);
    }
    final ranked = _knockoutSeedSources(participantCount)
      ..sort(_compareKnockoutSeedStrength);
    final half = (participantCount / 2).ceil();
    final stronger = ranked.take(half).toList()..shuffle(Random());
    final weaker = ranked.skip(half).toList()..shuffle(Random());
    final pairs = <List<_KnockoutSeedSource>>[];
    while (stronger.isNotEmpty && weaker.isNotEmpty) {
      final first = stronger.removeAt(0);
      var opponentIndex = weaker.indexWhere(
        (candidate) => !_sameKnownGroup(first, candidate),
      );
      if (opponentIndex < 0) opponentIndex = 0;
      pairs.add([first, weaker.removeAt(opponentIndex)]);
    }
    final remaining = [...stronger, ...weaker]..shuffle(Random());
    for (var index = 0; index + 1 < remaining.length; index += 2) {
      pairs.add([remaining[index], remaining[index + 1]]);
    }
    if (remaining.length.isOdd) pairs.add([remaining.last]);
    return [
      for (final pair in pairs) ...pair.map((source) => source.seed),
      ...List<int?>.filled(bracketSize - participantCount, null),
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
        !previousStage.isGroupStage ||
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

    final automaticOrder = _automaticKnockoutSlotOrder(
      participantCount,
      bracketSize,
    );
    return automaticOrder;
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
        !previousStage.isGroupStage ||
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
      if (_effectiveKnockoutSeedingMode() == 'random_cross') {
        final participantCount = _knockoutParticipantCount();
        final bracketSize = _knockoutBracketSize();
        _manualKnockoutSlotOrder =
            participantCount == null || bracketSize == null
            ? null
            : _randomCrossSeededKnockoutSlotOrder(
                participantCount,
                bracketSize,
              );
      } else {
        _manualKnockoutSlotOrder = null;
      }
    });
  }

  void _setKnockoutSeedingMode(String mode) {
    setState(() {
      _knockoutSeedingMode = mode;
      final participantCount = _knockoutParticipantCount();
      final bracketSize = _knockoutBracketSize();
      _manualKnockoutSlotOrder =
          mode == 'random_cross' &&
              participantCount != null &&
              bracketSize != null
          ? _randomCrossSeededKnockoutSlotOrder(participantCount, bracketSize)
          : null;
    });
    if (mode == 'elo') unawaited(_loadEloRatingsForSeeding());
  }

  bool _hasGroupSeedSources() {
    final previousStage = _previousStageForCurrentForm();
    return previousStage != null &&
        previousStage.isGroupStage &&
        previousStage.groupSizes.isNotEmpty;
  }

  String _effectiveKnockoutSeedingMode() {
    return _knockoutSeedingMode == 'elo' && !_hasSelectedEloRanking
        ? 'cross'
        : _knockoutSeedingMode;
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
      if (stage.isGroupStage && stage.groupSizes.isNotEmpty) {
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
      'swiss' => 'Schweizer System',
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
    var sameTypeCount = 0;
    for (var index = 0; index < _stages.length; index++) {
      final stage = _stages[index];
      final stageType = stage.isGroupStage && stage.groupPlayType == 'swiss'
          ? 'swiss'
          : stage.type;
      if (index != _editingStageIndex && stageType == type) {
        sameTypeCount++;
      }
    }
    return '$baseName ${sameTypeCount + 1}';
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
    final hasManualFixed = _fixedQualifiersByGroup.length == groupSizes.length;
    var fixedByGroup = hasManualFixed
        ? _currentFixedQualifiersByGroup(groupSizes, null)
        : [
            for (final groupSize in groupSizes)
              fixedPerGroup > groupSize ? groupSize : fixedPerGroup,
          ];
    final extraRank = hasManualFixed
        ? (_manualExtraRank ?? fixedPerGroup + 1)
        : fixedPerGroup + 1;
    var remainingExtraCount =
        cappedParticipantCount -
        fixedByGroup.fold<int>(0, (sum, value) => sum + value);
    if (_autoAdjustQualification &&
        _qualificationAdvancementPolicy == 'larger_group' &&
        !hasManualFixed &&
        remainingExtraCount > 0) {
      final orderedGroupIndexes = List<int>.generate(groupCount, (i) => i)
        ..sort((a, b) => groupSizes[b].compareTo(groupSizes[a]));
      for (
        var index = 0;
        index < orderedGroupIndexes.length && remainingExtraCount > 0;
        index++
      ) {
        final groupIndex = orderedGroupIndexes[index];
        final nextSize = index + 1 < orderedGroupIndexes.length
            ? groupSizes[orderedGroupIndexes[index + 1]]
            : -1;
        if (groupSizes[groupIndex] <= nextSize ||
            groupSizes[groupIndex] < fixedByGroup[groupIndex] + 1) {
          continue;
        }
        fixedByGroup = List<int>.from(fixedByGroup)
          ..[groupIndex] = fixedByGroup[groupIndex] + 1;
        remainingExtraCount--;
      }
    }
    final extraCount = !_autoAdjustQualification && hasManualFixed
        ? (_manualExtraCount ?? 0).clamp(0, groupCount).toInt()
        : remainingExtraCount.clamp(0, groupCount).toInt();
    final eligibleGroups = [
      for (var index = 0; index < groupSizes.length; index++)
        if (groupSizes[index] >= extraRank && fixedByGroup[index] < extraRank)
          index + 1,
    ];
    final eligibleGroupSize = eligibleGroups.isEmpty
        ? null
        : eligibleGroups
              .map((groupNumber) => groupSizes[groupNumber - 1])
              .reduce(max);
    final manualExtraGroups =
        _selectedExtraGroups
            .where((groupNumber) => eligibleGroups.contains(groupNumber))
            .toList()
          ..sort();
    final extraGroups =
        manualExtraGroups.isNotEmpty || !_autoAdjustQualification
        ? manualExtraGroups
        : eligibleGroups;

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
    var storedFixedByGroup = stage.fixedQualifiersByGroup.length == groupCount
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
    if (stage.qualificationAutoAdjust) {
      storedFixedByGroup = [
        for (final groupSize in stage.groupSizes)
          fixedPerGroup > groupSize ? groupSize : fixedPerGroup,
      ];
      var remaining =
          cappedParticipantCount -
          storedFixedByGroup.fold<int>(0, (sum, value) => sum + value);
      if (stage.qualificationAdvancementPolicy == 'larger_group') {
        final ordered = List<int>.generate(groupCount, (index) => index)
          ..sort((a, b) => stage.groupSizes[b].compareTo(stage.groupSizes[a]));
        for (var index = 0; index < ordered.length && remaining > 0; index++) {
          final groupIndex = ordered[index];
          final nextSize = index + 1 < ordered.length
              ? stage.groupSizes[ordered[index + 1]]
              : -1;
          if (stage.groupSizes[groupIndex] <= nextSize ||
              stage.groupSizes[groupIndex] <= storedFixedByGroup[groupIndex]) {
            continue;
          }
          storedFixedByGroup[groupIndex]++;
          remaining--;
        }
      }
    }
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
    final eligibleGroups = [
      for (var index = 0; index < groupCount; index++)
        if (stage.groupSizes[index] >= extraRank &&
            storedFixedByGroup[index] < extraRank)
          index + 1,
    ];
    final eligibleGroupSize = eligibleGroups.isEmpty
        ? null
        : eligibleGroups
              .map((groupNumber) => stage.groupSizes[groupNumber - 1])
              .reduce(max);

    return QualificationPlan(
      totalQualifiers: cappedParticipantCount,
      fixedPerGroup: fixedPerGroup,
      extraCount: extraCount,
      extraRank: extraRank,
      eligibleGroupSize: eligibleGroupSize,
      extraGroups: stage.qualificationAutoAdjust
          ? eligibleGroups
          : stage.qualifiersByGroup,
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
            'Teilnehmer konnten nicht aus der Datenbank geladen werden.',
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

  void _reorderPlayer(int oldIndex, int newIndex) {
    setState(() {
      final player = _players.removeAt(oldIndex);
      _players.insert(newIndex, player);
    });
  }

  void _setKratzerStartingScratches(int index, int scratches) {
    setState(() {
      _players[index] = _players[index].copyWith(
        kratzerStartingScratches: scratches,
      );
    });
  }

  void _setKratzerLives(int lives) {
    setState(() {
      _kratzerLives = lives;
      for (var index = 0; index < _players.length; index++) {
        if (_players[index].kratzerStartingScratches > lives) {
          _players[index] = _players[index].copyWith(
            kratzerStartingScratches: lives,
          );
        }
      }
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
          'Mehrere Plätze auswählbar. Nötige Vorrunden werden automatisch ergänzt.',
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
    final otherStages = [
      for (var index = 0; index < _stages.length; index++)
        if (index != _editingStageIndex) _stages[index],
    ];
    if ((_selectedStageType == 'kratzer' && otherStages.isNotEmpty) ||
        (otherStages.any((stage) => stage.type == 'kratzer') &&
            _editingStageIndex == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Der Kratzer-Modus muss die einzige Phase des Turniers sein.',
          ),
        ),
      );
      return;
    }
    if (_selectedStageType == 'kratzer' &&
        (_knockoutParticipantCount() ?? 0) < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Für Kratzer werden mindestens drei Teilnehmende benötigt.',
          ),
        ),
      );
      return;
    }
    if (_selectedStageType == 'groups' &&
        !hasValidGroupSizes(_calculateGroupSizes())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Jede Gruppe benötigt mindestens 3 Teilnehmer. Bitte weniger Gruppen wählen oder Teilnehmer ergänzen.',
          ),
        ),
      );
      return;
    }
    if (_selectedStageType == 'swiss' &&
        (_calculateGroupSizes().firstOrNull ?? 0) < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Für ein Schweizer System werden zwei Teilnehmer benötigt.',
          ),
        ),
      );
      return;
    }
    final groupSizes = _calculateGroupSizes();
    final participantCount = groupSizes.fold<int>(0, (sum, size) => sum + size);
    final manualOrder = _manualGroupSlotOrder;
    if (_selectedStageType == 'groups' &&
        _groupAllocationMode == GroupPlayerAllocationMode.manual &&
        (manualOrder == null ||
            manualOrder.length != participantCount ||
            manualOrder.any(
              (playerIndex) =>
                  playerIndex == null ||
                  playerIndex < 1 ||
                  playerIndex > participantCount,
            ) ||
            manualOrder.toSet().length != participantCount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte die benutzerdefinierten Gruppen erneut einteilen, '
            'damit alle aktuellen Teilnehmer genau einmal zugeordnet sind.',
          ),
        ),
      );
      return;
    }
    if (_stageGameFormat.bestOfLegs.isEven &&
        (_stageGameFormat.bestOfSets > 1 || !_isGroupStageForm)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gerade Leg-Längen sind nur für Jeder-gegen-jeden oder Swiss ohne Sets möglich.',
          ),
        ),
      );
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
    final groupQualificationPlan = _isGroupStageForm
        ? _groupQualificationPlan()
        : null;
    final inheritedQualificationPlan = _isKnockoutStageType(_selectedStageType)
        ? _storedGroupQualificationPlan(latestGroupStage)
        : null;
    return TournamentStage(
      name: _defaultStageName(),
      type: _selectedStageType,
      placementPlaces:
          (_selectedStageType == 'single_knockout' ||
              _selectedStageType == 'double_knockout' ||
              _selectedStageType == 'triple_knockout' ||
              _selectedStageType == 'groups')
          ? (_placementPlaces.toList()..sort())
          : const [],
      finalEndsTournament:
          _selectedStageType != 'kratzer' && _finalEndsTournament,
      knockoutLives: _isKnockoutStageType(_selectedStageType)
          ? _selectedLossLimit
          : null,
      kratzerPlayersPerBoard: _selectedStageType == 'kratzer'
          ? int.tryParse(_kratzerBoardDistribution)
          : null,
      kratzerPreferSameScratchCount: _selectedStageType == 'kratzer'
          ? _kratzerPreferSameScratchCount
          : false,
      kratzerPlayUntilElimination: _selectedStageType == 'kratzer'
          ? _kratzerPlayUntilElimination
          : false,
      kratzerBonusLifeFor180: _selectedStageType == 'kratzer'
          ? _kratzerBonusLifeFor180
          : false,
      kratzerBonusLifeForHighFinish: _selectedStageType == 'kratzer'
          ? _kratzerBonusLifeForHighFinish
          : false,
      kratzerHandicapsEnabled: _selectedStageType == 'kratzer'
          ? _kratzerHandicapsEnabled
          : false,
      groupCount: _isGroupStageForm ? _calculateGroupSizes().length : null,
      groupSizes: _isGroupStageForm ? _calculateGroupSizes() : const [],
      groupPlayType: _isGroupStageForm ? _selectedGroupPlayType : 'round_robin',
      groupPlayTypes: _isGroupStageForm
          ? _playTypesForGroupSizes(_calculateGroupSizes())
          : const [],
      groupRoundRobinRepeats: _isGroupStageForm
          ? _roundRobinRepeatsForGroupSizes(_calculateGroupSizes())
          : const [],
      groupTieBreakers: _isGroupStageForm
          ? List.unmodifiable(_groupTieBreakers)
          : defaultGroupTieBreakers,
      allowGroupTieBreakDeciders:
          _isGroupStageForm && _allowGroupTieBreakDeciders,
      tieBreakGameFormat: _tieBreakGameFormat,
      groupMaxGamesPerPlayer: _isGroupStageForm
          ? _gameLimitsForGroupSizes(_calculateGroupSizes())
          : const [],
      groupDrawOnStart: _selectedStageType == 'groups'
          ? _groupDrawOnStart
          : false,
      groupSlotOrder:
          _selectedStageType == 'groups' &&
              _groupAllocationMode == GroupPlayerAllocationMode.manual
          ? List<int?>.unmodifiable(_manualGroupSlotOrder ?? const [])
          : const [],
      knockoutParticipantCount: _isKnockoutStageType(_selectedStageType)
          ? _knockoutParticipantCount()
          : null,
      knockoutAdvancingCount:
          _isKnockoutStageType(_selectedStageType) &&
              _selectedStageType != 'kratzer' &&
              !_playKnockoutFully
          ? _knockoutAdvancingCount
          : null,
      knockoutBracketSize: _isKnockoutStageType(_selectedStageType)
          ? _knockoutBracketSize()
          : null,
      knockoutByeCount: _isKnockoutStageType(_selectedStageType)
          ? _knockoutByeCount()
          : 0,
      knockoutSlotOrder: _isKnockoutStageType(_selectedStageType)
          ? _effectiveKnockoutSeedingMode() == 'random'
                ? const []
                : _knockoutSlotOrder()
          : const [],
      knockoutSeedingMode: _isKnockoutStageType(_selectedStageType)
          ? _effectiveKnockoutSeedingMode()
          : 'cross',
      knockoutDrawOnStart:
          _isKnockoutStageType(_selectedStageType) &&
          _effectiveKnockoutSeedingMode() == 'random',
      qualifiersByGroup: _isGroupStageForm
          ? groupQualificationPlan?.extraGroups ?? const []
          : const [],
      fixedQualifiersByGroup: _isGroupStageForm
          ? groupQualificationPlan?.fixedByGroup ?? const []
          : const [],
      extraQualifierRank: _isGroupStageForm
          ? groupQualificationPlan?.extraRank
          : null,
      extraQualifierCount: _isGroupStageForm
          ? groupQualificationPlan?.extraCount
          : null,
      qualificationAutoAdjust: _isGroupStageForm
          ? _autoAdjustQualification
          : true,
      qualificationAdvancementPolicy: _isGroupStageForm
          ? _qualificationAdvancementPolicy
          : 'larger_group',
      qualifiedParticipantCount: _isGroupStageForm
          ? groupQualificationPlan?.totalQualifiers
          : null,
      qualificationSummary: _isGroupStageForm
          ? groupQualificationPlan?.summary
          : inheritedQualificationPlan?.summary,
      gameFormat: _stageGameFormat,
    );
  }

  void _resetStageForm() {
    _editingStageIndex = null;
    _selectedStageType = 'groups';
    _placementPlaces.clear();
    _finalEndsTournament = true;
    _knockoutAdvancingCount = null;
    _playKnockoutFully = true;
    _kratzerLives = 3;
    _kratzerBoardDistribution = 'balanced';
    _kratzerPreferSameScratchCount = false;
    _kratzerPlayUntilElimination = false;
    _kratzerBonusLifeFor180 = false;
    _kratzerBonusLifeForHighFinish = false;
    _kratzerHandicapsEnabled = false;
    _groupRoundRobinRepeats.clear();
    _groupMaxGamesPerPlayer.clear();
    _fixedQualifiersByGroup.clear();
    _manualExtraRank = null;
    _manualExtraCount = null;
    _bestOfQualifierCountController.text = '0';
    _autoAdjustQualification = true;
    _qualificationAdvancementPolicy = 'larger_group';
    _allowGroupTieBreakDeciders = false;
    _tieBreakGameFormat = const TournamentGameFormat(bestOfLegs: 1);
    _selectedExtraGroups.clear();
    _groupTieBreakers
      ..clear()
      ..addAll(defaultGroupTieBreakers);
    _manualKnockoutSlotOrder = null;
    _knockoutSeedingMode = 'cross';
    _groupDrawOnStart = false;
    _manualGroupSlotOrder = null;
    if (_groupAllocationMode == GroupPlayerAllocationMode.manual) {
      _groupAllocationMode = GroupPlayerAllocationMode.strengthLevels;
    }
    _kratzerBoardDistribution = 'balanced';
    _stageGameFormat = const TournamentGameFormat();
  }

  void _editStage(int index) {
    final stage = _stages[index];
    setState(() {
      _editingStageIndex = index;
      _selectedStageType = stage.isGroupStage && stage.groupPlayType == 'swiss'
          ? 'swiss'
          : stage.type;
      _placementPlaces
        ..clear()
        ..addAll(stage.placementPlaces);
      _finalEndsTournament = stage.finalEndsTournament;
      _knockoutAdvancingCount = stage.knockoutAdvancingCount;
      _playKnockoutFully = stage.knockoutAdvancingCount == null;
      _kratzerLives = stage.lossLimit;
      _kratzerBoardDistribution =
          stage.kratzerPlayersPerBoard?.toString() ?? 'balanced';
      _kratzerPreferSameScratchCount = stage.kratzerPreferSameScratchCount;
      _kratzerPlayUntilElimination = stage.kratzerPlayUntilElimination;
      _kratzerBonusLifeFor180 = stage.kratzerBonusLifeFor180;
      _kratzerBonusLifeForHighFinish = stage.kratzerBonusLifeForHighFinish;
      _kratzerHandicapsEnabled = stage.kratzerHandicapsEnabled;
      _stageGameFormat = stage.gameFormat;
      _allowGroupTieBreakDeciders = stage.allowGroupTieBreakDeciders;
      _tieBreakGameFormat = stage.tieBreakGameFormat;

      if (stage.isGroupStage) {
        _groupCountController.text = '${stage.groupSizes.length}';
        _groupQualifierCountController.text =
            '${stage.qualifiedParticipantCount ?? stage.groupSizes.fold<int>(0, (sum, size) => sum + size)}';
        _selectedExtraGroups
          ..clear()
          ..addAll(stage.qualifiersByGroup);
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
          ..addAll(
            stage.qualificationAutoAdjust
                ? const <int>[]
                : stage.fixedQualifiersByGroup,
          );
        _manualExtraRank = stage.extraQualifierRank;
        _manualExtraCount = stage.extraQualifierCount;
        _bestOfQualifierCountController.text =
            '${stage.extraQualifierCount ?? 0}';
        _autoAdjustQualification = stage.qualificationAutoAdjust;
        _qualificationAdvancementPolicy = stage.qualificationAdvancementPolicy;
        _groupDrawOnStart = false;
        if (stage.groupDrawOnStart) {
          _groupAllocationMode = GroupPlayerAllocationMode.random;
          _manualGroupSlotOrder = null;
        } else if (stage.groupSlotOrder.isNotEmpty) {
          _groupAllocationMode = GroupPlayerAllocationMode.manual;
          _manualGroupSlotOrder = List<int?>.from(stage.groupSlotOrder);
        } else {
          _groupAllocationMode = GroupPlayerAllocationMode.strengthLevels;
          _manualGroupSlotOrder = null;
        }
      } else {
        _selectedExtraGroups.clear();
        _groupRoundRobinRepeats.clear();
        _groupMaxGamesPerPlayer.clear();
        _fixedQualifiersByGroup.clear();
        _manualExtraRank = null;
        _manualExtraCount = null;
        _bestOfQualifierCountController.text = '0';
        _autoAdjustQualification = true;
        _qualificationAdvancementPolicy = 'larger_group';
        _allowGroupTieBreakDeciders = false;
        _tieBreakGameFormat = const TournamentGameFormat(bestOfLegs: 1);
        _groupTieBreakers
          ..clear()
          ..addAll(defaultGroupTieBreakers);
        _groupDrawOnStart = false;
        _manualGroupSlotOrder = null;
      }

      if (_isKnockoutStageType(stage.type)) {
        _knockoutSeedingMode = stage.knockoutSeedingMode;
        _manualKnockoutSlotOrder = stage.knockoutSlotOrder.isEmpty
            ? null
            : List<int?>.from(stage.knockoutSlotOrder);
      } else {
        _knockoutSeedingMode = 'cross';
        _manualKnockoutSlotOrder = null;
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
    await _refreshEloRankingAvailability();
    if (!mounted) return;
    final suggestion = await showDialog<TournamentFormatSuggestion>(
      context: context,
      builder: (_) => TournamentFormatPlannerDialog(
        initialAllowEloSeeding: _hasSelectedEloRanking,
      ),
    );
    if (suggestion == null || !mounted) return;
    if (suggestion.configurations.isNotEmpty) {
      if (_players.isNotEmpty &&
          _players.length != suggestion.participantCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Die Teilnehmerzahl im Finder muss zu den ausgewählten Teilnehmern passen.',
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
            'Vorschlag übernommen. Teilnehmer, Phasen und Spielformate bleiben bearbeitbar.',
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
            'Der Vorschlag passt nicht zur aktuellen Teilnehmerzahl: mindestens 3 Teilnehmer je Gruppe erforderlich.',
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
                  placementPlaces: suggestion.knockoutPlacementPlaces,
                  knockoutSeedingMode: suggestion.knockoutSeedingMode,
                  knockoutDrawOnStart:
                      suggestion.knockoutSeedingMode == 'random',
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
            placementPlaces: suggestion.knockoutPlacementPlaces,
            knockoutSeedingMode: suggestion.knockoutSeedingMode,
            knockoutDrawOnStart: suggestion.knockoutSeedingMode == 'random',
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
              ? 'Vorschlag übernommen. Bitte zuerst die Teilnehmer auswählen.'
              : 'Vorschlag übernommen. Du kannst Teilnehmer, Phasen und Spielformate weiter anpassen.',
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
      (stage) => stage.isGroupStage && !hasValidGroupSizes(stage.groupSizes),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Jede Gruppe benötigt mindestens 3 Teilnehmer. Bitte die Phasen anpassen.',
          ),
        ),
      );
      return;
    }
    if (_stages.isEmpty ||
        _players.isEmpty ||
        (_stages.any((stage) => stage.type == 'kratzer') &&
            _stages.length != 1)) {
      if (_stages.any((stage) => stage.type == 'kratzer') &&
          _stages.length != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Der Kratzer-Modus muss die einzige Phase des Turniers sein.',
            ),
          ),
        );
      }
      return;
    }
    final kratzerStages = _stages.where((stage) => stage.type == 'kratzer');
    if (kratzerStages.isNotEmpty) {
      final stage = kratzerStages.single;
      final participantCount =
          (stage.knockoutParticipantCount ?? _players.length)
              .clamp(0, _players.length)
              .toInt();
      final activeParticipantCount = _players
          .take(participantCount)
          .where((player) => player.kratzerStartingScratches < stage.lossLimit)
          .length;
      if (activeParticipantCount < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mindestens zwei Teilnehmende benötigen noch Leben, damit das Kratzer-Turnier starten kann.',
            ),
          ),
        );
        return;
      }
    }
    if (_countsForRanking &&
        _localRankingIds.isNotEmpty &&
        _players.every((player) => player.profileId == null)) {
      setState(() {
        _countsForRanking = false;
        _localRankingIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ohne lokale Teilnehmerprofile wird das Turnier als normales Turnier angelegt.',
          ),
        ),
      );
    }

    setState(() => _isCreatingTournament = true);
    try {
      final controller = TournamentCreationController(
        storage: widget.tournamentStorage,
      );
      final name = _tournamentNameController.text.trim().isEmpty
          ? 'Neues Turnier'
          : _tournamentNameController.text.trim();
      final existing = widget.existingTournament;
      final stages = List<TournamentStage>.unmodifiable(
        _preserveExistingGroupAssignment(existing, _stages),
      );
      final groupRatings =
          _groupAllocationMode == GroupPlayerAllocationMode.random
          ? const <String, int>{}
          : await _loadGroupRatings();
      final settingsChanged =
          existing != null &&
          (jsonEncode(
                    existing.players.map((player) => player.toJson()).toList(),
                  ) !=
                  jsonEncode(
                    _players.map((player) => player.toJson()).toList(),
                  ) ||
              jsonEncode(
                    existing.stages.map((stage) => stage.toJson()).toList(),
                  ) !=
                  jsonEncode(stages.map((stage) => stage.toJson()).toList()));
      final runStages =
          existing != null && !settingsChanged && existing.runStages.isNotEmpty
          ? existing.runStages
          : _buildRunStages(stages: stages, ratings: groupRatings);

      final choice = existing == null
          ? _TournamentSaveChoice.create
          : await _chooseTournamentSaveAction(
              canUpdate: !controller.hasRecordedResults(existing),
            );
      if (choice == null || !mounted) {
        setState(() => _isCreatingTournament = false);
        return;
      }

      final copyRunStages =
          existing != null && controller.hasRecordedResults(existing)
          ? _buildRunStages(stages: stages, ratings: groupRatings)
          : runStages;
      final CreatedTournament tournament;
      if (existing != null && choice == _TournamentSaveChoice.update) {
        tournament = await controller.updateTournament(
          existing,
          boardCount: _plannedBoardCount,
          countsForRanking: _effectiveCountsForRanking,
          rankingIds: _effectiveRankingIds,
          name: name,
          players: _players,
          stages: stages,
          runStages: runStages,
          settingsChanged: settingsChanged,
          tournamentDate: _tournamentDate,
          plannedMinimumMinutes: _configurationEstimate?.minimumMinutes,
          plannedMinutes: _configurationEstimate?.minutes,
          plannedMatches: _configurationEstimate?.totalMatches,
        );
      } else if (existing != null) {
        tournament = await controller.createTournamentCopy(
          boardCount: _plannedBoardCount,
          countsForRanking: _effectiveCountsForRanking,
          rankingIds: _effectiveRankingIds,
          name: name,
          players: _players,
          stages: stages,
          runStages: copyRunStages,
          tournamentDate: _tournamentDate,
          plannedMinimumMinutes: _configurationEstimate?.minimumMinutes,
          plannedMinutes: _configurationEstimate?.minutes,
          plannedMatches: _configurationEstimate?.totalMatches,
        );
      } else {
        tournament = await controller.createTournament(
          boardCount: _plannedBoardCount,
          countsForRanking: _effectiveCountsForRanking,
          rankingIds: _effectiveRankingIds,
          name: name,
          players: _players,
          stages: stages,
          runStages: runStages,
          tournamentDate: _tournamentDate,
          plannedMinimumMinutes: _configurationEstimate?.minimumMinutes,
          plannedMinutes: _configurationEstimate?.minutes,
          plannedMatches: _configurationEstimate?.totalMatches,
        );
      }
      if (!mounted) return;
      setState(() => _isCreatingTournament = false);
      if (existing != null) {
        Navigator.of(context).pop(tournament);
        return;
      }
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => TournamentRunPage(tournament: tournament),
        ),
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
  }

  Future<_TournamentSaveChoice?> _chooseTournamentSaveAction({
    required bool canUpdate,
  }) => showDialog<_TournamentSaveChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Turnier speichern'),
      content: Text(
        canUpdate
            ? 'Soll die bestehende Konfiguration ersetzt oder ein neues Turnier mit diesen Einstellungen angelegt werden? Gruppen müssen nach dem Aktualisieren gegebenenfalls neu zugewiesen werden.'
            : 'Das bestehende Turnier enthält Ergebnisse und kann deshalb nicht überschrieben werden. Du kannst die Einstellungen als neues Turnier speichern.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        if (canUpdate)
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(context, _TournamentSaveChoice.update),
            child: const Text('Bestehendes Turnier aktualisieren'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _TournamentSaveChoice.create),
          child: const Text('Als neues Turnier anlegen'),
        ),
      ],
    ),
  );

  Future<Map<String, int>> _loadGroupRatings() async {
    if (!_effectiveCountsForRanking ||
        _localRankingIds.isEmpty ||
        _players.every((player) => player.profileId == null)) {
      return const {};
    }
    final rankings = (await _localRankings)
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              _localRankingIds.contains(ranking.id),
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

  List<TournamentStage> _preserveExistingGroupAssignment(
    CreatedTournament? existing,
    List<TournamentStage> stages,
  ) {
    if (existing == null ||
        stages.isEmpty ||
        !stages.first.isGroupStage ||
        existing.runStages.isEmpty ||
        existing.runStages.first is! GroupTournamentRunStage) {
      return stages;
    }
    final oldStage = existing.runStages.first as GroupTournamentRunStage;
    final ordered = oldStage.groups.expand((group) => group.players).toList();
    String identity(TournamentPlayer player) =>
        player.profileId ?? player.name.trim().toLowerCase();
    final currentByIdentity = {
      for (final player in _players) identity(player): player,
    };
    final preserved = <TournamentPlayer>[];
    final seen = <String>{};
    for (final player in ordered) {
      final key = identity(player);
      final current = currentByIdentity[key];
      if (current != null && seen.add(key)) preserved.add(current);
    }
    final slotsNeeded = stages.first.groupSizes.fold<int>(
      0,
      (sum, size) => sum + size,
    );
    for (final player in _players) {
      if (preserved.length >= slotsNeeded) break;
      if (seen.add(identity(player))) preserved.add(player);
    }
    if (preserved.length != slotsNeeded) return stages;
    final slotOrder = preserved
        .map((player) => _players.indexOf(player) + 1)
        .toList();
    if (slotOrder.any((slot) => slot < 1) ||
        slotOrder.toSet().length != slotOrder.length) {
      return stages;
    }
    final firstStage = stages.first.copyWith(
      groupDrawOnStart: false,
      groupSlotOrder: List.unmodifiable(slotOrder),
    );
    return [firstStage, ...stages.skip(1)];
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
      if (stage.isGroupStage) {
        final groupParticipantCount = stage.groupSizes.fold<int>(
          0,
          (sum, size) => sum + size,
        );
        final groupPlayers = stage.groupSlotOrder.isNotEmpty
            ? GroupDrawAssignment.orderPlayers(
                players: incomingPlayers,
                slotOrder: stage.groupSlotOrder,
                participantCount: groupParticipantCount,
              )
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
            allowTieBreakDeciders: stage.allowGroupTieBreakDeciders,
            tieBreakGameFormat: stage.tieBreakGameFormat,
          ),
        );
        incomingPlayers = incomingPlayers
            .take(stage.qualifiedParticipantCount ?? incomingPlayers.length)
            .toList();
      } else if (stage.type == 'kratzer') {
        final participantCount =
            stage.knockoutParticipantCount ?? incomingPlayers.length;
        final participants = incomingPlayers.take(participantCount).toList();
        final activeParticipants = participants
            .where(
              (player) => player.kratzerStartingScratches < stage.lossLimit,
            )
            .toList();
        final eliminatedParticipants = participants
            .where(
              (player) => player.kratzerStartingScratches >= stage.lossLimit,
            )
            .toList();
        final assignments = const KratzerEngine().assignRound(
          players: activeParticipants,
          eliminatedFillers: eliminatedParticipants,
          availableBoards: [
            for (var board = 1; board <= _plannedBoardCount; board++) board,
          ],
          round: 1,
          playersPerBoard: stage.kratzerPlayersPerBoard,
        );
        runStages.add(
          KnockoutTournamentRunStage(
            name: stage.name,
            rounds: [
              [
                for (final assignment in assignments)
                  GroupMatch(
                    players: assignment.players,
                    scratchEligiblePlayers: assignment.scratchEligiblePlayers,
                    isKratzer: true,
                    round: 1,
                    boardNumber: assignment.boardNumber,
                  ),
              ],
            ],
            eliminationLossLimit: stage.lossLimit,
            finalEndsTournament: false,
            isKratzer: true,
            kratzerPlayersPerBoard: stage.kratzerPlayersPerBoard,
            kratzerPreferSameScratchCount: stage.kratzerPreferSameScratchCount,
            kratzerPlayUntilElimination: stage.kratzerPlayUntilElimination,
            kratzerBonusLifeFor180: stage.kratzerBonusLifeFor180,
            kratzerBonusLifeForHighFinish: stage.kratzerBonusLifeForHighFinish,
            kratzerHandicapsEnabled: stage.kratzerHandicapsEnabled,
            kratzerHandicaps: stage.kratzerHandicaps,
            kratzerHandicapAssignments: stage.kratzerHandicapAssignments,
            participants: participants,
          ),
        );
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
                : lossLimit == 2
                ? PlacementEngine.buildDoubleElimination(
                    rounds,
                    stage.placementPlaces.where(
                      (place) => place < participants.length,
                    ),
                  )
                : lossLimit >= 3
                ? PlacementEngine.buildTripleElimination(
                    rounds,
                    stage.placementPlaces.where(
                      (place) => place < participants.length,
                    ),
                    lossLimit: lossLimit,
                  )
                : const [],
            eliminationLossLimit: lossLimit,
            finalEndsTournament: stage.finalEndsTournament,
            kratzerPlayersPerBoard: stage.kratzerPlayersPerBoard,
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
    final requiredPlayers = nextStage.isGroupStage
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

  void _setQualificationAdvancementPolicy(String policy) => setState(() {
    _qualificationAdvancementPolicy = policy;
    _fixedQualifiersByGroup.clear();
    _selectedExtraGroups.clear();
  });

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
          onLeague: () {
            final navigator = Navigator.of(context);
            navigator.pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => LeagueMatchPage(
                  onCreated: (tournament) => navigator.pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => TournamentRunPage(
                        tournament: tournament,
                        tournamentStorage: widget.tournamentStorage,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          onFind: _openFormatPlanner,
          onExpert: () => setState(() => _showEntryChoices = false),
        ),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final groupSizes = _calculateGroupSizes();
    final canConfigureManualGroups =
        _canConfigureManualGroups && _players.isNotEmpty;
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
      appBar: AppBar(
        title: Text(
          widget.existingTournament == null
              ? 'Turnier erstellen'
              : 'Turnierkonfiguration bearbeiten',
        ),
      ),
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
              controller: _nameParticipantSectionController,
              initiallyExpanded: true,
              onExpansionChanged: (expanded) {
                if (expanded) {
                  _structureSectionController.collapse();
                  _summarySectionController.collapse();
                }
              },
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final nameField = TextField(
                      key: const ValueKey('tournament-name-field'),
                      controller: _tournamentNameController,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Turniername',
                        prefixIcon: Icon(Icons.emoji_events_outlined),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _saveTournamentNameDraft(),
                      onChanged: (_) => setState(() {}),
                    );
                    final pickNameButton = OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _pickTournamentName,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Name eines anderen Turniers öffnen'),
                    );
                    final saveButton = FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _saveTournamentNameDraft,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Namen speichern'),
                    );
                    final datePicker = TournamentDatePickerField(
                      value: _tournamentDate,
                      onChanged: (date) =>
                          setState(() => _tournamentDate = date),
                    );
                    final settingsButton = OutlinedButton.icon(
                      onPressed: _isCreatingTournament
                          ? null
                          : _pickTournamentSettings,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text(
                        'Einstellungen eines anderen Turniers öffnen',
                      ),
                    );
                    if (constraints.maxWidth < 900 ||
                        MediaQuery.textScalerOf(context).scale(16) > 24) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          nameField,
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [pickNameButton, saveButton],
                          ),
                          const SizedBox(height: 12),
                          datePicker,
                          const SizedBox(height: 8),
                          if (widget.existingTournament == null) settingsButton,
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: nameField),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(child: pickNameButton),
                                  const SizedBox(width: 8),
                                  Expanded(child: saveButton),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (widget.existingTournament == null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: datePicker),
                              const SizedBox(width: 16),
                              Expanded(child: settingsButton),
                            ],
                          )
                        else
                          datePicker,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                if (!_hasKratzerStage && !_hasTeamParticipants) ...[
                  SwitchListTile(
                    title: const Text('Ranglistenwertung'),
                    subtitle: const Text(
                      'Turnierergebnisse in ausgewählten Ranglisten werten.',
                    ),
                    value: _countsForRanking,
                    onChanged: (value) =>
                        unawaited(_configureRankingSelection(value)),
                  ),
                  if (_countsForRanking)
                    FutureBuilder<List<LocalRanking>>(
                      future: _localRankings,
                      builder: (context, snapshot) {
                        final rankings =
                            snapshot.data ?? const <LocalRanking>[];
                        final selectedNames = rankings
                            .where(
                              (ranking) =>
                                  _localRankingIds.contains(ranking.id),
                            )
                            .map((ranking) => ranking.name)
                            .join(', ');
                        return Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                unawaited(_configureRankingSelection(true)),
                            icon: const Icon(Icons.leaderboard_outlined),
                            label: Text(
                              snapshot.connectionState ==
                                      ConnectionState.waiting
                                  ? 'Ranglisten werden geladen …'
                                  : selectedNames.isEmpty
                                  ? 'Ranglisten auswählen'
                                  : selectedNames,
                            ),
                          ),
                        );
                      },
                    ),
                ],
                Text(
                  'Teilnehmer',
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
                      labelText: 'Teilnehmername',
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
                        tooltip: 'Teilnehmer hinzufügen',
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
                        label: const Text('Aus Spielerkatalog auswählen'),
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
                      labelText: 'Anzahl Teilnehmende',
                    ),
                  ),
                  trailing: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _generatePlayers,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Teilnehmer erzeugen'),
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
                  onReorder: _reorderPlayer,
                ),
                const SizedBox(height: 32),
              ],
            ),
            ExpertSetupSection(
              title: '2 · Turnierstruktur',
              summary:
                  '${_stages.length} Phasen gespeichert · Gruppen, KO und Spielregeln',
              enabled: _players.isNotEmpty,
              controller: _structureSectionController,
              onExpansionChanged: (expanded) {
                if (expanded) {
                  _nameParticipantSectionController.collapse();
                  _summarySectionController.collapse();
                }
              },
              children: [
                Text(
                  'Phasen',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (_stages.any((stage) => stage.type == 'kratzer') &&
                    _editingStageIndex == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Ein Kratzer-Turnier besteht nur aus dieser einen Phase. Entferne oder bearbeite sie, um die Konfiguration zu ändern.',
                    ),
                  ),
                Text('Name: ${_defaultStageName()}'),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton.filled(
                    key: const ValueKey('save-stage-button'),
                    onPressed:
                        _stages.any((stage) => stage.type == 'kratzer') &&
                            _editingStageIndex == null
                        ? null
                        : _saveStage,
                    icon: Icon(
                      _editingStageIndex == null ? Icons.add : Icons.check,
                    ),
                    tooltip: _editingStageIndex == null
                        ? 'Phase hinzufügen'
                        : 'Phase speichern',
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
                    labelText: 'Format',
                    prefixIcon: Icon(Icons.schema_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'groups',
                      child: Text('Gruppenphase'),
                    ),
                    const DropdownMenuItem(
                      value: 'swiss',
                      child: Text('Schweizer System'),
                    ),
                    if (_stages.isEmpty ||
                        (_editingStageIndex != null &&
                            _stages[_editingStageIndex!].type == 'kratzer'))
                      const DropdownMenuItem(
                        value: 'kratzer',
                        child: Text('Kratzer-Modus'),
                      ),
                    const DropdownMenuItem(
                      value: 'single_knockout',
                      child: Text('K.-o.-Runde'),
                    ),
                    const DropdownMenuItem(
                      value: 'double_knockout',
                      child: Text('Doppel-KO'),
                    ),
                    const DropdownMenuItem(
                      value: 'triple_knockout',
                      child: Text('Triple-KO'),
                    ),
                  ],
                  onChanged:
                      _stages.any((stage) => stage.type == 'kratzer') &&
                          _editingStageIndex == null
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _selectedStageType = value;
                            if (value == 'kratzer') {
                              _countsForRanking = false;
                              _localRankingIds.clear();
                            }
                            _finalEndsTournament = value != 'kratzer';
                            _kratzerLives = _lossLimitForStageType(
                              value,
                            ).clamp(2, 10);
                          });
                        },
                ),
                const SizedBox(height: 12),
                if (_selectedStageType == 'kratzer')
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
                    onChanged: (value) => _setKratzerLives(value ?? 3),
                  ),
                if (_selectedStageType == 'kratzer') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'kratzer-board-distribution-$_kratzerBoardDistribution',
                    ),
                    initialValue: _kratzerBoardDistribution,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Teilnehmer pro Board',
                      helperText:
                          'Gleichmäßig verteilt sich z. B. 15 Teilnehmer auf 4 Boards als 4, 4, 4 und 3.',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'balanced',
                        child: Text('Gleichmäßig auf verfügbare Boards'),
                      ),
                      for (final count in [3, 4, 5, 6])
                        DropdownMenuItem(
                          value: '$count',
                          child: Text('$count Teilnehmer'),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => _kratzerBoardDistribution = value ?? 'balanced',
                    ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('kratzer-prefer-same-scratches'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Teilnehmer mit gleichem Lebensstand bevorzugen',
                    ),
                    subtitle: const Text(
                      'Gleicht zuerst absolvierte Partien aus, vermeidet frühere Begegnungen wenn möglich und bevorzugt danach gleiche Kratzerstände.',
                    ),
                    value: _kratzerPreferSameScratchCount,
                    onChanged: (value) =>
                        setState(() => _kratzerPreferSameScratchCount = value),
                  ),
                  SwitchListTile(
                    key: const ValueKey('kratzer-play-until-elimination'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Gruppen bis zum Ausscheiden beibehalten',
                    ),
                    subtitle: const Text(
                      'Die Boards behalten ihre Gruppen, bis in einer Runde mindestens ein Teilnehmer ausscheidet.',
                    ),
                    value: _kratzerPlayUntilElimination,
                    onChanged: (value) =>
                        setState(() => _kratzerPlayUntilElimination = value),
                  ),
                  ExpansionTile(
                    key: const ValueKey('kratzer-special-rules'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Sonderregeln'),
                    children: [
                      SwitchListTile(
                        key: const ValueKey('kratzer-bonus-life-180'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bonusleben bei 180'),
                        subtitle: const Text(
                          'Die Turnierleitung kann im Ergebnisdialog für eine 180 ein zusätzliches Leben vergeben.',
                        ),
                        value: _kratzerBonusLifeFor180,
                        onChanged: (value) =>
                            setState(() => _kratzerBonusLifeFor180 = value),
                      ),
                      SwitchListTile(
                        key: const ValueKey('kratzer-bonus-life-high-finish'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bonusleben bei High Finish'),
                        subtitle: const Text(
                          'Die Turnierleitung kann im Ergebnisdialog für ein High Finish ein zusätzliches Leben vergeben.',
                        ),
                        value: _kratzerBonusLifeForHighFinish,
                        onChanged: (value) => setState(
                          () => _kratzerBonusLifeForHighFinish = value,
                        ),
                      ),
                      SwitchListTile(
                        key: const ValueKey('kratzer-handicaps-enabled'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Handicaps aktivieren'),
                        subtitle: const Text(
                          'Im Turnier lassen sich Handicaps verwalten und einzelnen Teilnehmern zuweisen.',
                        ),
                        value: _kratzerHandicapsEnabled,
                        onChanged: (value) =>
                            setState(() => _kratzerHandicapsEnabled = value),
                      ),
                      ExpansionTile(
                        key: const ValueKey('kratzer-starting-scratches'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Startkratzer je Teilnehmer'),
                        subtitle: Text(
                          _canEditKratzerStartingScratches
                              ? 'Vor Turnierstart bis zu $_kratzerLives Kratzer vergeben.'
                              : 'Startkratzer lassen sich nur vor Turnierbeginn ändern.',
                        ),
                        children: [
                          for (var index = 0; index < _players.length; index++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _players[index].name,
                                    style: textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  KeyedSubtree(
                                    key: ValueKey(
                                      'kratzer-start-scratches-field-$index-$_kratzerLives-${_players[index].kratzerStartingScratches}',
                                    ),
                                    child: DropdownButtonFormField<int>(
                                      key: ValueKey(
                                        'kratzer-start-scratches-$index',
                                      ),
                                      initialValue: _players[index]
                                          .kratzerStartingScratches
                                          .clamp(0, _kratzerLives)
                                          .toInt(),
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Startkratzer',
                                        helperText:
                                            '0 bedeutet: mit allen Leben starten.',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [
                                        for (
                                          var scratches = 0;
                                          scratches <= _kratzerLives;
                                          scratches++
                                        )
                                          DropdownMenuItem(
                                            value: scratches,
                                            child: Text(
                                              scratches == 0
                                                  ? '0 Kratzer'
                                                  : '$scratches Kratzer',
                                            ),
                                          ),
                                      ],
                                      onChanged:
                                          _canEditKratzerStartingScratches
                                          ? (value) {
                                              if (value != null) {
                                                _setKratzerStartingScratches(
                                                  index,
                                                  value,
                                                );
                                              }
                                            }
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
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
                if (_isGroupStageForm) ...[
                  const SizedBox(height: 12),
                  if (_selectedStageType == 'groups')
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
                  if (_selectedStageType == 'groups')
                    ExpertSetupSection(
                      title: 'Gruppenoptionen',
                      summary: 'Verteilung und Wiederholungen',
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
                          items: [
                            DropdownMenuItem(
                              value: GroupPlayerAllocationMode.strengthLevels,
                              child: Text('Nach Spielstärke gruppieren'),
                            ),
                            DropdownMenuItem(
                              value: GroupPlayerAllocationMode.balanced,
                              child: Text('Spielstärke gleichmäßig verteilen'),
                            ),
                            DropdownMenuItem(
                              value: GroupPlayerAllocationMode.random,
                              child: Text('Zufällige Verteilung'),
                            ),
                            DropdownMenuItem(
                              value: GroupPlayerAllocationMode.manual,
                              enabled: canConfigureManualGroups,
                              child: Text('Gruppen manuell festlegen'),
                            ),
                          ],
                          onChanged: (mode) {
                            if (mode != null) {
                              unawaited(_selectGroupAllocationMode(mode));
                            }
                          },
                        ),
                        if (_groupAllocationMode ==
                            GroupPlayerAllocationMode.manual) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              key: const ValueKey('edit-custom-groups'),
                              onPressed: canConfigureManualGroups
                                  ? () => unawaited(
                                      _selectGroupAllocationMode(
                                        GroupPlayerAllocationMode.manual,
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.drag_indicator),
                              label: Text(
                                _manualGroupSlotOrder == null
                                    ? 'Gruppen einteilen'
                                    : 'Gruppeneinteilung bearbeiten',
                              ),
                            ),
                          ),
                        ],
                        if (!_canConfigureManualGroups)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Manuelle Gruppen sind für die erste Gruppenetappe verfügbar. '
                              'Spätere Phasen können nach dem Weiterkommen angepasst werden.',
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(switch (_groupAllocationMode) {
                          GroupPlayerAllocationMode.strengthLevels =>
                            'Nach Spielstärke sortieren und nacheinander Gruppenblöcke bilden. '
                                'Die stärksten Wertungen starten in der ersten Gruppe.',
                          GroupPlayerAllocationMode.balanced =>
                            'Nach Spielstärke sortieren und abwechselnd auf die Gruppen verteilen.',
                          GroupPlayerAllocationMode.random =>
                            'Zufällige Verteilung der Teilnehmer auf die Gruppen.',
                          GroupPlayerAllocationMode.manual =>
                            'Teilnehmer per Drag-and-drop den gewünschten Gruppen zuordnen.',
                        }),
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
                        const SizedBox(height: 12),
                      ],
                    )
                  else
                    RoundRobinRepeatsSetup(
                      groupSizes: groupSizes,
                      playTypes: _playTypesForGroupSizes(groupSizes),
                      repeats: _roundRobinRepeatsForGroupSizes(groupSizes),
                      onChangeRepeats: _changeGroupRoundRobinRepeats,
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
                        labelText: 'Weiterkommende',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    trailing: ExpertSetupSection(
                      title: 'Weiterkommen im Detail',
                      summary:
                          'Plätze, Best-of-Vergleich und automatische Anpassung',
                      children: [
                        _GroupQualificationSetup(
                          groupSizes: groupSizes,
                          groupPlayTypes: _playTypesForGroupSizes(groupSizes),
                          qualificationPlan: groupQualificationPlan,
                          autoAdjust: _autoAdjustQualification,
                          advancementPolicy: _qualificationAdvancementPolicy,
                          bestOfQualifierCountController:
                              _bestOfQualifierCountController,
                          onSetExtraGroup: _setExtraGroupSelection,
                          onCyclePlace: _cycleQualificationPlace,
                          onAutoAdjustChanged: _setQualificationAutoAdjust,
                          onAdvancementPolicyChanged:
                              _setQualificationAdvancementPolicy,
                          onBestOfQualifierCountChanged:
                              _setBestOfQualifierCount,
                        ),
                      ],
                    ),
                    breakpoint: 620,
                  ),
                  const SizedBox(height: 12),
                  ExpertSetupSection(
                    title: 'Bei Punktgleichheit',
                    summary: 'Reihenfolge der Tabellenkriterien anpassen',
                    children: [
                      GroupTieBreakerSetup(
                        tieBreakers: _groupTieBreakers,
                        onMoveTieBreaker: _moveGroupTieBreaker,
                      ),
                      SwitchListTile(
                        key: const ValueKey('allow-group-deciders'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Stechen bei Gleichstand erlauben'),
                        subtitle: const Text(
                          'Entscheidungsspiele werden nur bei einem Gleichstand an einer Weiterkommensgrenze angelegt.',
                        ),
                        value: _allowGroupTieBreakDeciders,
                        onChanged: (value) =>
                            setState(() => _allowGroupTieBreakDeciders = value),
                      ),
                      if (_allowGroupTieBreakDeciders) ...[
                        Text(
                          'Spielformat fürs Stechen: ${_tieBreakGameFormat.x01Score} Double Out',
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          key: const ValueKey('tie-break-best-of-legs'),
                          isExpanded: true,
                          initialValue: _tieBreakGameFormat.bestOfLegs,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Stechen · Best of Legs',
                          ),
                          items: TournamentGameFormat.supportedBestOfLegs
                              .map(
                                (legs) => DropdownMenuItem(
                                  value: legs,
                                  child: Text('Best of $legs Legs'),
                                ),
                              )
                              .toList(),
                          onChanged: (legs) {
                            if (legs == null) return;
                            setState(
                              () => _tieBreakGameFormat = TournamentGameFormat(
                                gameType: 'x01',
                                x01Score: 501,
                                checkoutType: 'double_out',
                                bestOfLegs: legs,
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
                if (_isKnockoutStageType(_selectedStageType) &&
                    _selectedStageType != 'kratzer') ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('play-knockout-fully'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Turnierform vollständig ausspielen'),
                    value: _playKnockoutFully,
                    onChanged: (knockoutParticipantCount ?? 0) < 5
                        ? null
                        : (value) {
                            setState(() {
                              _playKnockoutFully = value;
                              if (!value) {
                                _finalEndsTournament = false;
                                _placementPlaces.clear();
                                _knockoutAdvancingCount =
                                    max(
                                      4,
                                      (knockoutParticipantCount ?? 4) ~/ 2,
                                    ).clamp(
                                      4,
                                      max(
                                        4,
                                        (knockoutParticipantCount ?? 4) - 1,
                                      ),
                                    );
                              } else {
                                _knockoutAdvancingCount = null;
                              }
                            });
                          },
                  ),
                  if (!_playKnockoutFully)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextFormField(
                        key: ValueKey(
                          'knockout-advancing-count-$_knockoutAdvancingCount',
                        ),
                        initialValue:
                            '${_knockoutAdvancingCount ?? max(4, (knockoutParticipantCount ?? 4) ~/ 2)}',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Weiterkommende',
                          helperText:
                              'Mindestens 4 Teilnehmer, weniger als die aktuelle Teilnehmerzahl.',
                        ),
                        validator: (value) {
                          final count = int.tryParse(value ?? '');
                          final participants = knockoutParticipantCount ?? 0;
                          if (count == null ||
                              count < 4 ||
                              count >= participants) {
                            return 'Bitte eine Zahl von 4 bis ${participants - 1} eingeben.';
                          }
                          return null;
                        },
                        onChanged: (value) => setState(
                          () => _knockoutAdvancingCount = int.tryParse(value),
                        ),
                      ),
                    ),
                  if (_playKnockoutFully &&
                      (_selectedStageType == 'double_knockout' ||
                          _selectedStageType == 'triple_knockout'))
                    SwitchListTile(
                      key: const ValueKey('final-ends-tournament'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Großes Finale ausspielen'),
                      value: _finalEndsTournament,
                      onChanged: (value) =>
                          setState(() => _finalEndsTournament = value),
                    ),
                  if (_playKnockoutFully) _placementSelection(),
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
                    allowEloSeed: _hasSelectedEloRanking,
                    onSeedingModeChanged: _setKnockoutSeedingMode,
                    onSwapSlot: _swapKnockoutSlots,
                    onResetSlots: _resetKnockoutSlots,
                  ),
                ],
                if (_isKnockoutStageType(_selectedStageType) &&
                    _selectedStageType != 'kratzer') ...[
                  const SizedBox(height: 12),
                  StageMatchCountPreview(
                    matchCount: _currentStageMatchCount(),
                    details: _currentStageMatchDetails(),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('save-stage-form-button'),
                  onPressed:
                      _stages.any((stage) => stage.type == 'kratzer') &&
                              _editingStageIndex == null ||
                          _loadingEloRatingsForSeeding
                      ? null
                      : _saveStage,
                  icon: Icon(
                    _editingStageIndex == null ? Icons.add : Icons.check,
                  ),
                  label: Text(
                    _editingStageIndex == null
                        ? 'Phase hinzufügen'
                        : 'Änderungen speichern',
                  ),
                ),
                const SizedBox(height: 16),
                _StageList(
                  stages: _stages,
                  boardCount: _plannedBoardCount,
                  editingStageIndex: _editingStageIndex,
                  onEditStage: _editStage,
                  onRemoveStage: _removeStage,
                ),
              ],
            ),
            ExpertSetupSection(
              title: '3 · Zusammenfassung & Start',
              summary:
                  '${_players.length} Teilnehmer · ${_stages.length} Phasen · $_plannedBoardCount Boards',
              enabled: _stages.isNotEmpty,
              controller: _summarySectionController,
              onExpansionChanged: (expanded) {
                if (expanded) {
                  _nameParticipantSectionController.collapse();
                  _structureSectionController.collapse();
                }
              },
              children: [
                if (_hasKratzerStage)
                  KratzerDurationPreview(
                    stages: [
                      if (_stages.isEmpty) _currentStageConfiguration(),
                      for (var i = 0; i < _stages.length; i++)
                        i == _editingStageIndex
                            ? _currentStageConfiguration()
                            : _stages[i],
                    ],
                    participantCount: _players.length,
                    boards: _plannedBoardCount,
                    onBoardsChanged: (boards) =>
                        setState(() => _plannedBoardCount = boards),
                    onEstimateChanged: (estimate) {
                      _configurationEstimate = estimate;
                    },
                  )
                else
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
                    onEstimateChanged: (estimate) {
                      _configurationEstimate = estimate;
                    },
                  ),
                const SizedBox(height: 12),
                const SizedBox(height: 24),
                if (_players.isEmpty || _stages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _players.isEmpty
                          ? 'Zum Speichern fehlen die Teilnehmer. Bitte oben Teilnehmer hinzufügen oder auswählen.'
                          : 'Zum Speichern fehlt eine Phase. Bitte eine Phase hinzufügen oder einen Vorschlag übernehmen.',
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
                        ? 'Wird gespeichert …'
                        : widget.existingTournament == null
                        ? 'Turnier anlegen'
                        : 'Einstellungen speichern',
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
