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
              assignment.entry.match.hasPlayers,
        )
        .toList();
    if (tournament.directorPlayOrderMode == 'fixed_schedule' &&
        tournament.directorMultiBoardAssignmentBehavior == 'mirror' &&
        assignments.isNotEmpty) {
      final groupKey = assignments.first.entry.groupKey;
      if (groupKey != null) {
        return schedule.planned
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
    return assignments.take(4).toList();
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
    final defaults = GroupBoardAssignment.defaults(
      groupNames: groupNames,
      boardCount: tournament.boardCount,
    );
    return {
      for (final name in groupNames)
        if ((tournament.directorGroupBoardAssignments[tournamentGroupBoardKey(
                      stage,
                      name,
                    )] ??
                    defaults[name]?.toList() ??
                    const <int>[])
                .toSet()
                .where((board) => board >= 1 && board <= tournament.boardCount)
                .length >
            1)
          tournamentGroupBoardKey(stage, name): List<int>.unmodifiable(
            (tournament.directorGroupBoardAssignments[tournamentGroupBoardKey(
                      stage,
                      name,
                    )] ??
                    defaults[name]?.toList() ??
                    const <int>[])
                .toSet()
                .where((board) => board >= 1 && board <= tournament.boardCount)
                .toList()
              ..sort(),
          ),
    };
  }

  List<BoardAssignment> upcomingForBoards(
    List<int> boards, {
    required String groupKey,
    int limit = 6,
  }) => schedule.planned
      .where(
        (assignment) =>
            assignment.entry.stageIndex == stage &&
            assignment.entry.groupKey == groupKey &&
            boards.contains(assignment.board) &&
            assignment.entry.match.hasPlayers,
      )
      .take(limit)
      .toList(growable: false);

  List<BoardAssignment> selectableForBoard(int board) {
    if (!freeBoards.contains(board)) return [];
    final busyPlayers = {
      for (final running in schedule.running) ...running.players,
    };
    final assignments = schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved &&
              !assignment.entry.players.any(busyPlayers.contains),
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
    final boardQueue = upcomingForBoard(board);
    final boardGroup = boardQueue.firstOrNull?.entry.groupKey;
    final candidates = selectableForBoard(board)
        .where(
          (assignment) =>
              boardGroup == null || assignment.entry.groupKey == boardGroup,
        )
        .toList();
    if (candidates.isEmpty) return null;
    final originalOrder = {
      for (var index = 0; index < candidates.length; index++)
        candidates[index]: index,
    };
    candidates.sort((a, b) {
      final blockOrder = a.block.compareTo(b.block);
      if (blockOrder != 0) return blockOrder;
      if (tournament.directorPlayOrderMode == 'dynamic') {
        final aPriority = _prioritizedMatches.contains(a.entry.match);
        final bPriority = _prioritizedMatches.contains(b.entry.match);
        if (aPriority != bPriority) return aPriority ? -1 : 1;
        final aDeprioritized = _deprioritizedMatches.contains(a.entry.match);
        final bDeprioritized = _deprioritizedMatches.contains(b.entry.match);
        if (aDeprioritized != bDeprioritized) {
          return aDeprioritized ? 1 : -1;
        }
      }
      return originalOrder[a]!.compareTo(originalOrder[b]!);
    });
    final recommended = candidates.first;
    final next = BoardAssignment(recommended.entry, recommended.block, board);
    final alternativeCandidate = candidates.skip(1).firstOrNull;
    final alternative = alternativeCandidate == null
        ? null
        : BoardAssignment(
            alternativeCandidate.entry,
            alternativeCandidate.block,
            board,
          );
    return TournamentDirectorBoardRecommendation(
      next: next,
      alternative: alternative,
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
