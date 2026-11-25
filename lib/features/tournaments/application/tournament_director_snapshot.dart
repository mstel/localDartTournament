import '../domain/tournament_models.dart';
import '../domain/tournament_settings.dart';
import 'tournament_flow_priority.dart';
import '../domain/tournament_flow_priority_settings.dart';
import 'order_of_play/order_of_play_controller.dart';
import 'order_of_play/fixed_global_suggestions.dart';
import 'order_of_play/global_order_of_play_service.dart';
import '../domain/engines/group_board_assignment.dart';
import '../domain/engines/global_waitlist_engine.dart';

/// A read-only view of the production queue. Does not predict future winners.
class TournamentDirectorSnapshot {
  TournamentDirectorSnapshot(this.tournament, this.stage)
    : schedule = const OrderOfPlayController().plan(tournament, stage) {
    entries = const OrderOfPlayController().entries(tournament);
    _openSinglesRemain = entries.any(
      (e) =>
          e.stageIndex == stage &&
          e.match.hasPlayers &&
          !e.match.isResolved &&
          !e.match.hasTeamParticipant,
    );
    ready = entries
        .where(
          (e) =>
              e.stageIndex == stage &&
              e.match.hasPlayers &&
              !e.match.isResolved &&
              isPreviewableMatch(e.match) &&
              !schedule.blockingRunning.any((r) => identical(r.match, e.match)),
        )
        .toList();
    _assignedQueueByBoard = _buildAssignedQueueByBoard();
  }

  /// Pure, read-only preview of the shared waiting list in the dynamic mode.
  ///
  /// Reading the snapshot (including this getter) never persists state. The
  /// fixed preview is initialised and updated explicitly by the controller;
  /// every consumer of this snapshot sees the same plan for the same state.
  late final GlobalWaitlistPlan globalWaitlist = const GlobalWaitlistEngine()
      .plan(
        tournament,
        stage,
        allEntries: entries,
        schedule: schedule,
        isPreviewable: isPreviewableMatch,
      );

  final CreatedTournament tournament;
  final int stage;
  final BoardSchedule schedule;
  late final List<PlayEntry> entries, ready;
  late final bool _openSinglesRemain;
  late final Map<int, List<BoardAssignment>> _assignedQueueByBoard;
  late final TournamentFlowPriority _flowPriority =
      TournamentFlowPriority.forStage(
        tournament.runStages[stage],
        tournament: tournament,
        settings: TournamentFlowPrioritySettings(
          playerMatchDeficitThreshold:
              tournament.tournamentSettings.playerMatchDeficitThreshold,
          groupMatchDeficitThreshold:
              tournament.tournamentSettings.groupMatchDeficitThreshold,
          usePercentageForGroups:
              tournament.tournamentSettings.usePercentageForGroups,
          enabled: tournament.tournamentSettings.priorityHintsEnabled,
        ),
      );
  late final Set<GroupMatch> _prioritizedMatches =
      _flowPriority.prioritizedMatches;
  late final Set<GroupMatch> _deprioritizedMatches =
      _flowPriority.deprioritizedMatches;

  /// Doppel werden in Vorschauen erst gezeigt, wenn alle Einzel beendet sind.
  bool isPreviewableMatch(GroupMatch match) =>
      !match.hasTeamParticipant || !_openSinglesRemain;

  bool get isNormalRanking => tournament.leagueMatch == null;

  bool get isDirectorManagedNormalRanking =>
      isNormalRanking && tournament.directorModeEnabled;

  bool get isGlobalStrategy =>
      tournament.directorSchedulingStrategy == 'global';

  /// The dynamic mode is tournament-wide by definition, even if legacy data
  /// still carries a group strategy. Fixed modes keep their stored strategy.
  bool get usesGlobalBoardPool => isDynamicSchedule || isGlobalStrategy;

  bool get isFixedSchedule =>
      tournament.directorPlayOrderMode == 'fixed_schedule';

  bool get isDynamicSchedule => tournament.directorPlayOrderMode == 'dynamic';

  /// The only dynamic mode is "dynamisch + turnierweit". Legacy dynamic + group
  /// data is normalised to this mode before it reaches the app.
  bool get usesGlobalWaitlist =>
      isDirectorManagedNormalRanking && isDynamicSchedule;

  /// Fixed + global: the board is freely selectable, so fixed schedule tiles
  /// must not show a board label.
  bool get hideScheduleBoardLabels =>
      isDirectorManagedNormalRanking && isFixedSchedule && isGlobalStrategy;

