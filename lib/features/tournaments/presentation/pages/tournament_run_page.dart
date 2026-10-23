part of '../../../../tournament_workspace.dart';

class TournamentRunPage extends StatelessWidget {
  const TournamentRunPage({
    super.key,
    required this.tournament,
    this.runController,
  });

  final CreatedTournament tournament;
  final TournamentRunController? runController;

  @override
  Widget build(BuildContext context) =>
      tournament.importedArchive != null &&
          !tournament.importedArchive!.usesNativeLogic
      ? ChallongeArchivePage(tournament: tournament)
      : _LiveTournamentRunPage(
          tournament: tournament,
          runController: runController,
        );
}

class _LiveTournamentRunPage extends StatefulWidget {
  const _LiveTournamentRunPage({required this.tournament, this.runController});
  final CreatedTournament tournament;
  final TournamentRunController? runController;
  @override
  State<_LiveTournamentRunPage> createState() => _TournamentRunPageState();
}

class _TournamentClockStatus extends StatefulWidget {
  const _TournamentClockStatus({required this.tournament});

  final CreatedTournament tournament;

  @override
  State<_TournamentClockStatus> createState() => _TournamentClockStatusState();
}

class _TournamentClockStatusState extends State<_TournamentClockStatus> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tournament = widget.tournament;
    final elapsed = TournamentTiming.snapshot(
      tournament,
      DateTime.now(),
    ).elapsed;
    final time =
        '${elapsed.inHours.toString().padLeft(2, '0')}:'
        '${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}:'
        '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final paused = tournament.isClockPaused;
    return Text(
      'Status: ${paused ? 'Pausiert' : 'Läuft aktiv'} · $time',
      key: const ValueKey('tournament-clock-status'),
    );
  }
}

