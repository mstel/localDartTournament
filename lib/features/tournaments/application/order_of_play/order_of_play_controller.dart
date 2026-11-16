import '../../domain/knockout_round_names.dart';
import '../../domain/tournament_models.dart';
import '../../domain/engines/board_scheduling_engine.dart';
import '../../domain/engines/group_board_assignment.dart';
export '../../domain/engines/board_scheduling_engine.dart';

String tournamentGroupBoardKey(int stageIndex, String groupName) =>
    '$stageIndex:${groupName.trim()}';

/// Deterministic greedy scheduling: fill boards, then prefer rested players.
/// No predictions of winners: unresolved future pairings stay in the waiting list.
class OrderOfPlayController {
  const OrderOfPlayController();

  List<PlayEntry> entries(CreatedTournament tournament) {
    final result = <PlayEntry>[];
    for (var index = 0; index < tournament.runStages.length; index++) {
      final stage = tournament.runStages[index];
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          final matches = group.knockoutRounds.isEmpty
              ? group.matches
              : <GroupMatch>[
                  for (final round in group.knockoutRounds) ...round,
                  ...group.placementMatches,
                  ...group.matches.where((match) => match.isDecider),
                ];
          for (final match in matches) {
            result.add(
              PlayEntry(
                match,
                index,
                '${stage.name} · ${group.name} · ${stageMatchName(stage, match)}',
                tournamentGroupBoardKey(index, group.name),
              ),
            );
          }
        }
      } else if (stage is KnockoutTournamentRunStage) {
        for (final match in stage.matches) {
          result.add(
            PlayEntry(
              match,
              index,
              '${stage.name} · ${stageMatchName(stage, match)}',
            ),
          );
        }
      }
    }
    return result;
  }

  List<PlayEntry> orderedEntriesForStage(
    CreatedTournament tournament,
    int stageIndex, {
    Set<GroupMatch> prioritizedMatches = const {},
    Set<GroupMatch> deprioritizedMatches = const {},
  }) {
    final stageEntries = entries(
      tournament,
    ).where((entry) => entry.stageIndex == stageIndex).toList();
    if (tournament.directorPlayOrderMode != 'dynamic') {
      final originalOrder = {
        for (var index = 0; index < stageEntries.length; index++)
          stageEntries[index]: index,
      };
      stageEntries.sort((a, b) {
        final scheduleOrder = (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
          b.match.fixedScheduleOrder ?? 1 << 30,
        );
        return scheduleOrder != 0
            ? scheduleOrder
            : originalOrder[a]!.compareTo(originalOrder[b]!);
      });
      return stageEntries;
    }

    final schedule = plan(tournament, stageIndex);
    final blockForMatch = <GroupMatch, int>{
      for (final entry in schedule.running) entry.match: -1,
      for (final assignment in schedule.planned)
        assignment.entry.match: assignment.block,
    };
    final scheduledEntries = [
      ...schedule.running,
      ...schedule.planned.map((assignment) => assignment.entry),
      ...schedule.finished.where((entry) => entry.stageIndex == stageIndex),
      ...schedule.waiting.where((entry) => entry.stageIndex == stageIndex),
    ];
    final scheduleOrder = {
      for (var index = 0; index < scheduledEntries.length; index++)
        scheduledEntries[index].match: index,
    };
    final originalOrder = {
      for (var index = 0; index < stageEntries.length; index++)
        stageEntries[index].match: index,
    };
    stageEntries.sort((a, b) {
      final aBlock = blockForMatch[a.match] ?? 1 << 30;
      final bBlock = blockForMatch[b.match] ?? 1 << 30;
      if (aBlock != bBlock) return aBlock.compareTo(bBlock);
      final aPriority = prioritizedMatches.contains(a.match);
      final bPriority = prioritizedMatches.contains(b.match);
      if (aPriority != bPriority) return aPriority ? -1 : 1;
      final aDeprioritized = deprioritizedMatches.contains(a.match);
      final bDeprioritized = deprioritizedMatches.contains(b.match);
      if (aDeprioritized != bDeprioritized) return aDeprioritized ? 1 : -1;
      final aOrder = scheduleOrder[a.match] ?? 1 << 30;
      final bOrder = scheduleOrder[b.match] ?? 1 << 30;
      return aOrder != bOrder
          ? aOrder.compareTo(bOrder)
          : originalOrder[a.match]!.compareTo(originalOrder[b.match]!);
    });
    return stageEntries;
  }

  BoardSchedule plan(
    CreatedTournament tournament,
    int activeStage, {
    Set<int> additionalBlockedBoards = const {},
  }) {
    if (tournament.boardCount < 1 || tournament.boardCount > 64) {
      throw ArgumentError.value(tournament.boardCount, 'boardCount');
    }
    final all = entries(tournament);
    if (tournament.directorPlayOrderMode != 'dynamic') {
      all.sort((a, b) {
        final order = (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
          b.match.fixedScheduleOrder ?? 1 << 30,
        );
        return order != 0 ? order : a.stageIndex.compareTo(b.stageIndex);
      });
    }
    final finished =
        all
            .where((e) => e.stageIndex <= activeStage && e.match.isResolved)
            .toList()
          ..sort(
            (a, b) => (a.match.finishedAt ?? DateTime(1970)).compareTo(
              b.match.finishedAt ?? DateTime(1970),
            ),
          );
    final running =
        all
            .where(
              (e) =>
                  e.stageIndex == activeStage &&
                  !e.match.isResolved &&
                  e.match.hasPlayers &&
                  e.match.startedAt != null &&
                  e.match.finishedAt == null &&
                  e.match.startedPlayers == e.playerSignature &&
                  e.match.boardNumber != null,
            )
            .toList()
          ..sort((a, b) => a.match.startedAt!.compareTo(b.match.startedAt!));
    final pending = all
        .where(
          (e) =>
              e.stageIndex == activeStage &&
              e.match.hasPlayers &&
              !e.match.isResolved &&
              !running.contains(e),
        )
        .toList();
    final waiting = all
        .where(
          (e) =>
              !finished.contains(e) &&
              !pending.contains(e) &&
              !running.contains(e),
        )
        .toList();
    final planned = const BoardSchedulingEngine().schedule(
      all: all,
      ready: pending,
      running: running,
      finished: finished,
      boardCount: tournament.boardCount,
      blockedBoards: {
        if (tournament.directorModeEnabled) ...tournament.blockedBoards,
        ...additionalBlockedBoards,
      },
      preferredBoardsByGroup: tournament.groupBoardAssignments,
      strategy: tournament.directorPlayOrderMode != 'dynamic'
          ? 'sequence'
          : tournament.directorModeEnabled
          ? tournament.directorSchedulingStrategy
          : 'group',
      assignGroupsToBoards:
          tournament.directorModeEnabled &&
          tournament.directorSchedulingStrategy == 'group',
      groupBoardAssignments: {
        for (final entry in tournament.directorGroupBoardAssignments.entries)
          entry.key: entry.value.toSet(),
      },
      allowGroupBoardExpansion:
          tournament.directorMultiBoardAssignmentBehavior != 'mirror',
    );
    return BoardSchedule(planned, running, finished, waiting);
  }

  /// Creates a persisted, complete queue once, including future pairing slots.
  void initializeFixedSchedule(CreatedTournament tournament) {
    final all = entries(tournament);
    final ordered = all
        .where((entry) => entry.match.fixedScheduleOrder != null)
        .toList();
    if (ordered.length == all.length) return;
    if (ordered.isNotEmpty) {
      var nextOrder =
          ordered
              .map((entry) => entry.match.fixedScheduleOrder!)
              .reduce((a, b) => a > b ? a : b) +
          1;
      for (final entry in all.where(
        (entry) => entry.match.fixedScheduleOrder == null,
      )) {
        entry.match.fixedScheduleOrder = nextOrder++;
      }
      return;
    }
    final schedule = <PlayEntry>[];
    final stageIndexes = all.map((entry) => entry.stageIndex).toSet().toList()
      ..sort();
    for (final stageIndex in stageIndexes) {
      final stageEntries = all
          .where((entry) => entry.stageIndex == stageIndex)
          .toList();
      final known = stageEntries
          .where((entry) => entry.match.hasPlayers)
          .toList();
      final groupKeys = stageEntries
          .map((entry) => entry.groupKey)
          .whereType<String>()
          .toSet()
          .toList();
      final defaultAssignments = GroupBoardAssignment.defaults(
        groupNames: groupKeys,
        boardCount: tournament.boardCount,
      );
      final groupAssignments = <String, Set<int>>{
        for (final groupKey in groupKeys)
          groupKey:
              (tournament.directorGroupBoardAssignments[groupKey] ??
                      defaultAssignments[groupKey] ??
                      const <int>{})
                  .toSet(),
      };
      final assignments = const BoardSchedulingEngine().schedule(
        all: stageEntries,
        ready: known,
        boardCount: tournament.boardCount,
        blockedBoards: tournament.blockedBoards,
        preferredBoardsByGroup: tournament.groupBoardAssignments,
        strategy:
            tournament.directorModeEnabled &&
                tournament.directorSchedulingStrategy == 'global'
            ? 'global'
            : 'sequence',
        assignGroupsToBoards:
            tournament.directorModeEnabled &&
            tournament.directorSchedulingStrategy == 'group' &&
            stageEntries.every((entry) => entry.groupKey != null),
        groupBoardAssignments: groupAssignments,
        allowGroupBoardExpansion:
            tournament.directorMultiBoardAssignmentBehavior != 'mirror',
      );
      schedule.addAll(assignments.map((assignment) => assignment.entry));
      schedule.addAll(stageEntries.where((entry) => !known.contains(entry)));
    }
    for (var index = 0; index < schedule.length; index++) {
      schedule[index].match.fixedScheduleOrder = index;
    }
  }

  bool moveFixedScheduleMatch(
    CreatedTournament tournament,
    GroupMatch match, {
    required int targetIndex,
  }) {
    final all = entries(tournament)
      ..sort(
        (a, b) => (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
          b.match.fixedScheduleOrder ?? 1 << 30,
        ),
      );
    final stageIndex = all
        .where((entry) => identical(entry.match, match))
        .firstOrNull
        ?.stageIndex;
    if (stageIndex == null || match.isResolved) return false;
    if (match.startedAt != null && match.finishedAt == null) return false;
    final stageEntries = all
        .where((entry) => entry.stageIndex == stageIndex)
        .toList();
    final running = stageEntries
        .where(
          (entry) =>
              entry.match.startedAt != null &&
              entry.match.finishedAt == null &&
              !entry.match.isResolved,
        )
        .toList();
    final pending = stageEntries
        .where((entry) => !running.contains(entry))
        .toList();
    final index = pending.indexWhere((entry) => identical(entry.match, match));
    if (index < 0) return false;
    final entry = pending.removeAt(index);
    final pendingTarget = (targetIndex - running.length).clamp(
      0,
      pending.length,
    );
    pending.insert(pendingTarget, entry);
    final reorderedStage = [...running, ...pending];
    final allIndex = all.indexWhere((item) => item.stageIndex == stageIndex);
    all.removeWhere((item) => item.stageIndex == stageIndex);
    all.insertAll(allIndex, reorderedStage);
    for (var position = 0; position < all.length; position++) {
      all[position].match.fixedScheduleOrder = position;
    }
    return true;
  }

  bool deferFixedScheduleMatch(CreatedTournament tournament, GroupMatch match) {
    final all = entries(tournament);
    final stageIndex = all
        .where((entry) => identical(entry.match, match))
        .firstOrNull
        ?.stageIndex;
    if (stageIndex == null) return false;
    final stageEntries = all
        .where((entry) => entry.stageIndex == stageIndex)
        .toList();
    return moveFixedScheduleMatch(
      tournament,
      match,
      targetIndex: stageEntries.length - 1,
    );
  }

  /// Uses the existing fair queue, but checks availability now, not in a future block.
  BoardAssignment? suggestForPlayer(
    CreatedTournament tournament,
    int stage,
    TournamentPlayer player,
  ) {
    final schedule = plan(tournament, stage);
    final busy = {for (final entry in schedule.running) ...entry.players};
    final identities = player.individuals
        .map((p) => p.profileId ?? p.name)
        .toSet();
    if (identities.any(busy.contains)) return null;
    final occupied = {
      for (final entry in schedule.running) entry.match.boardNumber,
    };
    for (final assignment in schedule.planned) {
      final candidate = assignment.entry;
      if (candidate.players.any(identities.contains) &&
          !candidate.players.any(busy.contains) &&
          !occupied.contains(assignment.board) &&
          !tournament.blockedBoards.contains(assignment.board)) {
        return assignment;
      }
    }
    return null;
  }

  BoardAssignment? suggestForBoard(
    CreatedTournament tournament,
    int stage,
    int board,
  ) {
    if (board < 1 || board > tournament.boardCount) return null;
    if (tournament.blockedBoards.contains(board)) return null;
    final schedule = plan(tournament, stage);
    if (schedule.running.any((entry) => entry.match.boardNumber == board)) {
      return null;
    }

    final busy = {for (final entry in schedule.running) ...entry.players};
    for (final assignment in schedule.planned) {
      final entry = assignment.entry;
      if (assignment.board != board || entry.players.any(busy.contains)) {
        continue;
      }
      if (schedule.running.any(
        (runningEntry) =>
            runningEntry.match.boardNumber == board ||
            runningEntry.players.any(entry.players.contains),
      )) {
        continue;
      }
      return BoardAssignment(entry, assignment.block, board);
    }
    return null;
  }

  bool start(
    CreatedTournament tournament,
    int stage,
    GroupMatch match,
    int board, {
    DateTime? startedAt,
  }) {
    final schedule = plan(tournament, stage);
    final candidates = schedule.planned.where(
      (a) => identical(a.entry.match, match),
    );
    if (candidates.isEmpty ||
        board < 1 ||
        board > tournament.boardCount ||
        tournament.blockedBoards.contains(board) ||
        tournament.completedStageIndexes.contains(stage)) {
      return false;
    }
    final entry = candidates.first.entry;
    if (schedule.running.any(
      (e) =>
          e.match.boardNumber == board || e.players.any(entry.players.contains),
    )) {
      return false;
    }
    match.boardNumber = board;
    match.startedAt = startedAt ?? DateTime.now();
    match.startedPlayers = entry.playerSignature;
    match.finishedAt = null;
    return true;
  }

  bool resetRunningMatch(
    CreatedTournament tournament,
    int stage,
    GroupMatch match,
  ) {
    if (match.hasResult ||
        !plan(tournament, stage).running.any((entry) => entry.match == match)) {
      return false;
    }
    match
      ..boardNumber = null
      ..startedAt = null
      ..startedPlayers = null
      ..finishedAt = null
      ..homeLegs = null
      ..awayLegs = null
      ..homeSets = null
      ..awaySets = null
      ..bestPerformances = [];
    return true;
  }

  bool moveRunningMatch(
    CreatedTournament tournament,
    int stage,
    GroupMatch match,
    int board,
  ) {
    if (board < 1 ||
        board > tournament.boardCount ||
        tournament.blockedBoards.contains(board) ||
        tournament.completedStageIndexes.contains(stage)) {
      return false;
    }
    final running = plan(tournament, stage);
    final matchIsRunning = running.running.any(
      (entry) => identical(entry.match, match),
    );
    if (!matchIsRunning) return false;
    if (match.boardNumber == board) return true;
    if (running.running.any((entry) => entry.match.boardNumber == board)) {
      return false;
    }
    match.boardNumber = board;
    return true;
  }

  void resultRecorded(GroupMatch match) {
    if (match.isResolved) {
      match.finishedAt ??= DateTime.now();
    } else {
      match.finishedAt = null;
      match.startedAt = null;
      match.boardNumber = null;
      match.startedPlayers = null;
    }
  }
}