  /// Flat, tournament-wide fixed suggestions for all free boards.
  ///
  /// The simulated board of an assignment is only a planning aid: a match from
  /// any later block can be started now if its players are free. All such
  /// entries are offered, collisions are filtered greedily in the persisted
  /// `fixedScheduleOrder` (the shared priority engine breaks ties).
  List<BoardAssignment> flatGlobalFixedSuggestions({int limit = 16}) =>
      const FixedGlobalSuggestions().plan(
        tournament: tournament,
        stage: stage,
        entries: entries,
        schedule: schedule,
        isPreviewable: isPreviewableMatch,
        limit: limit,
      );

  /// Stable per-board suggestions of the dynamic global mode. They only change
  /// after a result was entered; starting a match keeps them intact.
  Map<int, BoardAssignment> globalBoardAssignments() {
    if (!isDirectorManagedNormalRanking ||
        !isDynamicSchedule ||
        !usesGlobalBoardPool) {
      return const {};
    }
    final cached = GlobalOrderOfPlayService.instance.boardAssignments(
      tournament,
      stage,
    );
    final runningBoards = {
      for (final entry in schedule.blockingRunning) entry.match.boardNumber,
    };
    final used = <String>{
      for (final entry in schedule.blockingRunning) ...entry.players,
    };
    final result = <int, BoardAssignment>{};
    final boards = cached.keys.toList()..sort();
    for (final board in boards) {
      final assignment = cached[board]!;
      if (runningBoards.contains(board) ||
          tournament.blockedBoards.contains(board) ||
          assignment.entry.match.isResolved ||
          !isPreviewableMatch(assignment.entry.match)) {
        continue;
      }
      if (assignment.entry.players.any(used.contains)) continue;
      result[board] = assignment;
      used.addAll(assignment.entry.players);
    }
    return result;
  }

  /// Board -> match view of [globalBoardAssignments].
  Map<int, GroupMatch> globalBoardSuggestions() => {
    for (final entry in globalBoardAssignments().entries)
      entry.key: entry.value.entry.match,
  };

  /// Recalculated open/follow-up order behind the stable global suggestions.
  List<GroupMatch> remainingGlobalQueue() {
    if (!isDirectorManagedNormalRanking ||
        !isDynamicSchedule ||
        !usesGlobalBoardPool) {
      return const [];
    }
    return GlobalOrderOfPlayService.instance.remainingQueue(tournament, stage);
  }

  /// Names of players who trail the most-played participant by at least the
  /// configured backlog threshold after [entry] is counted.
  List<String> fewestMatchesPlayerNames(PlayEntry entry) {
    if (!tournament.tournamentSettings.priorityHintsEnabled) {
      return const [];
    }
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final candidate in entries.where(
      (candidate) => candidate.stageIndex == stage,
    )) {
      for (final player in [
        candidate.match.homePlayer,
        candidate.match.awayPlayer,
      ]) {
        if (player == null) continue;
        for (final individual in player.individuals) {
          final id = individual.profileId ?? individual.name;
          counts.putIfAbsent(id, () => 0);
          names.putIfAbsent(id, () => individual.name);
        }
      }
    }
    for (final played in [...schedule.finished, ...schedule.blockingRunning]) {
      if (played.stageIndex != stage) continue;
      for (final player in played.players) {
        counts[player] = (counts[player] ?? 0) + 1;
      }
    }
    for (final player in entry.players) {
      counts[player] = (counts[player] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];
    final highest = counts.values.reduce((a, b) => a > b ? a : b);
    final threshold = tournament.tournamentSettings.playerMatchDeficitThreshold;
    final lowest = counts.values.reduce((a, b) => a < b ? a : b);
    if (highest - lowest < threshold) return const [];
    return counts.entries
        .where((item) => highest - item.value >= threshold)
        .map((item) => names[item.key] ?? item.key)
        .toList()
      ..sort();
  }

  String fewestMatchesLabel(PlayEntry entry) =>
      fewestMatchesPlayerNames(entry).join(', ');