class _TournamentRunPageState extends State<_LiveTournamentRunPage>
    with WidgetsBindingObserver {
  bool _leaving = false;
  bool _allowPop = false;
  bool _backgrounded = false;
  bool _savingRankingSelection = false;
  bool _savingTieBreakerSettings = false;
  int? _tieBreakerDraftStageIndex;
  List<String> _tieBreakerDraft = const [];
  Future<void> _checkpoint() => _runController.saveProgress(
    tournament: widget.tournament,
    activeStageIndex: _activeStageIndex,
    completedStageIndexes: _completedStageIndexes,
  );

  Future<void> _leaveTournament({bool home = false}) async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _checkpoint();
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (home) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          Navigator.of(context).pop();
        }
      });
    } catch (_) {
      _leaving = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Speichern fehlgeschlagen. Bitte erneut zurückgehen.',
            ),
          ),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    if (widget.tournament.leagueMatch != null) return;
    if (_backgrounded) {
      unawaited(
        _checkpoint().catchError((Object error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Turnier konnte nicht zwischengespeichert werden.',
                ),
              ),
            );
          }
        }),
      );
    } else if (!_leaving) {
      unawaited(_saveTournamentProgress());
    }
  }

  int _activeStageIndex = 0;
  int _viewStageIndex = 0;
  StageViewMode _stageViewMode = StageViewMode.dashboard;
  String? _directorSaveError;

  Future<void> _renamePlayer(TournamentPlayer player) async {
    if (player.profileId != null) return;
    final controller = TextEditingController(text: player.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spieler umbenennen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Neuer Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != player.name) {
      final updatedPlayer = player.copyWith(name: newName);
      setState(() {
        final t = widget.tournament;
        final pIdx = t.players.indexOf(player);
        if (pIdx != -1) {
          t.players[pIdx] = updatedPlayer;
        }
        for (final stage in t.runStages) {
          if (stage is GroupTournamentRunStage) {
            for (final g in stage.groups) {
              final gIdx = g.players.indexOf(player);
              if (gIdx != -1) {
                g.players[gIdx] = updatedPlayer;
              }
              for (final m in g.matches) {
                if (m.homePlayer == player) m.homePlayer = updatedPlayer;
                if (m.awayPlayer == player) m.awayPlayer = updatedPlayer;
              }
            }
          } else if (stage is KnockoutTournamentRunStage) {
            for (final round in stage.rounds) {
              for (final m in round) {
                if (m.homePlayer == player) m.homePlayer = updatedPlayer;
                if (m.awayPlayer == player) m.awayPlayer = updatedPlayer;
              }
            }
            for (final m in stage.placementMatches) {
              if (m.homePlayer == player) m.homePlayer = updatedPlayer;
              if (m.awayPlayer == player) m.awayPlayer = updatedPlayer;
            }
          }
        }
      });
      await _saveTournamentProgress();
    }
  }

  Future<void> _withdrawPlayer([TournamentPlayer? selectedPlayer]) async {
    final rule = await showDialog<PlayerWithdrawal>(
      context: context,
      builder: (_) => PlayerWithdrawalDialog(
        tournament: widget.tournament,
        initialPlayer: selectedPlayer,
      ),
    );
    if (rule == null || !mounted) return;
    try {
      setState(() {
        final affected =
            const OrderOfPlayController()
                .entries(widget.tournament)
                .where(
                  (e) => [e.match.homePlayer, e.match.awayPlayer].any(
                    (p) =>
                        p != null &&
                        PlayerWithdrawalService.key(p) == rule.playerKey,
                  ),
                )
                .map((e) => e.stageIndex)
                .toList()
              ..sort();
        widget.tournament.withdrawals.add(rule);
        _advanceKnockoutWinners();
        if (rule.retroactive &&
            affected.isNotEmpty &&
            affected.first < _activeStageIndex) {
          _activeStageIndex = affected.first;
          _viewStageIndex = _activeStageIndex;
          _completedStageIndexes.removeWhere((i) => i >= _activeStageIndex);
          widget.tournament.completedStageIndexes.removeWhere(
            (i) => i >= _activeStageIndex,
          );
          widget.tournament.finishedAt = null;
          for (
            var i = _activeStageIndex + 1;
            i < widget.tournament.runStages.length;
            i++
          ) {
            final incoming = _advancingPlayersFromStage(
              widget.tournament.runStages[i - 1],
            );
            widget.tournament.runStages[i] = _buildRunStageFromPlayers(
              widget.tournament.stages[i],
              incoming,
            );
          }
        }
        _ensureGroupDeciders();
      });
      await _runController.saveProgress(
        tournament: widget.tournament,
        activeStageIndex: _activeStageIndex,
        completedStageIndexes: _completedStageIndexes,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ausstieg konnte nicht sicher gespeichert werden. Bitte Berechtigung prüfen und erneut speichern.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _exportTournament() async {
    final data = TournamentExport.encode(widget.tournament);
    final html = TournamentExport.html(widget.tournament);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turnierdaten exportieren'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: SelectableText(data, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (context.mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Turnierdaten kopiert.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('JSON kopieren'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: html));
              if (context.mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('HTML-Übersicht kopiert.')),
                );
              }
            },
            icon: const Icon(Icons.language),
            label: const Text('HTML kopieren'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBoardBlock(int board) async {
    if (!mounted) return;
    if (board < 1 || board > widget.tournament.boardCount) {
      throw StateError('Board nicht mehr verfügbar.');
    }
    final schedule = const OrderOfPlayController().plan(
      widget.tournament,
      _activeStageIndex,
    );
    if (schedule.running.any((e) => e.match.boardNumber == board)) {
      throw StateError('Ein laufendes Board kann nicht gesperrt werden.');
    }
    final wasBlocked = widget.tournament.blockedBoards.contains(board);
    setState(() {
      if (wasBlocked) {
        widget.tournament.blockedBoards.remove(board);
      } else {
        widget.tournament.blockedBoards.add(board);
      }
    });
    try {
      await _checkpoint();
    } catch (_) {
      if (wasBlocked) {
        widget.tournament.blockedBoards.add(board);
      } else {
        widget.tournament.blockedBoards.remove(board);
      }
      if (mounted) setState(() {});
      rethrow;
    }
  }

  bool _isBracketEditMode = false;
  bool _isApplyingStartDraw = false;
  final Set<int> _completedStageIndexes = {};
  TournamentRunController get _runController =>
      widget.runController ?? const TournamentRunController();
  final _tournamentNameController = TextEditingController();
  late final Future<List<LocalRanking>> _localRankings = LocalAppDatabase()
      .loadLocalRankings();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tournamentNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _stageViewMode = StageViewMode.dashboard;
    _tournamentNameController.text = widget.tournament.name;
    WidgetsBinding.instance.addObserver(this);
    if (widget.tournament.leagueMatch != null) return;
    _activeStageIndex = widget.tournament.activeStageIndex.clamp(
      0,
      widget.tournament.runStages.isEmpty
          ? 0
          : widget.tournament.runStages.length - 1,
    );
    _viewStageIndex = _activeStageIndex;
    _completedStageIndexes.addAll(widget.tournament.completedStageIndexes);
    widget.tournament.startedAt ??= DateTime.now();
    _restoreCompletedGroupDrawForActiveStage();
    _advanceKnockoutWinners();
    _ensureGroupDeciders();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _applyPendingStartDrawForActiveStage();
      if (!mounted) return;
      await _saveTournamentProgress();
    });
  }

  Future<void> _toggleClockPause() async {
    TournamentTiming.togglePause(widget.tournament);
    try {
      await _saveTournamentProgress();
      if (mounted) setState(() {});
    } catch (_) {
      TournamentTiming.togglePause(widget.tournament);
      rethrow;
    }
  }

  Future<void> _saveTournamentProgress({bool propagateError = false}) async {
    try {
      await _runController.saveProgress(
        tournament: widget.tournament,
        activeStageIndex: _activeStageIndex,
        completedStageIndexes: _completedStageIndexes,
      );
      if (mounted && _directorSaveError != null) {
        setState(() => _directorSaveError = null);
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _directorSaveError =
            'Änderungen sind noch nicht sicher gespeichert. Bitte erneut speichern.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Änderungen konnten nicht gespeichert werden.'),
          action: SnackBarAction(
            label: 'Erneut versuchen',
            onPressed: _saveTournamentProgress,
          ),
        ),
      );
      if (propagateError) rethrow;
    }
  }

  String _tournamentTypeLabel() {
    final tournament = widget.tournament;
    if (tournament.leagueMatch != null) {
      return tournament.leagueMatch!.variant == LeagueMatchVariant.adjusted
          ? 'Angepasstes Liga-/Freundschaftsspiel'
          : 'Traditionelles Ligaspiel';
    }
    if (tournament.importedArchive != null) return 'Challonge-Turnier';
    if (tournament.countsForRanking && tournament.rankingIds.isNotEmpty) {
      return 'Ranglistenturnier';
    }
    return 'Normales Turnier';
  }

  Future<void> _saveTournamentName() async {
    final name = _tournamentNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Turniername darf nicht leer sein.')),
      );
      return;
    }
    final previousName = widget.tournament.name;
    widget.tournament.name = name;
    try {
      await _saveTournamentProgress(propagateError: true);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Turniername gespeichert.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      widget.tournament.name = previousName;
      _tournamentNameController.text = previousName;
    }
  }

  Future<void> _saveRankingSelection({
    required bool countsForRanking,
    required List<String> rankingIds,
  }) async {
    if (_savingRankingSelection) return;
    final previousCounts = widget.tournament.countsForRanking;
    final previousIds = List<String>.from(widget.tournament.rankingIds);
    setState(() {
      _savingRankingSelection = true;
      widget.tournament.countsForRanking = countsForRanking;
      widget.tournament.rankingIds
        ..clear()
        ..addAll(countsForRanking ? rankingIds : const []);
    });
    try {
      await _saveTournamentProgress(propagateError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        widget.tournament.countsForRanking = previousCounts;
        widget.tournament.rankingIds
          ..clear()
          ..addAll(previousIds);
      });
    } finally {
      if (mounted) {
        setState(() => _savingRankingSelection = false);
      }
    }
  }

  List<String> _tieBreakersForActiveStage() {
    if (_activeStageIndex >= widget.tournament.stages.length) {
      return const [];
    }
    if (_tieBreakerDraftStageIndex == _activeStageIndex) {
      return _tieBreakerDraft;
    }
    return widget.tournament.stages[_activeStageIndex].groupTieBreakers;
  }

  bool get _hasPendingTieBreakerChanges {
    if (_tieBreakerDraftStageIndex != _activeStageIndex ||
        _activeStageIndex >= widget.tournament.stages.length) {
      return false;
    }
    final saved = widget.tournament.stages[_activeStageIndex].groupTieBreakers;
    final draft = _tieBreakerDraft;
    return saved.length != draft.length ||
        List.generate(
          saved.length,
          (index) => index,
        ).any((index) => saved[index] != draft[index]);
  }

  Future<void> _moveGroupTieBreakerDraft(int index, int direction) async {
    if (_viewStageIndex != _activeStageIndex ||
        _activeStageIndex >= widget.tournament.stages.length ||
        _savingTieBreakerSettings ||
        _completedStageIndexes.contains(_activeStageIndex)) {
      return;
    }
    final stage = widget.tournament.stages[_activeStageIndex];
    if (stage.type != 'groups') return;
    final target = index + direction;
    final current = _tieBreakersForActiveStage();
    if (index < 0 ||
        index >= current.length ||
        target < 0 ||
        target >= current.length) {
      return;
    }
    final tieBreakers = List<String>.from(current);
    final moved = tieBreakers.removeAt(index);
    tieBreakers.insert(target, moved);
    setState(() {
      _tieBreakerDraftStageIndex = _activeStageIndex;
      _tieBreakerDraft = List.unmodifiable(tieBreakers);
    });
  }

  Future<void> _applyGroupTieBreakerDraft() async {
    final stageIndex = _activeStageIndex;
    if (!_hasPendingTieBreakerChanges ||
        _savingTieBreakerSettings ||
        stageIndex >= widget.tournament.runStages.length ||
        _viewStageIndex != stageIndex ||
        _completedStageIndexes.contains(stageIndex)) {
      return;
    }
    final previousStage = widget.tournament.stages[stageIndex];
    final previousRunStage = widget.tournament.runStages[stageIndex];
    if (previousRunStage is! GroupTournamentRunStage) return;
    final tieBreakers = List<String>.unmodifiable(_tieBreakerDraft);
    final updatedStage = previousStage.copyWith(groupTieBreakers: tieBreakers);
    final updatedRunStage = GroupTournamentRunStage(
      name: previousRunStage.name,
      groupPlayType: previousRunStage.groupPlayType,
      groups: previousRunStage.groups,
      qualificationPlan: previousRunStage.qualificationPlan,
      tieBreakers: tieBreakers,
    );
    setState(() {
      _savingTieBreakerSettings = true;
      widget.tournament.stages[stageIndex] = updatedStage;
      widget.tournament.runStages[stageIndex] = updatedRunStage;
    });
    try {
      await _runController.saveProgress(
        tournament: widget.tournament,
        activeStageIndex: _activeStageIndex,
        completedStageIndexes: _completedStageIndexes,
      );
      if (!mounted) return;
      setState(() {
        _savingTieBreakerSettings = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tie-Breaker übernommen. Tabelle und Prognose wurden aktualisiert.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingTieBreakerSettings = false;
        widget.tournament.stages[stageIndex] = previousStage;
        widget.tournament.runStages[stageIndex] = previousRunStage;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tie-Breaker konnten nicht gespeichert werden: $error'),
        ),
      );
    }
  }

  Future<void> _editResult(GroupMatch match) async {
    if (match.withdrawalSignature != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dieses Ergebnis wurde durch die Ausstiegsregel festgelegt.',
          ),
        ),
      );
      return;
    }
    final result = await showDialog<MatchResult>(
      context: context,
      builder: (context) => ResultDialog(
        match: match,
        format: widget.tournament.stages[_activeStageIndex].gameFormat,
        allowAdministration: true,
      ),
    );

    if (result == null) {
      return;
    }
    if (!mounted) return;
    final currentStage = widget.tournament.runStages[_activeStageIndex];
    if (currentStage is GroupTournamentRunStage &&
        currentStage.groups.any(
          (group) =>
              group.playType == 'swiss' &&
              group.matches.contains(match) &&
              group.matches.any(
                (later) =>
                    later.round > match.round &&
                    (later.hasResult || later.startedAt != null),
              ),
        )) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Spätere Swiss-Runden zurücksetzen?'),
          content: const Text(
            'Die Paarungen späterer Runden hängen von diesem Ergebnis ab. Ihre Ergebnisse und laufenden Spiele werden zurückgesetzt und die nächste Runde neu gepaart.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Zurücksetzen'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      match.finishedAt = result.isAnnulled || result.homeLegs == null
          ? null
          : match.finishedAt ?? DateTime.now();
      final stage = widget.tournament.runStages[_activeStageIndex];
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          if (group.playType == 'swiss' && group.matches.contains(match)) {
            SwissEngine.invalidateAfter(group, match.round);
          }
        }
      }
      match.isAnnulled = result.isAnnulled;
      match.bestPerformances = result.bestPerformances;
      match.homeSets = result.homeSets;
      match.awaySets = result.awaySets;
      if (result.isAnnulled) {
        match.homeLegs = null;
        match.homeSets = null;
        match.awaySets = null;
        match.awayLegs = null;
      } else {
        match.homeLegs = result.homeLegs;
        match.awayLegs = result.awayLegs;
      }
      _advanceKnockoutWinners();
      _ensureGroupDeciders();
      const OrderOfPlayController().resultRecorded(match);
    });
    try {
      await _saveTournamentProgress(propagateError: true);
    } catch (_) {
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ergebnis gespeichert · Partie ist gespielt.'),
          duration: const Duration(seconds: 2),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  bool _canEditKnockoutBracket(KnockoutTournamentRunStage stage) {
    return stage.rounds.isNotEmpty &&
        stage.rounds.first.isNotEmpty &&
        stage.matches.every(
          (match) =>
              !match.hasScore && !match.isAnnulled && match.startedAt == null,
        );
  }

  Future<void> _editGroupPositions(GroupTournamentRunStage stage) async {
    if (_isApplyingStartDraw ||
        widget.tournament.runStages[_activeStageIndex] != stage ||
        _completedStageIndexes.contains(_activeStageIndex) ||
        !GroupPositionEditor.canEdit(stage)) {
      return;
    }
    final pair = await showDialog<List<TournamentPlayer>>(
      context: context,
      builder: (_) => GroupPositionsDialog(stage: stage),
    );
    if (!mounted ||
        pair == null ||
        widget.tournament.runStages[_activeStageIndex] != stage ||
        _completedStageIndexes.contains(_activeStageIndex)) {
      return;
    }
    var changed = false;
    setState(() {
      changed = GroupPositionEditor.swap(stage, pair[0], pair[1]);
      if (changed) {
        _persistGroupArrangementInDrawOrder(stage);
        _advanceKnockoutWinners();
        _ensureGroupDeciders();
      }
    });
    if (changed) await _saveTournamentProgress();
  }

  void _persistGroupArrangementInDrawOrder(GroupTournamentRunStage runStage) {
    final stageIndex = _activeStageIndex;
    if (stageIndex >= widget.tournament.stages.length) return;
    final stage = widget.tournament.stages[stageIndex];
    if (!stage.groupDrawOnStart || !stage.groupDrawCompleted) return;
    final incomingPlayers = _incomingPlayersForStage(stageIndex);
    if (stage.groupSizes.length != runStage.groups.length) return;
    final slotOrder = <int?>[];
    for (
      var groupIndex = 0;
      groupIndex < runStage.groups.length;
      groupIndex++
    ) {
      final group = runStage.groups[groupIndex];
      final groupSize = stage.groupSizes[groupIndex];
      if (group.players.length > groupSize) return;
      for (final player in group.players) {
        final playerIndex = incomingPlayers.indexOf(player);
        if (playerIndex < 0) return;
        slotOrder.add(playerIndex + 1);
      }
      slotOrder.addAll(
        List<int?>.filled(groupSize - group.players.length, null),
      );
    }
    widget.tournament.stages[stageIndex] = stage.copyWith(
      groupSlotOrder: List.unmodifiable(slotOrder),
    );
  }

  void _restoreCompletedGroupDrawForActiveStage() {
    final stageIndex = _activeStageIndex;
    if (stageIndex >= widget.tournament.stages.length ||
        stageIndex >= widget.tournament.runStages.length) {
      return;
    }
    var stage = widget.tournament.stages[stageIndex];
    final runStage = widget.tournament.runStages[stageIndex];
    if (stage.type != 'groups' ||
        !stage.groupDrawOnStart ||
        stage.groupSlotOrder.isEmpty ||
        runStage is! GroupTournamentRunStage) {
      return;
    }
    if (!stage.groupDrawCompleted) {
      stage = stage.copyWith(groupDrawCompleted: true);
      widget.tournament.stages[stageIndex] = stage;
    }
    if (!GroupPositionEditor.canEdit(runStage)) return;

    final expected = _buildRunStageFromPlayers(
      stage,
      _incomingPlayersForStage(stageIndex),
    );
    if (expected is! GroupTournamentRunStage ||
        expected.groups.length != runStage.groups.length) {
      return;
    }
    final hasDifferentAssignments = List.generate(expected.groups.length, (
      groupIndex,
    ) {
      final expectedPlayers = expected.groups[groupIndex].players;
      final savedPlayers = runStage.groups[groupIndex].players;
      return expectedPlayers.length != savedPlayers.length ||
          List.generate(
            expectedPlayers.length,
            (playerIndex) => playerIndex,
          ).any(
            (playerIndex) =>
                expectedPlayers[playerIndex] != savedPlayers[playerIndex],
          );
    }).any((different) => different);
    if (hasDifferentAssignments) {
      widget.tournament.runStages[stageIndex] = expected;
    }
  }

  Future<void> _swapKnockoutRunSlots(
    KnockoutTournamentRunStage stage,
    int fromSlotIndex,
    int toSlotIndex,
  ) async {
    if (!_canEditKnockoutBracket(stage) ||
        fromSlotIndex == toSlotIndex ||
        fromSlotIndex < 0 ||
        toSlotIndex < 0) {
      return;
    }

    final firstRound = stage.rounds.first;
    final maxSlotIndex = firstRound.length * 2 - 1;
    if (fromSlotIndex > maxSlotIndex || toSlotIndex > maxSlotIndex) {
      return;
    }

    setState(() {
      final fromPlayer = _playerAtFirstRoundSlot(firstRound, fromSlotIndex);
      final toPlayer = _playerAtFirstRoundSlot(firstRound, toSlotIndex);
      _setPlayerAtFirstRoundSlot(firstRound, fromSlotIndex, toPlayer);
      _setPlayerAtFirstRoundSlot(firstRound, toSlotIndex, fromPlayer);
      _clearKnockoutProgress(stage.rounds);
      _clearPlacementMatches(stage.placementMatches);
      _advanceKnockoutWinners();
    });
    await _saveTournamentProgress();
  }

  TournamentPlayer? _playerAtFirstRoundSlot(
    List<GroupMatch> firstRound,
    int slotIndex,
  ) {
    final match = firstRound[slotIndex ~/ 2];
    return slotIndex.isEven ? match.homePlayer : match.awayPlayer;
  }

  void _setPlayerAtFirstRoundSlot(
    List<GroupMatch> firstRound,
    int slotIndex,
    TournamentPlayer? player,
  ) {
    final match = firstRound[slotIndex ~/ 2];
    if (slotIndex.isEven) {
      match.homePlayer = player;
    } else {
      match.awayPlayer = player;
    }
  }

  void _clearKnockoutProgress(List<List<GroupMatch>> rounds) {
    for (var roundIndex = 0; roundIndex < rounds.length; roundIndex++) {
      for (final match in rounds[roundIndex]) {
        match.homeLegs = null;
        match.homeSets = null;
        match.awaySets = null;
        match.awayLegs = null;
        match.isAnnulled = false;
        if (roundIndex > 0) {
          match.homePlayer = null;
          match.awayPlayer = null;
        }
      }
    }
  }

  void _clearPlacementMatches(List<GroupMatch> matches) {
    for (final match in matches) {
      match.homePlayer = null;
      match.awayPlayer = null;
      match.homeLegs = null;
      match.homeSets = null;
      match.awaySets = null;
      match.awayLegs = null;
      match.isAnnulled = false;
    }
  }

  void _advanceKnockoutWinners() {
    if (widget.tournament.withdrawals.isEmpty) {
      _advanceWithoutWithdrawals();
      return;
    }
    // Propagate forfeits through newly populated rounds until stable.
    final limit = widget.tournament.players.length * 8 + 32;
    for (var i = 0; i < limit; i++) {
      final changed = const PlayerWithdrawalService().reconcile(
        widget.tournament,
      );
      _advanceWithoutWithdrawals();
      if (!changed &&
          !const PlayerWithdrawalService().reconcile(widget.tournament)) {
        break;
      }
    }
  }

  void _advanceWithoutWithdrawals() {
    for (final stage in widget.tournament.runStages) {
      if (stage is KnockoutTournamentRunStage) {
        if (stage.eliminationLossLimit == 2) {
          _advanceDoubleEliminationRounds(
            stage.rounds,
            finalEndsTournament: stage.finalEndsTournament,
          );
        } else if (stage.eliminationLossLimit >= 3) {
          TripleKoEngine.advance(
            stage.rounds,
            lossLimit: stage.eliminationLossLimit,
            finalEndsTournament: stage.finalEndsTournament,
          );
        } else {
          _advanceWinnersInRounds(stage.rounds);
          _advancePlacementMatches(stage.rounds, stage.placementMatches);
        }
      }

      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          if (group.playType == 'swiss') SwissEngine.advance(group);
          if (_isEliminationGroupPlayType(group.playType)) {
            if (group.eliminationLossLimit == 2) {
              _advanceDoubleEliminationRounds(
                group.knockoutRounds,
                finalEndsTournament: group.finalEndsTournament,
              );
              group.matches
                ..clear()
                ..addAll([
                  for (final round in group.knockoutRounds) ...round,
                  ...group.placementMatches,
                ]);
              continue;
            }
            if (group.eliminationLossLimit == 3) {
              TripleKoEngine.advance(
                group.knockoutRounds,
                lossLimit: group.eliminationLossLimit,
                finalEndsTournament: group.finalEndsTournament,
              );
              group.matches
                ..clear()
                ..addAll([
                  for (final round in group.knockoutRounds) ...round,
                  ...group.placementMatches,
                ]);
              continue;
            }
            _advanceWinnersInRounds(group.knockoutRounds);
            _advancePlacementMatches(
              group.knockoutRounds,
              group.placementMatches,
            );
          }
        }
      }
    }
  }

  void _advanceWinnersInRounds(List<List<GroupMatch>> rounds) {
    for (var roundIndex = 0; roundIndex < rounds.length - 1; roundIndex++) {
      final currentRound = rounds[roundIndex];
      final nextRound = rounds[roundIndex + 1];
      for (var matchIndex = 0; matchIndex < currentRound.length; matchIndex++) {
        final winner = currentRound[matchIndex].winner;
        final targetMatch = nextRound[matchIndex ~/ 2];
        if (matchIndex.isEven) {
          if (targetMatch.homePlayer != winner) {
            targetMatch.homeLegs = null;
            targetMatch.homeSets = null;
            targetMatch.awaySets = null;
            targetMatch.awayLegs = null;
            targetMatch.isAnnulled = false;
          }
          targetMatch.homePlayer = winner;
        } else {
          if (targetMatch.awayPlayer != winner) {
            targetMatch.homeLegs = null;
            targetMatch.homeSets = null;
            targetMatch.awaySets = null;
            targetMatch.awayLegs = null;
            targetMatch.isAnnulled = false;
          }
          targetMatch.awayPlayer = winner;
        }
      }
      if (widget.tournament.withdrawals.isNotEmpty) {
        for (var i = 0; i < nextRound.length; i++) {
          final sources = currentRound.skip(i * 2).take(2).toList();
          final target = nextRound[i];
          final resolved =
              sources.length == 2 && sources.every((m) => m.isResolved);
          target.allowsBye = resolved && !target.hasPlayers;
          if (resolved &&
              target.homePlayer == null &&
              target.awayPlayer == null) {
            target.isAnnulled = true;
          }
        }
      }
    }
  }

  void _ensureGroupDeciders() {
    for (final stage in widget.tournament.runStages) {
      if (stage is! GroupTournamentRunStage) {
        continue;
      }

      for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
        final group = stage.groups[groupIndex];
        if (group.playType != 'round_robin') {
          continue;
        }
        _ensureDecidersForGroup(stage, group, groupIndex);
      }
      _ensureBestOfDecidersForStage(stage);
    }
  }

  void _ensureBestOfDecidersForStage(GroupTournamentRunStage stage) {
    final plan = stage.qualificationPlan;
    if (plan == null || plan.extraCount < 1 || plan.extraGroups.isEmpty) {
      return;
    }

    final candidates = _bestOfCandidatesForStage(stage);
    if (candidates.length <= plan.extraCount) {
      return;
    }

    for (final groupNumber in plan.extraGroups) {
      final groupIndex = groupNumber - 1;
      if (groupIndex < 0 || groupIndex >= stage.groups.length) {
        return;
      }
      final group = stage.groups[groupIndex];
      final baseMatches = group.matches.where(
        (match) => match.label != 'Beste-N Decider',
      );
      if (baseMatches.any((match) => match.hasPlayers && !match.isResolved)) {
        return;
      }
    }

    final sortedByTieBreakers = List<BestOfCandidate>.from(candidates)
      ..sort((a, b) => _compareBestOfTieBreakersOnly(stage, a, b));
    final boundaryIndex = plan.extraCount - 1;
    if (boundaryIndex < 0 || boundaryIndex >= sortedByTieBreakers.length) {
      return;
    }

    final boundaryCandidate = sortedByTieBreakers[boundaryIndex];
    final tiedAtBoundary = sortedByTieBreakers
        .where(
          (candidate) =>
              _compareBestOfTieBreakersOnly(
                stage,
                candidate,
                boundaryCandidate,
              ) ==
              0,
        )
        .toList();
    final firstTiedIndex = sortedByTieBreakers.indexWhere(
      (candidate) =>
          _compareBestOfTieBreakersOnly(stage, candidate, boundaryCandidate) ==
          0,
    );
    final lastTiedIndex = sortedByTieBreakers.lastIndexWhere(
      (candidate) =>
          _compareBestOfTieBreakersOnly(stage, candidate, boundaryCandidate) ==
          0,
    );

    if (tiedAtBoundary.length < 2 ||
        firstTiedIndex >= plan.extraCount ||
        lastTiedIndex < plan.extraCount) {
      return;
    }

    for (var first = 0; first < tiedAtBoundary.length; first++) {
      for (var second = first + 1; second < tiedAtBoundary.length; second++) {
        _addBestOfDeciderIfMissing(
          stage,
          tiedAtBoundary[first],
          tiedAtBoundary[second],
        );
      }
    }
  }

  List<BestOfCandidate> _bestOfCandidatesForStage(
    GroupTournamentRunStage stage,
  ) {
    final plan = stage.qualificationPlan;
    if (plan == null || plan.extraCount < 1) {
      return const [];
    }

    final candidates = <BestOfCandidate>[];
    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final groupNumber = groupIndex + 1;
      if (!plan.extraGroups.contains(groupNumber)) {
        continue;
      }

      final group = stage.groups[groupIndex];
      if (group.playType != 'round_robin') {
        continue;
      }

      final candidateIndex = plan.extraRank - 1;
      final standings = _standingsFor(group, stage.tieBreakers);
      if (candidateIndex < 0 || candidateIndex >= standings.length) {
        continue;
      }

      candidates.add(
        BestOfCandidate(
          groupName: group.name,
          groupNumber: groupNumber,
          place: plan.extraRank,
          standing: standings[candidateIndex],
        ),
      );
    }

    return candidates;
  }

  int _compareBestOfTieBreakersOnly(
    GroupTournamentRunStage stage,
    BestOfCandidate a,
    BestOfCandidate b,
  ) {
    for (final tieBreaker in stage.tieBreakers) {
      final comparison = switch (tieBreaker) {
        'points' => b.standing.points.compareTo(a.standing.points),
        'legDifference' => b.standing.legDifference.compareTo(
          a.standing.legDifference,
        ),
        'legsFor' => b.standing.legsFor.compareTo(a.standing.legsFor),
        _ => 0,
      };

      if (comparison != 0) {
        return comparison;
      }
    }

    return 0;
  }

  int _compareBestOfCandidates(
    GroupTournamentRunStage stage,
    BestOfCandidate a,
    BestOfCandidate b,
  ) {
    final tieBreakerComparison = _compareBestOfTieBreakersOnly(stage, a, b);
    if (tieBreakerComparison != 0) {
      return tieBreakerComparison;
    }

    final deciderComparison = _compareBestOfDeciders(stage, a, b);
    if (deciderComparison != 0) {
      return deciderComparison;
    }

    final groupCompare = a.groupNumber.compareTo(b.groupNumber);
    if (groupCompare != 0) {
      return groupCompare;
    }
    return a.standing.player.name.compareTo(b.standing.player.name);
  }

  int _compareBestOfDeciders(
    GroupTournamentRunStage stage,
    BestOfCandidate a,
    BestOfCandidate b,
  ) {
    for (final group in stage.groups) {
      for (final match in group.matches.where(
        (match) =>
            match.isDecider &&
            match.label == 'Beste-N Decider' &&
            match.hasResult,
      )) {
        final home = match.homePlayer;
        final away = match.awayPlayer;
        if (home == null || away == null || match.winner == null) {
          continue;
        }
        final isDirectMatch =
            (home.name == a.standing.player.name &&
                away.name == b.standing.player.name) ||
            (home.name == b.standing.player.name &&
                away.name == a.standing.player.name);
        if (!isDirectMatch) {
          continue;
        }
        return match.winner!.name == a.standing.player.name ? -1 : 1;
      }
    }

    return 0;
  }

  void _addBestOfDeciderIfMissing(
    GroupTournamentRunStage stage,
    BestOfCandidate first,
    BestOfCandidate second,
  ) {
    final alreadyExists = stage.groups.any((group) {
      return group.matches.any((match) {
        if (!match.isDecider || match.label != 'Beste-N Decider') {
          return false;
        }
        final home = match.homePlayer;
        final away = match.awayPlayer;
        return (home == first.standing.player &&
                away == second.standing.player) ||
            (home == second.standing.player && away == first.standing.player);
      });
    });
    if (alreadyExists) {
      return;
    }

    final homeGroupIndex = first.groupNumber - 1;
    if (homeGroupIndex < 0 || homeGroupIndex >= stage.groups.length) {
      return;
    }

    final homeGroup = stage.groups[homeGroupIndex];
    homeGroup.matches.add(
      GroupMatch(
        homePlayer: first.standing.player,
        awayPlayer: second.standing.player,
        round: _nextDeciderRound(homeGroup),
        label: 'Beste-N Decider',
        isDecider: true,
      ),
    );
  }

  void _advanceDoubleEliminationRounds(
    List<List<GroupMatch>> rounds, {
    bool finalEndsTournament = false,
  }) {
    _repairDoubleEliminationRoundsIfNeeded(rounds);

    final winnersRoundCount = _doubleWinnersRoundCount(rounds);
    final losersRoundCount = _doubleLosersRoundCount(rounds);
    if (winnersRoundCount == 1 && losersRoundCount == 0) {
      final opening = rounds.first.single;
      final finalMatch = _matchesWithLabel(
        rounds,
        _doubleGrandFinalLabel,
      ).single;
      _setMatchPlayers(finalMatch, opening.winner, opening.loser);
      final resets = _matchesWithLabel(rounds, _doubleResetFinalLabel);
      if (!finalEndsTournament &&
          finalMatch.hasResult &&
          finalMatch.winner == finalMatch.awayPlayer) {
        if (resets.isEmpty) {
          rounds.add([
            GroupMatch(
              round: rounds.length + 1,
              label: _doubleResetFinalLabel,
              homePlayer: finalMatch.homePlayer,
              awayPlayer: finalMatch.awayPlayer,
            ),
          ]);
        } else {
          _setMatchPlayers(
            resets.single,
            finalMatch.homePlayer,
            finalMatch.awayPlayer,
          );
        }
      } else {
        rounds.removeWhere(
          (r) => r.isNotEmpty && r.first.label == _doubleResetFinalLabel,
        );
      }
      return;
    }
    if (winnersRoundCount == 0 || losersRoundCount == 0) {
      return;
    }

    for (var roundNumber = 1; roundNumber <= winnersRoundCount; roundNumber++) {
      final currentWinnersRound = _doubleWinnersRoundMatches(
        rounds,
        roundNumber,
        includeAutoAdvances: roundNumber == 1,
      );
      if (currentWinnersRound.isEmpty) {
        continue;
      }

      if (roundNumber < winnersRoundCount) {
        final nextWinnersRound = _doubleWinnersRoundMatches(
          rounds,
          roundNumber + 1,
        );
        _advancePairedWinners(currentWinnersRound, nextWinnersRound);
      }

      final targetLosersRoundNumber = roundNumber == 1
          ? 1
          : roundNumber == winnersRoundCount
          ? losersRoundCount
          : roundNumber * 2 - 2;
      final targetLosersRound = _matchesWithLabel(
        rounds,
        _doubleLosersLabel(targetLosersRoundNumber),
      );
      if (roundNumber == 1) {
        _dropFirstWinnersLosersToInitialLosersRound(
          currentWinnersRound,
          targetLosersRound,
        );
      } else {
        _dropWinnersLosersToLosersRound(currentWinnersRound, targetLosersRound);
      }
    }

    for (var roundNumber = 1; roundNumber < losersRoundCount; roundNumber++) {
      final currentLosersRound = _matchesWithLabel(
        rounds,
        _doubleLosersLabel(roundNumber),
      );
      final nextLosersRound = _matchesWithLabel(
        rounds,
        _doubleLosersLabel(roundNumber + 1),
      );
      if (currentLosersRound.isEmpty || nextLosersRound.isEmpty) {
        continue;
      }

      if (nextLosersRound.length == currentLosersRound.length) {
        for (var index = 0; index < currentLosersRound.length; index++) {
          _setMatchHomePlayer(
            nextLosersRound[index],
            currentLosersRound[index].winner,
          );
        }
      } else {
        _advancePairedWinners(currentLosersRound, nextLosersRound);
      }
    }

    final grandFinal = _matchesWithLabel(rounds, _doubleGrandFinalLabel);
    if (grandFinal.isEmpty) {
      return;
    }

    final winnersFinal = _matchesWithLabel(
      rounds,
      _doubleWinnersLabel(winnersRoundCount),
    );
    final losersFinal = _matchesWithLabel(
      rounds,
      _doubleLosersLabel(losersRoundCount),
    );
    _setMatchHomePlayer(
      grandFinal.first,
      winnersFinal.isEmpty ? null : winnersFinal.first.winner,
    );
    _setMatchAwayPlayer(
      grandFinal.first,
      losersFinal.isEmpty ? null : losersFinal.first.winner,
    );

    if (!finalEndsTournament &&
        grandFinal.first.hasResult &&
        grandFinal.first.winner == grandFinal.first.awayPlayer &&
        _matchesWithLabel(rounds, _doubleResetFinalLabel).isEmpty) {
      rounds.add([
        GroupMatch(
          round: rounds.length + 1,
          label: _doubleResetFinalLabel,
          homePlayer: grandFinal.first.homePlayer,
          awayPlayer: grandFinal.first.awayPlayer,
        ),
      ]);
    }
  }

  void _repairDoubleEliminationRoundsIfNeeded(List<List<GroupMatch>> rounds) {
    if (!_doubleEliminationRoundsNeedRepair(rounds)) {
      return;
    }

    final repairedRounds = _buildDoubleEliminationRoundsFromFirstRound(
      rounds.first,
    );
    rounds
      ..clear()
      ..addAll(repairedRounds);
  }

  void _advancePairedWinners(
    List<GroupMatch> currentRound,
    List<GroupMatch> nextRound,
  ) {
    for (var matchIndex = 0; matchIndex < currentRound.length; matchIndex++) {
      final winner = currentRound[matchIndex].winner;
      if (winner == null || nextRound.isEmpty) {
        continue;
      }

      final targetIndex = matchIndex ~/ 2;
      if (targetIndex >= nextRound.length) {
        continue;
      }

      final targetMatch = nextRound[targetIndex];
      if (matchIndex.isEven) {
        _setMatchHomePlayer(targetMatch, winner);
      } else {
        _setMatchAwayPlayer(targetMatch, winner);
      }
    }
  }

  void _dropFirstWinnersLosersToInitialLosersRound(
    List<GroupMatch> winnersRound,
    List<GroupMatch> losersRound,
  ) {
    final losers = <TournamentPlayer>[];
    for (final match in winnersRound) {
      final loser = match.loser;
      if (loser == null || losers.any((entry) => entry.name == loser.name)) {
        continue;
      }
      losers.add(loser);
    }

    final slots = List<TournamentPlayer?>.filled(losersRound.length * 2, null);
    for (var index = 0; index < losers.length; index++) {
      var slot = ((index * losersRound.length) ~/ losers.length) * 2;
      while (slot < slots.length && slots[slot] != null) {
        slot++;
      }
      if (slot < slots.length) slots[slot] = losers[index];
    }
    for (var i = 0; i < losersRound.length; i++) {
      _setMatchPlayers(losersRound[i], slots[i * 2], slots[i * 2 + 1]);
    }
  }

  void _dropWinnersLosersToLosersRound(
    List<GroupMatch> winnersRound,
    List<GroupMatch> losersRound,
  ) {
    for (var matchIndex = 0; matchIndex < winnersRound.length; matchIndex++) {
      final loser = winnersRound[matchIndex].loser;
      if (loser == null || matchIndex >= losersRound.length) {
        continue;
      }
      _setMatchAwayPlayer(losersRound[matchIndex], loser);
    }
  }

  void _setMatchHomePlayer(GroupMatch match, TournamentPlayer? player) {
    if (match.homePlayer != player) {
      match.homeLegs = null;
      match.homeSets = null;
      match.awaySets = null;
      match.awayLegs = null;
      match.isAnnulled = false;
    }
    match.homePlayer = player;
  }

  void _setMatchAwayPlayer(GroupMatch match, TournamentPlayer? player) {
    if (match.awayPlayer != player) {
      match.homeLegs = null;
      match.homeSets = null;
      match.awaySets = null;
      match.awayLegs = null;
      match.isAnnulled = false;
    }
    match.awayPlayer = player;
  }

  List<TournamentPlayer> _playersInEliminationRounds(
    List<List<GroupMatch>> rounds,
  ) {
    final players = <TournamentPlayer>[];
    void add(TournamentPlayer? player) {
      if (player == null || players.any((entry) => entry.name == player.name)) {
        return;
      }
      players.add(player);
    }

    for (final round in rounds) {
      for (final match in round) {
        add(match.homePlayer);
        add(match.awayPlayer);
      }
    }

    return players;
  }

  Map<String, int> _lossCountsForElimination(List<List<GroupMatch>> rounds) {
    final losses = <String, int>{};
    for (final player in _playersInEliminationRounds(rounds)) {
      losses[player.name] = 0;
    }

    for (final round in rounds) {
      for (final match in round.where((match) => match.hasResult)) {
        final loser = match.loser;
        if (loser != null) {
          losses[loser.name] = (losses[loser.name] ?? 0) + 1;
        }
      }
    }

    return losses;
  }

  List<TournamentPlayer> _activeEliminationPlayers(
    List<List<GroupMatch>> rounds,
    int lossLimit,
  ) {
    final losses = _lossCountsForElimination(rounds);
    return [
      for (final player in _playersInEliminationRounds(rounds))
        if ((losses[player.name] ?? 0) < lossLimit) player,
    ];
  }

  void _ensureDecidersForGroup(
    GroupTournamentRunStage stage,
    TournamentGroup group,
    int groupIndex,
  ) {
    final regularMatches = group.matches
        .where((match) => !match.isDecider)
        .toList();
    if (regularMatches.any((match) => match.hasPlayers && !match.isResolved)) {
      return;
    }

    final standings = _standingsFor(group, stage.tieBreakers);
    final relevantPlaces = _relevantPlacesForDeciders(stage, groupIndex);
    if (relevantPlaces.isEmpty) {
      return;
    }

    for (final place in relevantPlaces) {
      final index = place - 1;
      if (index < 0 || index >= standings.length) {
        continue;
      }

      final tied = <PlayerStanding>[standings[index]];
      for (var above = index - 1; above >= 0; above--) {
        if (_compareTieBreakersOnly(
              standings[index],
              standings[above],
              stage.tieBreakers,
              group.matches,
            ) !=
            0) {
          break;
        }
        tied.add(standings[above]);
      }
      for (var below = index + 1; below < standings.length; below++) {
        if (_compareTieBreakersOnly(
              standings[index],
              standings[below],
              stage.tieBreakers,
              group.matches,
            ) !=
            0) {
          break;
        }
        tied.add(standings[below]);
      }

      if (tied.length < 2) {
        continue;
      }

      for (var first = 0; first < tied.length; first++) {
        for (var second = first + 1; second < tied.length; second++) {
          _addDeciderIfMissing(group, tied[first].player, tied[second].player);
        }
      }
    }
  }

  Set<int> _relevantPlacesForDeciders(
    GroupTournamentRunStage stage,
    int groupIndex,
  ) {
    final plan = stage.qualificationPlan;
    if (plan == null) {
      return const {};
    }

    final fixedForGroup = groupIndex < plan.fixedByGroup.length
        ? plan.fixedByGroup[groupIndex]
        : plan.fixedPerGroup;
    final groupNumber = groupIndex + 1;
    return {
      for (var place = 1; place <= fixedForGroup; place++) place,
      if (plan.extraGroups.contains(groupNumber)) plan.extraRank,
    };
  }

  int _compareTieBreakersOnly(
    PlayerStanding a,
    PlayerStanding b,
    List<String> tieBreakers,
    List<GroupMatch> matches,
  ) {
    for (final tieBreaker in tieBreakers) {
      final comparison = switch (tieBreaker) {
        'points' => b.points.compareTo(a.points),
        'legDifference' => b.legDifference.compareTo(a.legDifference),
        'legsFor' => b.legsFor.compareTo(a.legsFor),
        'headToHead' => _compareHeadToHead(a, b, matches),
        _ => 0,
      };

      if (comparison != 0) {
        return comparison;
      }
    }

    return 0;
  }

  void _addDeciderIfMissing(
    TournamentGroup group,
    TournamentPlayer first,
    TournamentPlayer second,
  ) {
    final alreadyExists = group.matches.any((match) {
      if (!match.isDecider) {
        return false;
      }
      final home = match.homePlayer;
      final away = match.awayPlayer;
      return (home == first && away == second) ||
          (home == second && away == first);
    });
    if (alreadyExists) {
      return;
    }

    group.matches.add(
      GroupMatch(
        homePlayer: first,
        awayPlayer: second,
        round: _nextDeciderRound(group),
        label: 'Decider',
        isDecider: true,
      ),
    );
  }

  int _nextDeciderRound(TournamentGroup group) {
    final highestRound = group.matches.fold<int>(
      0,
      (highest, match) => match.round > highest ? match.round : highest,
    );
    return highestRound + 1;
  }

  void _advancePlacementMatches(
    List<List<GroupMatch>> rounds,
    List<GroupMatch> placementMatches,
  ) {
    if (placementMatches.any((m) => m.placementKey != null)) {
      PlacementEngine.advance(rounds, placementMatches);
      return;
    }
    if (rounds.length >= 2 && placementMatches.isNotEmpty) {
      final semifinalRound = rounds.last.length >= 2
          ? rounds.last
          : rounds[rounds.length - 2];
      final semifinalLosers = semifinalRound
          .map((match) => match.loser)
          .whereType<TournamentPlayer>()
          .toList();
      final thirdPlaceMatches = placementMatches
          .where((match) => match.label == 'Spiel um Platz 3')
          .toList();
      final thirdPlaceMatch = thirdPlaceMatches.isEmpty
          ? null
          : thirdPlaceMatches.first;
      if (thirdPlaceMatch != null && semifinalLosers.length >= 2) {
        _setMatchPlayers(
          thirdPlaceMatch,
          semifinalLosers[0],
          semifinalLosers[1],
        );
      }
    }

    final fifthSemis = placementMatches
        .where(
          (match) => match.label?.startsWith('Platz 5 Halbfinale') ?? false,
        )
        .toList();
    if (fifthSemis.isNotEmpty) {
      final quarterfinalRound = rounds.last.length >= 4
          ? rounds.last
          : rounds.length >= 3
          ? rounds[rounds.length - 3]
          : const <GroupMatch>[];
      final quarterfinalLosers = quarterfinalRound
          .map((match) => match.loser)
          .whereType<TournamentPlayer>()
          .toList();
      if (quarterfinalLosers.length >= 4 && fifthSemis.length >= 2) {
        _setMatchPlayers(
          fifthSemis[0],
          quarterfinalLosers[0],
          quarterfinalLosers[1],
        );
        _setMatchPlayers(
          fifthSemis[1],
          quarterfinalLosers[2],
          quarterfinalLosers[3],
        );
      }

      final fifthFinalMatches = placementMatches
          .where((match) => match.label == 'Spiel um Platz 5')
          .toList();
      final fifthFinal = fifthFinalMatches.isEmpty
          ? null
          : fifthFinalMatches.first;
      if (fifthFinal != null && fifthSemis.length >= 2) {
        _setMatchPlayers(
          fifthFinal,
          fifthSemis[0].winner,
          fifthSemis[1].winner,
        );
      }

      final seventhPlaceMatches = placementMatches
          .where((match) => match.label == 'Spiel um Platz 7')
          .toList();
      if (seventhPlaceMatches.isNotEmpty && fifthSemis.length >= 2) {
        _setMatchPlayers(
          seventhPlaceMatches.first,
          fifthSemis[0].loser,
          fifthSemis[1].loser,
        );
      }
    }
  }

  void _setMatchPlayers(
    GroupMatch match,
    TournamentPlayer? homePlayer,
    TournamentPlayer? awayPlayer,
  ) {
    if (match.homePlayer != homePlayer || match.awayPlayer != awayPlayer) {
      match.homeLegs = null;
      match.homeSets = null;
      match.awaySets = null;
      match.awayLegs = null;
      match.isAnnulled = false;
    }
    match.homePlayer = homePlayer;
    match.awayPlayer = awayPlayer;
  }

  List<PlayerStanding> _standingsFor(
    TournamentGroup group,
    List<String> tieBreakers,
  ) {
    if (group.playType == 'swiss') {
      final rows = SwissEngine.standings(group);
      return [
        ...rows.where(
          (s) =>
              PlayerWithdrawalService.policy(widget.tournament, s.player) ==
              null,
        ),
        ...rows.where(
          (s) =>
              PlayerWithdrawalService.policy(widget.tournament, s.player) !=
              null,
        ),
      ];
    }
    final standings = {
      for (final player in group.players) player.name: PlayerStanding(player),
    };

    for (final match in group.matches.where(
      (match) => match.countsForStatistics && !match.isDecider,
    )) {
      final homePlayer = match.homePlayer!;
      final awayPlayer = match.awayPlayer!;
      final home = standings[homePlayer.name]!;
      final away = standings[awayPlayer.name]!;
      final homeLegs = match.homeLegs!;
      final awayLegs = match.awayLegs!;

      home.played++;
      home.legsFor += homeLegs;
      home.legsAgainst += awayLegs;
      away.played++;
      away.legsFor += awayLegs;
      away.legsAgainst += homeLegs;

      if (match.winner == match.homePlayer) {
        home.wins++;
        home.points += 3;
        away.losses++;
      } else if (match.winner == match.awayPlayer) {
        away.wins++;
        away.points += 3;
        home.losses++;
      } else {
        home.draws++;
        home.points++;
        away.draws++;
        away.points++;
      }
    }

    final sorted = standings.values.toList();
    sorted.sort((a, b) {
      final withdrawn =
          (PlayerWithdrawalService.policy(widget.tournament, a.player) == null
                  ? 0
                  : 1)
              .compareTo(
                PlayerWithdrawalService.policy(widget.tournament, b.player) ==
                        null
                    ? 0
                    : 1,
              );
      if (withdrawn != 0) return withdrawn;
      final comparison = _compareStandings(
        a,
        b,
        tieBreakers,
        matches: group.matches,
      );
      if (comparison != 0) {
        return comparison;
      }
      return a.player.name.compareTo(b.player.name);
    });

    return sorted;
  }

  int _compareStandings(
    PlayerStanding a,
    PlayerStanding b,
    List<String> tieBreakers, {
    List<GroupMatch> matches = const [],
  }) {
    for (final tieBreaker in tieBreakers) {
      final comparison = switch (tieBreaker) {
        'points' => b.points.compareTo(a.points),
        'legDifference' => b.legDifference.compareTo(a.legDifference),
        'legsFor' => b.legsFor.compareTo(a.legsFor),
        'headToHead' => _compareHeadToHead(a, b, matches),
        _ => 0,
      };

      if (comparison != 0) {
        return comparison;
      }
    }

    return _compareDecider(a, b, matches);
  }

  int _compareDecider(
    PlayerStanding a,
    PlayerStanding b,
    List<GroupMatch> matches,
  ) {
    for (final match in matches.where(
      (match) => match.isDecider && match.hasResult,
    )) {
      final home = match.homePlayer!;
      final away = match.awayPlayer!;
      final isDirectMatch =
          (home.name == a.player.name && away.name == b.player.name) ||
          (home.name == b.player.name && away.name == a.player.name);
      if (!isDirectMatch || match.winner == null) {
        continue;
      }
      return match.winner!.name == a.player.name ? -1 : 1;
    }

    return 0;
  }

  int _compareHeadToHead(
    PlayerStanding a,
    PlayerStanding b,
    List<GroupMatch> matches,
  ) {
    var aPoints = 0;
    var bPoints = 0;
    var aLegs = 0;
    var bLegs = 0;

    for (final match in matches.where(
      (match) => match.countsForStatistics && !match.isDecider,
    )) {
      final home = match.homePlayer!;
      final away = match.awayPlayer!;
      final isDirectMatch =
          (home.name == a.player.name && away.name == b.player.name) ||
          (home.name == b.player.name && away.name == a.player.name);
      if (!isDirectMatch) {
        continue;
      }

      final aIsHome = home.name == a.player.name;
      final aMatchLegs = aIsHome ? match.homeLegs! : match.awayLegs!;
      final bMatchLegs = aIsHome ? match.awayLegs! : match.homeLegs!;
      aLegs += aMatchLegs;
      bLegs += bMatchLegs;

      if (match.winner?.name == a.player.name) {
        aPoints += 3;
      } else if (match.winner?.name == b.player.name) {
        bPoints += 3;
      } else {
        aPoints++;
        bPoints++;
      }
    }

    final pointCompare = bPoints.compareTo(aPoints);
    if (pointCompare != 0) return pointCompare;
    final diffCompare = (bLegs - aLegs).compareTo(aLegs - bLegs);
    if (diffCompare != 0) return diffCompare;
    return bLegs.compareTo(aLegs);
  }

  bool _stageHasOpenMatches(TournamentRunStage stage) {
    if (stage is KnockoutTournamentRunStage) {
      return !_knockoutHasWinner(stage) ||
          _hasOpenPlacementMatches(stage.placementMatches);
    }
    if (stage is GroupTournamentRunStage) {
      return stage.groups.any((group) {
        if (_isEliminationGroupPlayType(group.playType)) {
          final groupIndex = stage.groups.indexOf(group);
          return !_eliminationGroupQualifiersKnown(stage, group, groupIndex);
        }

        return group.matches.any((match) => !match.isResolved);
      });
    }

    return _matchesForStage(stage).any((match) => !match.isResolved);
  }

  bool _hasOpenPlacementMatches(List<GroupMatch> matches) {
    return matches.any((match) => match.hasPlayers && !match.isResolved);
  }

  bool _knockoutHasWinner(KnockoutTournamentRunStage stage) {
    if (stage.finalEndsTournament &&
        stage.rounds.isNotEmpty &&
        stage.rounds.last.length == 1 &&
        stage.rounds.last.single.hasResult &&
        (stage.rounds.last.single.label == _doubleGrandFinalLabel ||
            stage.rounds.last.single.label == _tripleFinalLabel)) {
      return true;
    }
    if (stage.eliminationLossLimit > 1) {
      return stage.rounds.isNotEmpty &&
          stage.rounds.last.every((match) => match.isResolved) &&
          _activeEliminationPlayers(
                stage.rounds,
                stage.eliminationLossLimit,
              ).length <=
              1;
    }

    return stage.rounds.isNotEmpty &&
        stage.rounds.last.length == 1 &&
        stage.rounds.last.first.winner != null;
  }

  bool _eliminationGroupQualifiersKnown(
    GroupTournamentRunStage stage,
    TournamentGroup group,
    int groupIndex,
  ) {
    final requiredRank = _requiredRankForGroupStage(stage, groupIndex);
    if (group.placementMatches.any((m) => m.placementKey != null)) {
      return group.knockoutRounds.isNotEmpty &&
          group.knockoutRounds.last.single.isResolved &&
          !_hasOpenPlacementMatches(group.placementMatches);
    }
    if (requiredRank >= group.players.length) {
      return true;
    }
    if (group.knockoutRounds.isEmpty) {
      return false;
    }

    if (_hasOpenPlacementMatches(group.placementMatches)) return false;
    if (group.eliminationLossLimit > 1) {
      if (group.finalEndsTournament &&
          group.knockoutRounds.last.length == 1 &&
          group.knockoutRounds.last.single.hasResult &&
          (group.knockoutRounds.last.single.label == _doubleGrandFinalLabel ||
              group.knockoutRounds.last.single.label == _tripleFinalLabel)) {
        return true;
      }
      return _activeEliminationPlayers(
            group.knockoutRounds,
            group.eliminationLossLimit,
          ).length <=
          requiredRank;
    }

    return group.knockoutRounds.last.every((match) => match.isResolved) &&
        !_hasOpenPlacementMatches(group.placementMatches);
  }

  int _requiredRankForGroupStage(
    GroupTournamentRunStage stage,
    int groupIndex,
  ) {
    final plan = stage.qualificationPlan;
    if (plan == null) {
      return 1;
    }

    final fixedForGroup =
        groupIndex >= 0 && groupIndex < plan.fixedByGroup.length
        ? plan.fixedByGroup[groupIndex]
        : plan.fixedPerGroup;
    final groupNumber = groupIndex + 1;
    final extraRank = plan.extraGroups.contains(groupNumber)
        ? plan.extraRank
        : 0;
    final requiredRank = fixedForGroup > extraRank ? fixedForGroup : extraRank;
    return requiredRank < 1 ? 1 : requiredRank;
  }

  List<GroupMatch> _matchesForStage(TournamentRunStage stage) {
    if (stage is GroupTournamentRunStage) {
      return [for (final group in stage.groups) ...group.matches];
    }
    if (stage is KnockoutTournamentRunStage) {
      return stage.matches;
    }

    return const [];
  }

  int _requiredRankForRunStage(int stageIndex) {
    if (stageIndex >= widget.tournament.stages.length - 1) {
      return 1;
    }

    final stage = widget.tournament.runStages[stageIndex];
    final availablePlayers = _participantCountForRunStage(stage);
    final nextStage = widget.tournament.stages[stageIndex + 1];
    final requiredPlayers = nextStage.type == 'groups'
        ? nextStage.groupSizes.fold<int>(0, (sum, size) => sum + size)
        : nextStage.knockoutParticipantCount ?? availablePlayers;
    return requiredPlayers.clamp(1, availablePlayers).toInt();
  }

  int _participantCountForRunStage(TournamentRunStage stage) {
    if (stage is KnockoutTournamentRunStage) {
      if (stage.rounds.isEmpty) {
        return 0;
      }
      return stage.rounds.first.fold<int>(
        0,
        (sum, match) =>
            sum +
            (match.homePlayer == null ? 0 : 1) +
            (match.awayPlayer == null ? 0 : 1),
      );
    }
    if (stage is GroupTournamentRunStage) {
      return stage.groups.fold<int>(
        0,
        (sum, group) => sum + group.players.length,
      );
    }
    return 0;
  }

  List<TournamentPlayer> _advancingPlayersFromStage(TournamentRunStage stage) {
    return _advancingPlayersIncludingWithdrawn(stage)
        .where(
          (p) => PlayerWithdrawalService.policy(widget.tournament, p) == null,
        )
        .toList();
  }

  List<TournamentPlayer> _advancingPlayersIncludingWithdrawn(
    TournamentRunStage stage,
  ) {
    if (stage is GroupTournamentRunStage) {
      return _advancingPlayersFromGroupStage(stage);
    }

    if (stage is KnockoutTournamentRunStage) {
      if (stage.eliminationLossLimit > 1) {
        return _multiEliminationRanking(
          stage.rounds,
          stage.eliminationLossLimit,
          fallbackPlayers: const [],
          finalEndsTournament: stage.finalEndsTournament,
        );
      }
      return _knockoutRanking(
        stage.rounds,
        stage.placementMatches,
        fallbackPlayers: const [],
      );
    }

    return const [];
  }

  TournamentRunStage _stageForView(int stageIndex) {
    if (stageIndex <= _activeStageIndex) {
      return widget.tournament.runStages[stageIndex];
    }

    final sourceStage = widget.tournament.runStages[_activeStageIndex];
    var incomingPlayers = const GroupStagePreviewService()
        .presentProjectedPlayers(
          stage: sourceStage,
          projectedPlayers: _advancingPlayersFromStage(sourceStage),
          tournament: widget.tournament,
        );
    late TournamentRunStage previewStage;

    for (
      var index = _activeStageIndex + 1;
      index <= stageIndex && index < widget.tournament.stages.length;
      index++
    ) {
      previewStage = _buildRunStageFromPlayers(
        widget.tournament.stages[index],
        incomingPlayers,
      );
      if (index < stageIndex) {
        incomingPlayers = _advancingPlayersFromStage(previewStage);
      }
    }

    return previewStage;
  }

  List<TournamentPlayer> _advancingPlayersFromGroupStage(
    GroupTournamentRunStage stage,
  ) {
    if (stage.groups.any(
      (group) => _isEliminationGroupPlayType(group.playType),
    )) {
      return _advancingPlayersFromMixedGroups(stage);
    }

    final plan = stage.qualificationPlan;
    if (plan == null) {
      return [
        for (final group in stage.groups)
          for (final standing in _standingsFor(group, stage.tieBreakers))
            standing.player,
      ];
    }

    final advancingPlayers = <TournamentPlayer>[];
    final extraCandidates = <BestOfCandidate>[];

    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final groupNumber = groupIndex + 1;
      final standings = _standingsFor(
        stage.groups[groupIndex],
        stage.tieBreakers,
      );

      final fixedForGroup = groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      advancingPlayers.addAll(
        standings.take(fixedForGroup).map((standing) => standing.player),
      );

      final extraIndex = plan.extraRank - 1;
      if (plan.extraGroups.contains(groupNumber) &&
          extraIndex >= 0 &&
          extraIndex < standings.length) {
        extraCandidates.add(
          BestOfCandidate(
            groupName: stage.groups[groupIndex].name,
            groupNumber: groupNumber,
            place: plan.extraRank,
            standing: standings[extraIndex],
          ),
        );
      }
    }

    extraCandidates.sort((a, b) => _compareBestOfCandidates(stage, a, b));
    advancingPlayers.addAll(
      extraCandidates
          .take(plan.extraCount)
          .map((candidate) => candidate.standing.player),
    );

    return advancingPlayers;
  }

  List<TournamentPlayer> _advancingPlayersFromMixedGroups(
    GroupTournamentRunStage stage,
  ) {
    final plan = stage.qualificationPlan;
    if (plan == null) {
      return [
        for (final group in stage.groups)
          ..._orderedPlayersForGroup(stage, group),
      ];
    }

    final advancingPlayers = <TournamentPlayer>[];
    final extraCandidates = <TournamentPlayer>[];

    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final groupNumber = groupIndex + 1;
      final ranking = _orderedPlayersForGroup(stage, stage.groups[groupIndex]);

      final fixedForGroup = groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      advancingPlayers.addAll(ranking.take(fixedForGroup));

      final extraIndex = plan.extraRank - 1;
      if (plan.extraGroups.contains(groupNumber) &&
          extraIndex >= 0 &&
          extraIndex < ranking.length) {
        extraCandidates.add(ranking[extraIndex]);
      }
    }

    advancingPlayers.addAll(extraCandidates.take(plan.extraCount));
    return advancingPlayers;
  }

  List<TournamentPlayer> _orderedPlayersForGroup(
    GroupTournamentRunStage stage,
    TournamentGroup group,
  ) {
    if (_isEliminationGroupPlayType(group.playType)) {
      return _miniKnockoutRankingForGroup(group);
    }

    return _standingsFor(
      group,
      stage.tieBreakers,
    ).map((standing) => standing.player).toList();
  }

  List<TournamentPlayer> _miniKnockoutRankingForGroup(TournamentGroup group) {
    if (group.eliminationLossLimit > 1) {
      return _multiEliminationRanking(
        group.knockoutRounds,
        group.eliminationLossLimit,
        fallbackPlayers: group.players,
        finalEndsTournament: group.finalEndsTournament,
      );
    }

    return _knockoutRanking(
      group.knockoutRounds,
      group.placementMatches,
      fallbackPlayers: group.players,
    );
  }

  List<TournamentPlayer> _multiEliminationRanking(
    List<List<GroupMatch>> rounds,
    int lossLimit, {
    bool finalEndsTournament = false,
    required List<TournamentPlayer> fallbackPlayers,
  }) {
    final players = _playersInEliminationRounds(rounds);
    final losses = _lossCountsForElimination(rounds);
    final lastResolvedRound = <String, int>{};
    for (final round in rounds) {
      for (final match in round.where((match) => match.hasResult)) {
        final loser = match.loser;
        final winner = match.winner;
        if (loser != null) {
          lastResolvedRound[loser.name] = match.round;
        }
        if (winner != null) {
          lastResolvedRound[winner.name] = match.round;
        }
      }
    }

    final ranked = [...players];
    ranked.sort((a, b) {
      if (finalEndsTournament &&
          rounds.isNotEmpty &&
          rounds.last.length == 1 &&
          rounds.last.single.hasResult &&
          (rounds.last.single.label == _doubleGrandFinalLabel ||
              rounds.last.single.label == _tripleFinalLabel)) {
        final finalMatch = rounds.last.single;
        if (a.name == finalMatch.winner?.name) return -1;
        if (b.name == finalMatch.winner?.name) return 1;
        if (a.name == finalMatch.loser?.name) return -1;
        if (b.name == finalMatch.loser?.name) return 1;
      }
      final aLosses = losses[a.name] ?? 0;
      final bLosses = losses[b.name] ?? 0;
      final lossCompare = aLosses.compareTo(bLosses);
      if (lossCompare != 0) {
        return lossCompare;
      }

      final roundCompare = (lastResolvedRound[b.name] ?? 0).compareTo(
        lastResolvedRound[a.name] ?? 0,
      );
      if (roundCompare != 0) {
        return roundCompare;
      }

      return a.name.compareTo(b.name);
    });

    for (final player in fallbackPlayers) {
      if (!ranked.any((entry) => entry.name == player.name)) {
        ranked.add(player);
      }
    }

    return ranked;
  }

  List<TournamentPlayer> _knockoutRanking(
    List<List<GroupMatch>> rounds,
    List<GroupMatch> placementMatches, {
    required List<TournamentPlayer> fallbackPlayers,
  }) {
    final rankedPlayers = <TournamentPlayer>[];

    void addPlayer(TournamentPlayer? player) {
      if (player == null) {
        return;
      }
      if (rankedPlayers.any((ranked) => ranked.name == player.name)) {
        return;
      }
      rankedPlayers.add(player);
    }

    if (rounds.isNotEmpty) {
      final isTruncatedQualificationRound = rounds.last.length > 1;
      if (isTruncatedQualificationRound) {
        for (final match in rounds.last) {
          addPlayer(match.winner);
        }
      } else {
        addPlayer(rounds.last.first.winner);
        addPlayer(rounds.last.first.loser);
      }

      final thirdPlaceMatches = placementMatches
          .where((match) => match.label == 'Spiel um Platz 3')
          .toList();
      if (thirdPlaceMatches.isNotEmpty) {
        addPlayer(thirdPlaceMatches.first.winner);
        addPlayer(thirdPlaceMatches.first.loser);
      } else if (rounds.length >= 2) {
        for (final match in rounds[rounds.length - 2]) {
          addPlayer(match.loser);
        }
      }

      final fifthPlaceMatches = placementMatches
          .where((match) => match.label == 'Spiel um Platz 5')
          .toList();
      if (fifthPlaceMatches.isNotEmpty) {
        addPlayer(fifthPlaceMatches.first.winner);
        addPlayer(fifthPlaceMatches.first.loser);
      }

      final seventhPlaceMatches = placementMatches
          .where((match) => match.label == 'Spiel um Platz 7')
          .toList();
      if (seventhPlaceMatches.isNotEmpty) {
        addPlayer(seventhPlaceMatches.first.winner);
        addPlayer(seventhPlaceMatches.first.loser);
      }

      for (var roundIndex = rounds.length - 1; roundIndex >= 0; roundIndex--) {
        for (final match in rounds[roundIndex]) {
          addPlayer(match.loser);
        }
      }
    }

    for (final player in fallbackPlayers) {
      addPlayer(player);
    }

    return PlacementEngine.applyRanking(rankedPlayers, placementMatches);
  }

  TournamentRunStage _buildRunStageFromPlayers(
    TournamentStage stage,
    List<TournamentPlayer> players,
  ) {
    if (_isKnockoutStageType(stage.type)) {
      final participantCount = stage.knockoutParticipantCount == null
          ? players.length
          : stage.knockoutParticipantCount!.clamp(0, players.length).toInt();
      final participants = players.take(participantCount).toList();
      var slots = stage.knockoutSlotOrder;
      final stageIndex = widget.tournament.stages.indexOf(stage);
      if (stage.knockoutSeedingMode == 'cross' &&
          !stage.knockoutDrawOnStart &&
          stageIndex > 0 &&
          stageIndex - 1 < widget.tournament.runStages.length) {
        final source = widget.tournament.runStages[stageIndex - 1];
        if (source is GroupTournamentRunStage &&
            source.groups.every(
              (group) => !_isEliminationGroupPlayType(group.playType),
            )) {
          final candidates = <BestOfCandidate>[];
          for (var index = 0; index < source.groups.length; index++) {
            final standings = _standingsFor(
              source.groups[index],
              source.tieBreakers,
            );
            for (var place = 0; place < standings.length; place++) {
              candidates.add(
                BestOfCandidate(
                  groupName: source.groups[index].name,
                  groupNumber: index + 1,
                  place: place + 1,
                  standing: standings[place],
                ),
              );
            }
          }
          final defaultSlots = [
            for (final seed in _seedOrderForSize(
              _nextPowerOfTwo(participants.length),
            ))
              seed <= participants.length ? seed : null,
          ];
          slots = const GroupByeSeeding().assign(
            drawKey: '${widget.tournament.id}:group-byes:$stageIndex',
            slots: slots.isEmpty ? defaultSlots : slots,
            players: participants,
            candidates: candidates,
            tieBreakers: source.tieBreakers,
          );
        }
      }
      final lossLimit = stage.lossLimit;
      return KnockoutTournamentRunStage(
        name: stage.name,
        rounds: lossLimit == 1
            ? _buildKnockoutRoundsForPlayers(participants, slotOrder: slots)
            : lossLimit == 2
            ? _buildDoubleEliminationRoundsForPlayers(
                participants,
                slotOrder: slots,
              )
            : _buildTripleEliminationRoundsForPlayers(
                participants,
                lossLimit: lossLimit,
                slotOrder: slots,
              ),
        placementMatches: lossLimit == 1
            ? stage.placementPlaces.isEmpty
                  ? _buildPlacementMatchesForPlayers(participants.length, 1)
                  : PlacementEngine.build(
                      _buildKnockoutRoundsForPlayers(
                        participants,
                        slotOrder: slots,
                      ),
                      stage.placementPlaces.where(
                        (p) => p < participants.length,
                      ),
                    )
            : const [],
        eliminationLossLimit: lossLimit,
        finalEndsTournament: stage.finalEndsTournament,
      );
    }

    final groupParticipantCount = stage.groupSizes.fold<int>(
      0,
      (sum, size) => sum + size,
    );
    final groupPlayers = players.take(groupParticipantCount).toList();

    return GroupTournamentRunStage(
      name: stage.name,
      groupPlayType: stage.groupPlayType,
      groups: _buildTournamentGroupsForPlayers(
        stage,
        groupPlayers,
        requiredRankForGroup: _requiredRankForStageGroup,
      ),
      qualificationPlan: _qualificationPlanForStage(stage),
      tieBreakers: stage.groupTieBreakers,
    );
  }

  QualificationPlan? _qualificationPlanForStage(TournamentStage stage) {
    if (stage.groupSizes.isEmpty || stage.qualifiedParticipantCount == null) {
      return null;
    }

    final groupCount = stage.groupSizes.length;
    final maxQualifiers = stage.groupSizes.fold<int>(
      0,
      (sum, size) => sum + size,
    );
    final totalQualifiers = stage.qualifiedParticipantCount! > maxQualifiers
        ? maxQualifiers
        : stage.qualifiedParticipantCount!;
    final fixedPerGroup = totalQualifiers ~/ groupCount;
    final fixedByGroup = stage.fixedQualifiersByGroup.length == groupCount
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
    final fixedTotal = fixedByGroup.fold<int>(0, (sum, value) => sum + value);
    final automaticExtraCount = (totalQualifiers - fixedTotal)
        .clamp(0, groupCount)
        .toInt();
    final extraCount = stage.qualificationAutoAdjust
        ? automaticExtraCount
        : (stage.extraQualifierCount ?? automaticExtraCount)
              .clamp(0, groupCount)
              .toInt();
    final extraRank = stage.extraQualifierRank ?? fixedPerGroup + 1;
    final extraGroups = extraCount == 0
        ? const <int>[]
        : stage.qualifiersByGroup.isNotEmpty
        ? stage.qualifiersByGroup
        : [
            for (var index = 0; index < stage.groupSizes.length; index++)
              if (stage.groupSizes[index] >= extraRank) index + 1,
          ];
    final eligibleGroupSize = extraCount == 0
        ? null
        : stage.groupSizes
              .where((size) => size >= extraRank)
              .fold<int>(0, (largest, size) => size > largest ? size : largest);

    return QualificationPlan(
      totalQualifiers: totalQualifiers,
      fixedPerGroup: fixedPerGroup,
      extraCount: extraCount,
      extraRank: extraRank,
      eligibleGroupSize: eligibleGroupSize,
      extraGroups: extraGroups,
      fixedByGroup: fixedByGroup,
    );
  }

  int _requiredRankForStageGroup(TournamentStage stage, int groupIndex) {
    final plan = _qualificationPlanForStage(stage);
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

  Future<void> _applyPendingStartDrawForActiveStage() async {
    if (!mounted ||
        _isApplyingStartDraw ||
        _activeStageIndex >= widget.tournament.stages.length ||
        _activeStageIndex >= widget.tournament.runStages.length) {
      return;
    }

    final stageConfig = widget.tournament.stages[_activeStageIndex];
    if (!_stageNeedsStartDraw(stageConfig)) {
      return;
    }

    final runStage = widget.tournament.runStages[_activeStageIndex];
    if (_matchesForStage(runStage).any((match) => match.hasResult)) {
      return;
    }

    final incomingPlayers = _incomingPlayersForStage(_activeStageIndex);
    final participantCount = _drawParticipantCount(
      stageConfig,
      incomingPlayers,
    );
    if (participantCount < 2) {
      return;
    }

    _isApplyingStartDraw = true;
    final labels = incomingPlayers
        .take(participantCount)
        .map((player) => player.name)
        .toList();
    final slotOrder = await showDialog<List<int?>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RandomDrawDialog(
        stageName: stageConfig.name,
        participantLabels: labels,
        bracketSize: stageConfig.type == 'groups'
            ? participantCount
            : _drawBracketSize(stageConfig, participantCount),
        useBracketSlots: stageConfig.type != 'groups',
        groupSizes: stageConfig.type == 'groups'
            ? stageConfig.groupSizes
            : const [],
      ),
    );
    _isApplyingStartDraw = false;

    if (!mounted || slotOrder == null) {
      return;
    }

    setState(() {
      final updatedStage = _copyStageWithStartDraw(stageConfig, slotOrder);
      widget.tournament.stages[_activeStageIndex] = updatedStage;
      widget.tournament.runStages[_activeStageIndex] =
          _buildRunStageFromPlayers(updatedStage, incomingPlayers);
      _advanceKnockoutWinners();
      _ensureGroupDeciders();
    });
    await _saveTournamentProgress();
  }

  bool _stageNeedsStartDraw(TournamentStage stage) {
    if (stage.type == 'groups') {
      return stage.groupDrawOnStart &&
          !stage.groupDrawCompleted &&
          stage.groupSlotOrder.isEmpty;
    }

    return _isKnockoutStageType(stage.type) &&
        stage.knockoutSeedingMode == 'random' &&
        stage.knockoutDrawOnStart &&
        stage.knockoutSlotOrder.isEmpty;
  }

  List<TournamentPlayer> _incomingPlayersForStage(int stageIndex) {
    if (stageIndex <= 0) {
      return List<TournamentPlayer>.from(widget.tournament.players);
    }

    return _advancingPlayersFromStage(
      widget.tournament.runStages[stageIndex - 1],
    );
  }

  int _drawParticipantCount(
    TournamentStage stage,
    List<TournamentPlayer> incomingPlayers,
  ) {
    if (stage.type == 'groups') {
      final groupParticipantCount = stage.groupSizes.fold<int>(
        0,
        (sum, size) => sum + size,
      );
      return groupParticipantCount.clamp(0, incomingPlayers.length).toInt();
    }

    final participantCount =
        stage.knockoutParticipantCount ?? incomingPlayers.length;
    return participantCount.clamp(0, incomingPlayers.length).toInt();
  }

  int _drawBracketSize(TournamentStage stage, int participantCount) {
    final storedBracketSize = stage.knockoutBracketSize;
    if (storedBracketSize != null && storedBracketSize >= participantCount) {
      return storedBracketSize;
    }

    return _nextPowerOfTwo(participantCount);
  }

  TournamentStage _copyStageWithStartDraw(
    TournamentStage stage,
    List<int?> slotOrder,
  ) => stage.type == 'groups'
      ? stage.copyWith(
          groupSlotOrder: List.unmodifiable(slotOrder),
          groupDrawCompleted: true,
        )
      : stage.copyWith();

  Future<void> _completeCurrentStage() async {
    final nextStageIndex = _activeStageIndex + 1;
    final hasNextStage = nextStageIndex < widget.tournament.runStages.length;
    final completedStageIndex = _activeStageIndex;
    final previousViewStageIndex = _viewStageIndex;
    final wasReopenedForCorrections = widget.tournament.reopenedForCorrections;
    final advancingPlayers = hasNextStage
        ? _advancingPlayersFromStage(
            widget.tournament.runStages[_activeStageIndex],
          )
        : const <TournamentPlayer>[];

    setState(() {
      if (hasNextStage) {
        final nextStageConfig = widget.tournament.stages[nextStageIndex];
        widget.tournament.runStages[nextStageIndex] = _buildRunStageFromPlayers(
          nextStageConfig,
          advancingPlayers,
        );
      }

      _completedStageIndexes.add(_activeStageIndex);
      if (!hasNextStage) {
        widget.tournament.reopenedForCorrections = false;
      }
      if (hasNextStage) {
        _activeStageIndex++;
      }
      _viewStageIndex = _activeStageIndex;
    });
    _advanceKnockoutWinners();
    try {
      await _saveTournamentProgress(propagateError: true);
    } catch (_) {
      if (wasReopenedForCorrections && !hasNextStage) {
        setState(() {
          widget.tournament.reopenedForCorrections = true;
          widget.tournament.finishedAt = null;
          _completedStageIndexes.remove(completedStageIndex);
          widget.tournament.completedStageIndexes.remove(completedStageIndex);
          _viewStageIndex = previousViewStageIndex;
        });
      }
      rethrow;
    }
    if (!mounted) {
      return;
    }
    if (!hasNextStage) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TournamentResultsPage(tournament: widget.tournament),
        ),
      );
      return;
    }
    await _applyPendingStartDrawForActiveStage();
    await _saveTournamentProgress();
  }

  void _finishCurrentStageEarly() {
    setState(() {
      for (final match in _matchesForStage(
        widget.tournament.runStages[_activeStageIndex],
      )) {
        if (match.hasPlayers && !match.isResolved) {
          match.isAnnulled = true;
          match.homeLegs = null;
          match.homeSets = null;
          match.awaySets = null;
          match.awayLegs = null;
        }
      }
      _advanceKnockoutWinners();
    });
    _completeCurrentStage();
  }

  @override
  Widget build(BuildContext context) {
    return _buildAuthorized(context);
  }

  Widget _buildAuthorized(BuildContext context) {
    if (widget.tournament.leagueMatch != null) {
      return LeagueMatchPage(tournament: widget.tournament);
    }
    final activeStage = _stageForView(_viewStageIndex);
    final isViewingActiveStage =
        _stageViewMode == StageViewMode.director ||
        _viewStageIndex == _activeStageIndex;
    final canCompleteStage =
        isViewingActiveStage &&
        !_stageHasOpenMatches(widget.tournament.runStages[_activeStageIndex]);
    final isLastStage =
        _activeStageIndex == widget.tournament.runStages.length - 1;
    final canEditResults = isViewingActiveStage;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leaveTournament());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.tournament.name} (${_tournamentTypeLabel()})'),
          actions: [
            SportActionsMenu(
              label: 'Turnier',
              actions: [
                if (widget.tournament.finishedAt == null)
                  SportMenuAction(
                    label: 'Spieler aus Turnier entfernen',
                    icon: Icons.person_remove_outlined,
                    onTap: _withdrawPlayer,
                  ),
                SportMenuAction(
                  label: 'Turnierdaten exportieren',
                  icon: Icons.ios_share,
                  onTap: _exportTournament,
                ),
                SportMenuAction(
                  label: 'Hauptmenü',
                  icon: Icons.home_outlined,
                  onTap: () => _leaveTournament(home: true),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: CustomScrollView(
            key: ValueKey('stage-$_viewStageIndex-$_stageViewMode'),
            slivers: [
              SliverToBoxAdapter(
                child: TournamentRunHeader(
                  tournament: widget.tournament,
                  stageIndex: _viewStageIndex,
                  completedStages: _completedStageIndexes,
                  mode: _stageViewMode,
                  canLead: true,
                  onStageChanged: (index) => setState(() {
                    _viewStageIndex = index;
                    _isBracketEditMode = false;
                  }),
                  onModeChanged: (mode) =>
                      setState(() => _stageViewMode = mode),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.list(
                  children: [
                    if (!isViewingActiveStage &&
                        _viewStageIndex > _activeStageIndex &&
                        _stageViewMode != StageViewMode.orderOfPlay &&
                        _stageViewMode != StageViewMode.director)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Vorschau: Teilnehmer und Setzung stehen erst nach Abschluss der vorherigen Etappe fest.',
                        ),
                      ),
                    if (_stageViewMode == StageViewMode.dashboard ||
                        _stageViewMode == StageViewMode.director)
                      TournamentDirectorDashboard(
                        tournament: widget.tournament,
                        activeStage: _activeStageIndex,
                        saveError: _directorSaveError,
                        canOperate:
                            !_isApplyingStartDraw &&
                            !_completedStageIndexes.contains(
                              _activeStageIndex,
                            ) &&
                            !_stageNeedsStartDraw(
                              widget.tournament.stages[_activeStageIndex],
                            ),
                        onResult: _editResult,
                        onBlock: _toggleBoardBlock,
                        onChange: () async {
                          setState(() {});
                          await _saveTournamentProgress(propagateError: true);
                        },
                        onCompleteStage: _completeCurrentStage,
                        onFinishEarly: _finishCurrentStageEarly,
                        canCompleteStage: canCompleteStage,
                        isLastStage: isLastStage,
                      )
                    else if (_stageViewMode == StageViewMode.settings)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Turniereinstellungen',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final field = TextField(
                                        controller: _tournamentNameController,
                                        maxLength: 100,
                                        decoration: const InputDecoration(
                                          labelText: 'Turniername',
                                          border: OutlineInputBorder(),
                                          counterText: '',
                                        ),
                                        onSubmitted: (_) =>
                                            _saveTournamentName(),
                                      );
                                      final saveButton = FilledButton.icon(
                                        onPressed: _saveTournamentName,
                                        icon: const Icon(Icons.save_outlined),
                                        label: const Text('Namen speichern'),
                                      );
                                      if (constraints.maxWidth < 560) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            field,
                                            const SizedBox(height: 8),
                                            saveButton,
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(flex: 3, child: field),
                                          const SizedBox(width: 12),
                                          saveButton,
                                        ],
                                      );
                                    },
                                  ),
                                  const Divider(height: 28),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 1. Turnieruhr Steuerung
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.timer_outlined),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Turnieruhr',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _TournamentClockStatus(
                                    tournament: widget.tournament,
                                  ),
                                  const SizedBox(height: 12),
                                  if (widget.tournament.finishedAt == null)
                                    FilledButton.tonalIcon(
                                      onPressed: _toggleClockPause,
                                      icon: Icon(
                                        widget.tournament.isClockPaused
                                            ? Icons.play_circle_outline
                                            : Icons.pause_circle_outline,
                                      ),
                                      label: Text(
                                        widget.tournament.isClockPaused
                                            ? 'Turnieruhr fortsetzen'
                                            : 'Turnieruhr pausieren',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 2. 2-Monitor-Modus
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.tv),
                                      const SizedBox(width: 8),
                                      Text(
                                        '2. Bildschirm (TV-Anzeige)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Für den Vereinsheim-TV oder Beamer: Zeigt Tabellen, Spielansetzungen, '
                                    'Ergebnisse und Turnieruhr automatisch rotierend im Vollbild an. '
                                    'So können Ergebnisse am Laptop eingetragen werden, ohne die Anzeige zu stören.',
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () async {
                                          try {
                                            await Process.start(
                                              Platform.resolvedExecutable,
                                              [
                                                '--second-screen',
                                                widget.tournament.id,
                                                '--parent-pid=$pid',
                                              ],
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'TV-Anzeige im separaten Fenster geöffnet. Ziehe das Fenster auf den 2. Monitor und maximiere es.',
                                                  ),
                                                ),
                                              );
                                            }
                                          } catch (_) {
                                            if (context.mounted) {
                                              showDialog<void>(
                                                context: context,
                                                builder: (ctx) => Dialog.fullscreen(
                                                  child:
                                                      TournamentSecondScreenView(
                                                        tournament:
                                                            widget.tournament,
                                                        isStandaloneWindow:
                                                            true,
                                                      ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.open_in_new),
                                        label: const Text(
                                          'In separatem Fenster öffnen (für 2. Monitor)',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => showDialog<void>(
                                          context: context,
                                          builder: (ctx) => Dialog.fullscreen(
                                            child: TournamentSecondScreenView(
                                              tournament: widget.tournament,
                                              isStandaloneWindow: true,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(Icons.fullscreen),
                                        label: const Text(
                                          'Hier im Vollbild-Dialog öffnen',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 3. Gruppen verwalten
                          if (activeStage is GroupTournamentRunStage)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.grid_view),
                                title: const Text('Gruppen verwalten'),
                                subtitle: const Text(
                                  'Positionen der Spieler in den Gruppen tauschen.',
                                ),
                                trailing: OutlinedButton(
                                  onPressed:
                                      isViewingActiveStage &&
                                          !_isApplyingStartDraw &&
                                          !_completedStageIndexes.contains(
                                            _viewStageIndex,
                                          ) &&
                                          GroupPositionEditor.canEdit(
                                            activeStage,
                                          )
                                      ? () => _editGroupPositions(activeStage)
                                      : null,
                                  child: const Text('Bearbeiten'),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (widget.tournament.leagueMatch == null)
                            Card(
                              child: ExpansionTile(
                                initiallyExpanded: false,
                                leading: const Icon(Icons.leaderboard_outlined),
                                title: const Text('Ranglistenoptionen'),
                                subtitle: const Text(
                                  'Wertung und zugewiesene Ranglisten',
                                ),
                                childrenPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                children: [
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Für Rangliste berücksichtigen',
                                    ),
                                    subtitle: const Text(
                                      'Nur ausgewählte Ranglisten erhalten Ergebnisse dieses Turniers.',
                                    ),
                                    value: widget.tournament.countsForRanking,
                                    onChanged: _savingRankingSelection
                                        ? null
                                        : (value) => _saveRankingSelection(
                                            countsForRanking: value,
                                            rankingIds: value
                                                ? widget.tournament.rankingIds
                                                : const [],
                                          ),
                                  ),
                                  if (_savingRankingSelection)
                                    const LinearProgressIndicator(),
                                  if (widget.tournament.countsForRanking)
                                    FutureBuilder<List<LocalRanking>>(
                                      future: _localRankings,
                                      builder: (context, snapshot) {
                                        if (snapshot.hasError) {
                                          return Text(
                                            'Ranglisten konnten nicht geladen werden: ${snapshot.error}',
                                          );
                                        }
                                        if (!snapshot.hasData) {
                                          return const LinearProgressIndicator();
                                        }
                                        final rankings = snapshot.data!;
                                        if (rankings.isEmpty) {
                                          return const Text(
                                            'Lege zuerst eine Rangliste im Hauptmenü an.',
                                          );
                                        }
                                        return Column(
                                          children: [
                                            for (final ranking in rankings)
                                              CheckboxListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(ranking.name),
                                                value: widget
                                                    .tournament
                                                    .rankingIds
                                                    .contains(ranking.id),
                                                onChanged:
                                                    _savingRankingSelection
                                                    ? null
                                                    : (selected) {
                                                        final ids =
                                                            List<String>.from(
                                                              widget
                                                                  .tournament
                                                                  .rankingIds,
                                                            );
                                                        if (selected == true) {
                                                          ids.add(ranking.id);
                                                        } else {
                                                          ids.remove(
                                                            ranking.id,
                                                          );
                                                        }
                                                        _saveRankingSelection(
                                                          countsForRanking:
                                                              true,
                                                          rankingIds: ids,
                                                        );
                                                      },
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (widget.tournament.leagueMatch == null &&
                              _activeStageIndex <
                                  widget.tournament.stages.length &&
                              widget
                                      .tournament
                                      .stages[_activeStageIndex]
                                      .type ==
                                  'groups')
                            Card(
                              child: ExpansionTile(
                                initiallyExpanded: false,
                                leading: const Icon(Icons.swap_vert),
                                title: const Text('Tie Breaker Einstellungen'),
                                subtitle: const Text(
                                  'Reihenfolge für Gleichstände in dieser Etappe',
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                children: [
                                  Text(
                                    'Tie-Breaker · ${widget.tournament.stages[_activeStageIndex].name}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  GroupTieBreakerSetup(
                                    tieBreakers: _tieBreakersForActiveStage(),
                                    onMoveTieBreaker: _moveGroupTieBreakerDraft,
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed:
                                          _hasPendingTieBreakerChanges &&
                                              !_savingTieBreakerSettings &&
                                              _viewStageIndex ==
                                                  _activeStageIndex &&
                                              !_completedStageIndexes.contains(
                                                _activeStageIndex,
                                              )
                                          ? _applyGroupTieBreakerDraft
                                          : null,
                                      icon: _savingTieBreakerSettings
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.check),
                                      label: const Text('Übernehmen'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (widget.tournament.leagueMatch == null)
                            const SizedBox(height: 12),
                          // 4. Spieler verwalten
                          Card(
                            child: ExpansionTile(
                              leading: const Icon(Icons.people_alt_outlined),
                              title: Text(
                                'Spieler (${widget.tournament.players.length})',
                              ),
                              subtitle: const Text(
                                'Namen anpassen oder Spieler aus dem Turnier entfernen.',
                              ),
                              childrenPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              children: [
                                for (final player in widget.tournament.players)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(player.name),
                                    subtitle: Wrap(
                                      spacing: 8,
                                      runSpacing: 2,
                                      children: [
                                        if (PlayerWithdrawalService.policy(
                                              widget.tournament,
                                              player,
                                            ) !=
                                            null)
                                          const Text(
                                            'Ausgeschieden / Zurückgezogen',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        if (player.profileId != null)
                                          const Text(
                                            'Name aus Spielerkartei · Umbenennen gesperrt',
                                          ),
                                      ],
                                    ),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        if (player.profileId == null)
                                          IconButton(
                                            tooltip: 'Spieler umbenennen',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 20,
                                            ),
                                            onPressed: () =>
                                                _renamePlayer(player),
                                          ),
                                        if (widget.tournament.finishedAt ==
                                                null &&
                                            PlayerWithdrawalService.policy(
                                                  widget.tournament,
                                                  player,
                                                ) ==
                                                null)
                                          IconButton(
                                            tooltip: 'Spieler entfernen (Drop)',
                                            icon: const Icon(
                                              Icons.person_remove_outlined,
                                              size: 20,
                                              color: Colors.red,
                                            ),
                                            onPressed: () =>
                                                _withdrawPlayer(player),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else if (_stageViewMode == StageViewMode.players)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Spieler',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          for (final player in widget.tournament.players)
                            Card(
                              child: ListTile(
                                title: Text(player.name),
                                subtitle:
                                    PlayerWithdrawalService.policy(
                                          widget.tournament,
                                          player,
                                        ) ==
                                        null
                                    ? null
                                    : const Text(
                                        'Aus dem Turnier ausgeschieden',
                                      ),
                                trailing:
                                    true &&
                                        widget.tournament.finishedAt == null &&
                                        PlayerWithdrawalService.policy(
                                              widget.tournament,
                                              player,
                                            ) ==
                                            null
                                    ? const Icon(Icons.person_remove_outlined)
                                    : null,
                                onTap:
                                    true &&
                                        widget.tournament.finishedAt == null &&
                                        PlayerWithdrawalService.policy(
                                              widget.tournament,
                                              player,
                                            ) ==
                                            null
                                    ? () => _withdrawPlayer(player)
                                    : null,
                              ),
                            ),
                        ],
                      )
                    else ...[
                      // Modus "Ergebnisse"
                      StageResultsSplitView(
                        stage: activeStage,
                        tournament: widget.tournament,
                        standingsFor: _standingsFor,
                        onEditResult: _editResult,
                        canEditResults: canEditResults,
                        qualifyingRank: _requiredRankForRunStage(
                          _viewStageIndex,
                        ),
                        isBracketEditMode: _isBracketEditMode && canEditResults,
                        canEditBracket:
                            canEditResults &&
                            (activeStage is KnockoutTournamentRunStage &&
                                _canEditKnockoutBracket(activeStage)),
                        onSwapSlot: (fromSlotIndex, toSlotIndex) {
                          if (activeStage is KnockoutTournamentRunStage) {
                            _swapKnockoutRunSlots(
                              activeStage,
                              fromSlotIndex,
                              toSlotIndex,
                            );
                          }
                        },
                        bracketBuilder:
                            (
                              stage,
                              qualifyingRank,
                              onEditResult,
                              canEditResults,
                              isEditMode,
                              onSwapSlot,
                            ) {
                              return _KnockoutBracketView(
                                stage: stage,
                                placementMatches: stage.placementMatches,
                                qualifyingRank: qualifyingRank,
                                onEditResult: onEditResult,
                                canEditResults: canEditResults,
                                isEditMode: isEditMode,
                                onSwapSlot: onSwapSlot,
                              );
                            },
                      ),
                    ],
                  ],
                ),
              ),
              if (_stageViewMode == StageViewMode.dashboard ||
                  _stageViewMode == StageViewMode.director) ...[
                SliverToBoxAdapter(
                  child: StageFooter(
                    canCompleteStage: canCompleteStage,
                    isLastStage: isLastStage,
                    isViewingActiveStage: isViewingActiveStage,
                    activeStageName:
                        widget.tournament.runStages[_activeStageIndex].name,
                    onCompleteStage: _completeCurrentStage,
                    onFinishEarly: _finishCurrentStageEarly,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
