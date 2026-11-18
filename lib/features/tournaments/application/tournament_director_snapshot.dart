import '../domain/tournament_models.dart';
import '../domain/tournament_settings.dart';
import 'tournament_flow_priority.dart';
import '../domain/tournament_flow_priority_settings.dart';
import 'order_of_play/order_of_play_controller.dart';
import '../domain/engines/group_board_assignment.dart';

/// A read-only view of the production queue. Does not predict future winners.
class TournamentDirectorSnapshot {
  TournamentDirectorSnapshot(this.tournament, this.stage)
    : schedule = const OrderOfPlayController().plan(tournament, stage) {
    entries = const OrderOfPlayController().entries(tournament);
    ready = entries
        .where(
          (e) =>
              e.stageIndex == stage &&
              e.match.hasPlayers &&
              !e.match.isResolved &&
              !schedule.running.any((r) => identical(r.match, e.match)),
        )
        .toList();
  }
  final CreatedTournament tournament;
  final int stage;
  final BoardSchedule schedule;
  late final List<PlayEntry> entries, ready;
  late final TournamentFlowPriority _flowPriority =
      TournamentFlowPriority.forStage(
        tournament.runStages[stage],
        settings: TournamentFlowPrioritySettings(
          playerMatchDeficitThreshold:
              tournament.tournamentSettings.playerMatchDeficitThreshold,
          groupMatchDeficitThreshold:
              tournament.tournamentSettings.groupMatchDeficitThreshold,
          usePercentageForGroups:
              tournament.tournamentSettings.usePercentageForGroups,
        ),
      );
  late final Set<GroupMatch> _prioritizedMatches =
      _flowPriority.prioritizedMatches;
  late final Set<GroupMatch> _deprioritizedMatches =
      _flowPriority.deprioritizedMatches;

  List<BoardAssignment> upcomingForBoard(int board) {
    final assignments = schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.board == board &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved,
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
                  assignment.entry.match.hasPlayers,
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
    if (tournament.directorPlayOrderMode != 'fixed_schedule') return assignments;
    final fixedOrder = {
      for (var index = 0; index < assignments.length; index++)
        assignments[index]: index,
    };
    return assignments.toList()
      ..sort((a, b) {
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
      result[key] =
          configured
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
    final assignments = tournament.directorPlayOrderMode == 'fixed_schedule'
        ? upcomingForBoard(board)
        : _selectableAssignments();
    return assignments.take(limit).toList();
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
    final assignedBoards =
        directorAssigned.isNotEmpty
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
    return _selectableAssignments();
  }

  List<BoardAssignment> _selectableAssignments({Set<String>? busyPlayers}) {
    final busy = busyPlayers ?? <String>{
      for (final running in schedule.running) ...running.players,
    };
    final assignments = schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved &&
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
      next: BoardAssignment(suggestions.first.entry, suggestions.first.block, board),
      alternative: suggestions.length > 1
          ? BoardAssignment(suggestions[1].entry, suggestions[1].block, board)
          : null,
    );
  }

  List<int> get freeBoards => [
    for (var b = 1; b <= tournament.boardCount; b++)
      if (!tournament.blockedBoards.contains(b) && runningOn(b) == null) b,
  ];
  PlayEntry? runningOn(int board) =>
      schedule.running.where((e) => e.match.boardNumber == board).firstOrNull;
  bool canStart(PlayEntry entry) =>
      freeBoards.isNotEmpty &&
      !tournament.completedStageIndexes.contains(stage) &&
      !schedule.running.any((r) => r.players.any(entry.players.contains));

  List<BoardAssignment> visibleRecommendations({
    TournamentSettings settings = const TournamentSettings(),
    int limit = 6,
  }) {
    final priority = TournamentFlowPriority.forStage(
      tournament.runStages[stage],
      settings: TournamentFlowPrioritySettings(
        playerMatchDeficitThreshold: settings.playerMatchDeficitThreshold,
        groupMatchDeficitThreshold: settings.groupMatchDeficitThreshold,
        usePercentageForGroups: settings.usePercentageForGroups,
      ),
    );
    final prioritized = priority.prioritizedMatches;
    final assignments = schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.entry.match.hasPlayers,
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