  /// What the schedule overview (second monitor / Leitung) should show.
  DirectorScheduleOverview get scheduleOverview {
    if (!isDirectorManagedNormalRanking) {
      return const DirectorScheduleOverview(
        presentation: DirectorSchedulePresentation.unchanged,
      );
    }
    if (isFixedSchedule && isGlobalStrategy) {
      return DirectorScheduleOverview(
        presentation: DirectorSchedulePresentation.globalFlat,
        suggestions: flatGlobalFixedSuggestions(),
        note: 'Freie Board-Wahl',
        showBoardLabels: false,
      );
    }
    if (usesGlobalWaitlist) {
      final waitlist = globalWaitlist;
      final entries = waitlist.queue
          .asMap()
          .entries
          .map((item) => BoardAssignment(item.value, item.key, 0))
          .toList(growable: false);
      final preview = waitlistPreviewEntries();
      final skippedMatches = <GroupMatch>{
        for (final entry in waitlist.skipped) entry.match,
        for (final entry in [...waitlist.fixed, ...waitlist.dynamic])
          if (waitlist.isSkipped(entry)) entry.match,
      };
      return DirectorScheduleOverview(
        presentation: DirectorSchedulePresentation.globalWaitlist,
        suggestions: entries,
        note: 'Die nächste Begegnung kommt an das nächste freie Board.',
        showBoardLabels: false,
        fixedCount: waitlist.fixedCount,
        waitlist: waitlist,
        waitlistPreview: preview,
        waitlistPreviewFlags: {
          for (final assignment in preview)
            assignment.entry.match: skippedMatches.contains(
              assignment.entry.match,
            ),
        },
      );
    }
    // Only fixed + group remains here: the dynamic mode is always the shared
    // waitlist, there is no separate dynamic + group presentation any more.
    final boardsByGroup = configuredBoardsByGroup();
    final groups = <String, List<BoardAssignment>>{
      for (final key in boardsByGroup.keys) key: <BoardAssignment>[],
    };
    for (final group in boardsByGroup.entries) {
      for (final board in group.value) {
        groups[group.key]!.addAll(upcomingForBoard(board));
      }
      groups[group.key]!.sort((a, b) {
        final order = (a.entry.match.fixedScheduleOrder ?? 1 << 30).compareTo(
          b.entry.match.fixedScheduleOrder ?? 1 << 30,
        );
        return order != 0 ? order : a.board.compareTo(b.board);
      });
    }
    return DirectorScheduleOverview(
      presentation: DirectorSchedulePresentation.groupFull,
      groups: groups,
    );
  }

  /// Feste,Board-lokale Warteschlange für den Modus "Fest zugewiesene Partien".
  /// Die Reihenfolge wird ausschließlich aus den persistierten
  /// `fixedScheduleOrder`-Werten und der Gruppen-/Board-Zuordnung gebildet.
  /// Ein Ergebnis verändert daher nur die Warteschlange des betroffenen Boards.
  Map<int, List<BoardAssignment>> _buildAssignedQueueByBoard() {
    final queue = <int, List<BoardAssignment>>{};
    if (tournament.directorPlayOrderMode != 'fixed_schedule' ||
        tournament.directorMultiBoardAssignmentBehavior != 'assigned') {
      return queue;
    }

    final stageEntries = entries
        .where((entry) => entry.stageIndex == stage && entry.match.hasPlayers)
        .toList();
    final originalOrder = {
      for (var index = 0; index < stageEntries.length; index++)
        stageEntries[index]: index,
    };
    stageEntries.sort((a, b) {
      final order = (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
        b.match.fixedScheduleOrder ?? 1 << 30,
      );
      return order != 0
          ? order
          : originalOrder[a]!.compareTo(originalOrder[b]!);
    });

    final groupsByBoard = configuredBoardsByGroup();
    final fallbackBoards = [
      for (var board = 1; board <= tournament.boardCount; board++)
        if (!tournament.blockedBoards.contains(board)) board,
    ];
    final counters = <String, int>{};
    final running = schedule.running.map((entry) => entry.match).toSet();

    for (final entry in stageEntries) {
      final key = entry.groupKey ?? '';
      final configured = groupsByBoard[key]?.toList() ?? fallbackBoards;
      final boards = [...configured]..sort();
      if (boards.isEmpty) continue;
      // Der Index wird für jeden Eintrag der festen Reihenfolge vergeben –
      // auch für bereits gespielte Partien. Nur so bleibt die Board-Zuordnung
      // nach einem Ergebnis stabil.
      final index = counters[key] ?? 0;
      counters[key] = index + 1;
      final board = boards[index % boards.length];
      if (!isPreviewableMatch(entry.match) ||
          entry.match.isResolved ||
          running.any((match) => identical(match, entry.match))) {
        continue;
      }
      queue
          .putIfAbsent(board, () => <BoardAssignment>[])
          .add(BoardAssignment(entry, index ~/ boards.length, board));
    }
    return queue;
  }

  List<BoardAssignment> upcomingForBoard(int board) {
    final assignedQueue = _assignedQueueByBoard[board];
    if (assignedQueue != null) {
      return assignedQueue.take(4).toList();
    }
    final assignments = schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.board == board &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved &&
              isPreviewableMatch(assignment.entry.match),
        )
        .toList();
    late final List<BoardAssignment> result;
    if (tournament.directorPlayOrderMode == 'fixed_schedule' &&
        tournament.directorMultiBoardAssignmentBehavior == 'mirror' &&
        assignments.isNotEmpty) {
      final groupKey = assignments.first.entry.groupKey;
      if (groupKey != null) {
        result = schedule.planned
            .where(
              (assignment) =>
                  assignment.entry.stageIndex == stage &&
                  assignment.entry.groupKey == groupKey &&
                  assignment.entry.match.hasPlayers &&
                  isPreviewableMatch(assignment.entry.match),
            )
            .take(4)
            .map(
              (assignment) =>
                  BoardAssignment(assignment.entry, assignment.block, board),
            )
            .toList();
        return _orderedForPlay(result);
      }
    }
    if (tournament.directorPlayOrderMode == 'dynamic') {
      final order = {
        for (var index = 0; index < assignments.length; index++)
          assignments[index]: index,
      };
      assignments.sort((a, b) {
        final blockOrder = a.block.compareTo(b.block);
        if (blockOrder != 0) return blockOrder;
        final aPriority = _prioritizedMatches.contains(a.entry.match);
        final bPriority = _prioritizedMatches.contains(b.entry.match);
        if (aPriority != bPriority) return aPriority ? -1 : 1;
        final aDeprioritized = _deprioritizedMatches.contains(a.entry.match);
        final bDeprioritized = _deprioritizedMatches.contains(b.entry.match);
        if (aDeprioritized != bDeprioritized) {
          return aDeprioritized ? 1 : -1;
        }
        return order[a]!.compareTo(order[b]!);
      });
    }
    return _orderedForPlay(assignments.take(4).toList());
  }

  List<BoardAssignment> _orderedForPlay(List<BoardAssignment> assignments) {
    if (tournament.directorPlayOrderMode != 'fixed_schedule') {
      return assignments;
    }
    final fixedOrder = {
      for (var index = 0; index < assignments.length; index++)
        assignments[index]: index,
    };
    return assignments.toList()..sort((a, b) {
      final order = (a.entry.match.fixedScheduleOrder ?? 1 << 30).compareTo(
        b.entry.match.fixedScheduleOrder ?? 1 << 30,
      );
      return order != 0 ? order : fixedOrder[a]!.compareTo(fixedOrder[b]!);
    });
  }

  /// The configured board membership, independent of the currently computed
  /// queue. This is the source for board labels in the director dashboard.
  Map<String, Set<int>> configuredBoardsByGroup() {
    if (stage < 0 || stage >= tournament.runStages.length) return const {};
    final activeStage = tournament.runStages[stage];
    if (activeStage is! GroupTournamentRunStage) return const {};
    final groupNames = activeStage.groups.map((group) => group.name).toList();
    final defaults = GroupBoardAssignment.defaultsForStage(
      stageIndex: stage,
      groupNames: groupNames,
      boardCount: tournament.boardCount,
    );
    final result = <String, Set<int>>{};
    for (final groupName in groupNames) {
      final key = tournamentGroupBoardKey(stage, groupName);
      final configured =
          tournament.directorGroupBoardAssignments[key]?.toSet() ??
          tournament.groupBoardAssignments[key]?.toSet() ??
          defaults[key] ??
          const <int>{};
      result[key] = configured
          .where(
            (board) =>
                board >= 1 &&
                board <= tournament.boardCount &&
                !tournament.blockedBoards.contains(board),
          )
          .toSet();
    }
    return result;
  }

  /// Inverse of [configuredBoardsByGroup] for board cards and schedule tables.
  Map<int, List<String>> configuredGroupsByBoard() {
    final groupsByBoard = <int, List<String>>{};
    for (final entry in configuredBoardsByGroup().entries) {
      final label = _groupLabel(entry.key);
      if (label.isEmpty) continue;
      for (final board in entry.value) {
        groupsByBoard.putIfAbsent(board, () => <String>[]).add(label);
      }
    }
    for (final entry in groupsByBoard.entries) {
      entry.value.sort();
    }
    return groupsByBoard;
  }

  String _groupLabel(String groupKey) {
    final separator = groupKey.indexOf(':');
    final name = separator >= 0 ? groupKey.substring(separator + 1) : groupKey;
    return name.startsWith('Gruppe ') ? name.trim() : 'Gruppe $name';
  }

  /// One canonical suggestion source for dashboard, second screen and audio.
  /// Fixed schedules use the persisted per-board queue; dynamic schedules keep
  /// the globally best playable matches as suggestions for every board.
  List<BoardAssignment> suggestionsForBoard(int board, {int limit = 3}) {
    if (tournament.blockedBoards.contains(board)) return const [];
    if (usesGlobalWaitlist) {
      return (_globalWaitlistBoardSuggestions(limit: limit)[board] ?? const [])
          .take(1)
          .toList(growable: false);
    }
    if (isDirectorManagedNormalRanking && isGlobalStrategy) {
      if (isFixedSchedule) {
        // A fixed global schedule is a flat list: no board is reserved in
        // advance. The simulator boards are only a planning aid, so every free
        // board must see the whole collision-free list. Otherwise running
        // matches leave the remaining boards without any suggestion.
        if (runningOn(board) != null) return const [];
        return flatGlobalFixedSuggestions()
            .map(
              (assignment) =>
                  BoardAssignment(assignment.entry, assignment.block, board),
            )
            .take(limit)
            .toList(growable: false);
      }
      final stable = globalBoardAssignments()[board];
      return stable == null ? const [] : [stable];
    }
    final assignments = isFixedSchedule
        ? upcomingForBoard(board)
        : _selectableAssignments();
    return assignments.take(limit).toList();
  }

  /// Every entry shown in the shared waitlist, including entries that are
  /// temporarily blocked by a running match. Those entries remain visible as
  /// "vorläufig übersprungen" but are not offered by [suggestionsForBoard].
  List<BoardAssignment> waitlistPreviewEntries() {
    if (!usesGlobalWaitlist) return const [];
    final waitlist = globalWaitlist;
    final seen = <GroupMatch>{};
    final result = <BoardAssignment>[];
    for (final entry in [
      ...waitlist.fixed,
      ...waitlist.dynamic,
      ...waitlist.skipped,
    ]) {
      if (!seen.add(entry.match)) continue;
      result.add(BoardAssignment(entry, 0, 0));
    }
    return List<BoardAssignment>.unmodifiable(result);
  }

  Map<String, List<int>> mergedGroupBoards() {
    if (tournament.directorMultiBoardAssignmentBehavior != 'merge' ||
        !tournament.directorModeEnabled ||
        tournament.directorSchedulingStrategy != 'group' ||
        stage < 0 ||
        stage >= tournament.runStages.length) {
      return const {};
    }
    final activeStage = tournament.runStages[stage];
    if (activeStage is! GroupTournamentRunStage) return const {};
    final groupNames = activeStage.groups.map((group) => group.name).toList();
    final defaults = GroupBoardAssignment.defaultsForStage(
      stageIndex: stage,
      groupNames: groupNames,
      boardCount: tournament.boardCount,
    );
    final candidates = <String, List<int>>{};
    for (final name in groupNames) {
      final key = tournamentGroupBoardKey(stage, name);
      final configured = _activeAssignedBoards(stage, name, defaults);
      if (configured.length < 2) continue;
      final pendingMatches = <GroupMatch>{
        for (final assignment in schedule.planned)
          if (assignment.entry.stageIndex == stage &&
              assignment.entry.groupKey == key &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved)
            assignment.entry.match,
        for (final entry in schedule.running)
          if (entry.stageIndex == stage &&
              entry.groupKey == key &&
              entry.match.hasPlayers &&
              !entry.match.isResolved)
            entry.match,
      };
      // Release boards the group no longer needs: one remaining match cannot
      // occupy two boards at the same time.
      if (pendingMatches.length < configured.length) continue;
      final activeBoards = <int>{
        for (final assignment in schedule.planned)
          if (assignment.entry.stageIndex == stage &&
              assignment.entry.groupKey == key &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved)
            assignment.board,
        for (final entry in schedule.running)
          if (entry.stageIndex == stage &&
              entry.groupKey == key &&
              entry.match.hasPlayers &&
              !entry.match.isResolved &&
              entry.match.boardNumber != null)
            entry.match.boardNumber!,
      };
      // With several groups the configured pair stays merged even if the
      // engine currently queues the matches on one of the boards. A single
      // group only keeps the pair while both boards are actually in use.
      if (groupNames.length < 2 && activeBoards.length < 2) continue;
      candidates[key] = List<int>.unmodifiable(configured);
    }
    return candidates;
  }

  List<int> _activeAssignedBoards(
    int stage,
    String groupName,
    Map<String, Set<int>> defaults,
  ) {
    final directorAssigned = GroupBoardAssignment.lookup(
      tournament.directorGroupBoardAssignments,
      stage,
      groupName,
    );
    final legacyAssigned = GroupBoardAssignment.lookup(
      tournament.groupBoardAssignments,
      stage,
      groupName,
    );
    final assignedBoards = directorAssigned.isNotEmpty
        ? directorAssigned
        : legacyAssigned.isNotEmpty
        ? legacyAssigned
        : GroupBoardAssignment.lookup(defaults, stage, groupName);
    final eligibleBoards = assignedBoards
        .where(
          (board) =>
              board >= 1 &&
              board <= tournament.boardCount &&
              !tournament.blockedBoards.contains(board),
        )
        .toSet();
    return eligibleBoards.toList()..sort();
  }

  List<BoardAssignment> upcomingForBoards(
    List<int> boards, {
    required String groupKey,
    int limit = 6,
  }) {
    final seen = <GroupMatch>{};
    final suggestions = <BoardAssignment>[];
    for (final board in boards) {
      for (final assignment in suggestionsForBoard(board, limit: limit)) {
        if (assignment.entry.groupKey != groupKey) continue;
        if (!seen.add(assignment.entry.match)) continue;
        suggestions.add(assignment);
        if (suggestions.length >= limit) {
          return suggestions;
        }
      }
    }
    return suggestions;
  }

  List<BoardAssignment> selectableForBoard(int board) {
    if (!freeBoards.contains(board)) return [];
    if (usesGlobalWaitlist) {
      return [
        for (final entry in _globalWaitlistSelectableEntries().indexed)
          BoardAssignment(entry.$2, entry.$1 ~/ tournament.boardCount, board),
      ];
    }
    if (hideScheduleBoardLabels && isFixedSchedule) {
      return flatGlobalFixedSuggestions(limit: 32)
          .map(
            (assignment) =>
                BoardAssignment(assignment.entry, assignment.block, board),
          )
          .toList(growable: false);
    }
    return _selectableAssignments();
  }

  List<PlayEntry> _globalWaitlistSelectableEntries() {
    final runningPlayers = <String>{
      for (final running in schedule.blockingRunning) ...running.players,
    };
    final eligible = ready
        .where(
          (entry) =>
              entry.stageIndex == stage &&
              !entry.players.any(runningPlayers.contains),
        )
        .toList();
    final order = {
      for (var index = 0; index < entries.length; index++) entries[index]: index,
    };
    eligible.sort((a, b) {
      final aPriority = _prioritizedMatches.contains(a.match);
      final bPriority = _prioritizedMatches.contains(b.match);
      if (aPriority != bPriority) return aPriority ? -1 : 1;
      final aDeprioritized = _deprioritizedMatches.contains(a.match);
      final bDeprioritized = _deprioritizedMatches.contains(b.match);
      if (aDeprioritized != bDeprioritized) return aDeprioritized ? 1 : -1;
      return (order[a] ?? 1 << 30).compareTo(order[b] ?? 1 << 30);
    });

    final selected = <PlayEntry>[];
    final seen = <GroupMatch>{};
    final waitlist = globalWaitlist;
    for (final entry in [...waitlist.fixed, ...eligible]) {
      if (waitlist.isSkipped(entry) ||
          entry.stageIndex != stage ||
          !entry.match.hasPlayers ||
          entry.match.isResolved ||
          !isPreviewableMatch(entry.match) ||
          entry.players.any(runningPlayers.contains) ||
          !seen.add(entry.match)) {
        continue;
      }
      selected.add(entry);
    }
    return selected;
  }

  /// Distributes collision-free next-up suggestions over currently free
  /// boards. The persisted waitlist keeps its configured size; this fallback
  /// pool keeps every free board usable when that size is smaller than the
  /// board count or its fixed entries collide.
  Map<int, List<BoardAssignment>> _globalWaitlistBoardSuggestions({
    required int limit,
  }) {
    if (limit < 1 || freeBoards.isEmpty) return const {};
    final candidates = _globalWaitlistSelectableEntries();
    final runningPlayers = <String>{
      for (final running in schedule.blockingRunning) ...running.players,
    };
    final selectedMatches = <GroupMatch>{};
    final result = <int, List<BoardAssignment>>{
      for (final board in freeBoards) board: <BoardAssignment>[],
    };
    for (var wave = 0; wave < limit; wave++) {
      final busyThisWave = <String>{...runningPlayers};
      for (final board in freeBoards) {
        final next = candidates
            .where(
              (entry) =>
                  !selectedMatches.contains(entry.match) &&
                  !entry.players.any(busyThisWave.contains),
            )
            .firstOrNull;
        if (next == null) continue;
        result[board]!.add(BoardAssignment(next, wave, board));
        selectedMatches.add(next.match);
        busyThisWave.addAll(next.players);
      }
    }
    return {
      for (final entry in result.entries)
        if (entry.value.isNotEmpty)
          entry.key: List<BoardAssignment>.unmodifiable(entry.value),
    };
  }

  List<BoardAssignment> _selectableAssignments({Set<String>? busyPlayers}) {
    final busy =
        busyPlayers ??
        <String>{
          for (final running in schedule.blockingRunning) ...running.players,
        };
    final assignments = schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved &&
              isPreviewableMatch(assignment.entry.match) &&
              !assignment.entry.players.any(busy.contains),
        )
        .toList();
    if (tournament.directorPlayOrderMode == 'dynamic') {
      final order = {
        for (var index = 0; index < assignments.length; index++)
          assignments[index]: index,
      };
      assignments.sort((a, b) {
        final blockOrder = a.block.compareTo(b.block);
        if (blockOrder != 0) return blockOrder;
        final aPriority = _prioritizedMatches.contains(a.entry.match);
        final bPriority = _prioritizedMatches.contains(b.entry.match);
        if (aPriority != bPriority) return aPriority ? -1 : 1;
        final aDeprioritized = _deprioritizedMatches.contains(a.entry.match);
        final bDeprioritized = _deprioritizedMatches.contains(b.entry.match);
        if (aDeprioritized != bDeprioritized) {
          return aDeprioritized ? 1 : -1;
        }
        return order[a]!.compareTo(order[b]!);
      });
    }
    return assignments;
  }

  TournamentDirectorBoardRecommendation? recommendationForBoard(int board) {
    if (!freeBoards.contains(board)) return null;
    final suggestions = suggestionsForBoard(board, limit: 2);
    if (suggestions.isEmpty) return null;
    return TournamentDirectorBoardRecommendation(
      next: BoardAssignment(
        suggestions.first.entry,
        suggestions.first.block,
        board,
      ),
      alternative: suggestions.length > 1
          ? BoardAssignment(suggestions[1].entry, suggestions[1].block, board)
          : null,
    );
  }

  List<int> get freeBoards => [
    for (var b = 1; b <= tournament.boardCount; b++)
      if (!tournament.blockedBoards.contains(b) && runningOn(b) == null) b,
  ];
  PlayEntry? runningOn(int board) => schedule.blockingRunning
      .where((e) => e.match.boardNumber == board)
      .firstOrNull;
  bool canStart(PlayEntry entry) =>
      freeBoards.isNotEmpty &&
      !tournament.completedStageIndexes.contains(stage) &&
      !schedule.blockingRunning.any(
        (r) => r.players.any(entry.players.contains),
      );

  List<BoardAssignment> visibleRecommendations({
    TournamentSettings settings = const TournamentSettings(),
    int limit = 6,
  }) {
    final priority = TournamentFlowPriority.forStage(
      tournament.runStages[stage],
      tournament: tournament,
      settings: TournamentFlowPrioritySettings(
        playerMatchDeficitThreshold: settings.playerMatchDeficitThreshold,
        groupMatchDeficitThreshold: settings.groupMatchDeficitThreshold,
        usePercentageForGroups: settings.usePercentageForGroups,
        enabled: settings.priorityHintsEnabled,
      ),
    );
    final prioritized = priority.prioritizedMatches;
    final assignments = schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.entry.match.hasPlayers &&
              isPreviewableMatch(assignment.entry.match),
        )
        .toList();
    final originalOrder = {
      for (var index = 0; index < assignments.length; index++)
        assignments[index]: index,
    };
    assignments.sort((a, b) {
      final blockOrder = a.block.compareTo(b.block);
      if (blockOrder != 0) return blockOrder;
      if (tournament.directorPlayOrderMode == 'dynamic') {
        final priorityOrder =
            prioritized.contains(a.entry.match) ==
                prioritized.contains(b.entry.match)
            ? 0
            : prioritized.contains(a.entry.match)
            ? -1
            : 1;
        if (priorityOrder != 0) return priorityOrder;
        final aDeprioritized = priority.deprioritizedMatches.contains(
          a.entry.match,
        );
        final bDeprioritized = priority.deprioritizedMatches.contains(
          b.entry.match,
        );
        if (aDeprioritized != bDeprioritized) {
          return aDeprioritized ? 1 : -1;
        }
      }
      return originalOrder[a]!.compareTo(originalOrder[b]!);
    });
    return assignments.take(limit).toList(growable: false);
  }

  List<PlayEntry> search(String query) {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return [];
    bool matches(TournamentPlayer? p) =>
        p != null &&
        (p.name.toLowerCase().contains(text) ||
            p.individuals.any((i) => i.name.toLowerCase().contains(text)));
    // Only known pairings from the current stage; no speculative next-stage seeds.
    final ordered = const OrderOfPlayController().orderedEntriesForStage(
      tournament,
      stage,
      prioritizedMatches: _prioritizedMatches,
      deprioritizedMatches: _deprioritizedMatches,
    );
    final order = {
      for (var index = 0; index < ordered.length; index++)
        ordered[index].match: index,
    };
    return entries
        .where(
          (e) =>
              e.stageIndex == stage &&
              !e.match.isResolved &&
              (matches(e.match.homePlayer) || matches(e.match.awayPlayer)),
        )
        .toList()
      ..sort((a, b) {
        final aRunning = schedule.running.any(
          (running) => identical(running.match, a.match),
        );
        final bRunning = schedule.running.any(
          (running) => identical(running.match, b.match),
        );
        if (aRunning != bRunning) return aRunning ? -1 : 1;
        return (order[a.match] ?? 1 << 30).compareTo(order[b.match] ?? 1 << 30);
      });
  }
}

class TournamentDirectorBoardRecommendation {
  const TournamentDirectorBoardRecommendation({
    required this.next,
    this.alternative,
  });

  final BoardAssignment next;
  final BoardAssignment? alternative;
}

/// Which schedule the second monitor / the Leitung should render for a normal
/// ranking tournament.
enum DirectorSchedulePresentation {
  /// Fixed order + group strategy: complete group-wise schedule.
  groupFull,

  /// Obsolete legacy value: dynamic order is always the shared waitlist now.
  /// Kept only so persisted screenshots and old callers still compile.
  groupFirstOnly,

  /// Fixed order + global strategy: one flat fixed list, free board choice.
  globalFlat,

  /// Dynamic order + global strategy: one shared waiting list with a fixed
  /// preview and an optimised remainder. No board is assigned in advance.
  globalWaitlist,

  /// Legacy dynamic global presentation, kept for persisted screenshots/tests.
  globalPerBoard,

  /// League/friendly or director mode off: keep the existing presentation.
  unchanged,
}

/// Read model for the schedule overview. [groups] is keyed by the internal
/// group key (`stageIndex:groupName`), [suggestions] is the flat list for the
/// global modes. Board labels must be hidden when [showBoardLabels] is false.
class DirectorScheduleOverview {
  const DirectorScheduleOverview({
    required this.presentation,
    this.groups = const {},
    this.suggestions = const [],
    this.note,
    this.showBoardLabels = true,
    this.fixedCount = 0,
    this.waitlist,
    this.waitlistPreview,
    this.waitlistPreviewFlags,
  });

  final DirectorSchedulePresentation presentation;
  final Map<String, List<BoardAssignment>> groups;
  final List<BoardAssignment> suggestions;
  final String? note;
  final bool showBoardLabels;
  final int fixedCount;
  final GlobalWaitlistPlan? waitlist;

  /// All waitlist entries, including temporarily busy ones. Board numbers are
  /// zero because the next free board is chosen only when the match starts.
  final List<BoardAssignment>? waitlistPreview;

  /// `true` means "vorläufig übersprungen" (blocked/running), `false` means the
  /// preview entry can be started right now.
  final Map<GroupMatch, bool>? waitlistPreviewFlags;

  Set<GroupMatch> get skippedPreviewMatches {
    final flags = waitlistPreviewFlags;
    if (flags == null) return const {};
    return {
      for (final item in flags.entries)
        if (item.value) item.key,
    };
  }

  bool get hasSkippedPreview => skippedPreviewMatches.isNotEmpty;

  String? get skippedPreviewNote =>
      hasSkippedPreview ? 'vorläufig übersprungen' : null;

  bool get isFlat =>
      presentation == DirectorSchedulePresentation.globalFlat ||
      presentation == DirectorSchedulePresentation.globalWaitlist ||
      presentation == DirectorSchedulePresentation.globalPerBoard;

  List<BoardAssignment> get visibleSuggestions => isFlat
      ? suggestions
      : groups.values.expand((items) => items).toList(growable: false);
}
