import '../../domain/engines/board_scheduling_engine.dart';
import '../../domain/engines/schedule_priority_engine.dart';
import '../../domain/tournament_models.dart';

/// Shared, read-only source for fixed + tournament-wide suggestions.
///
/// The simulated board of a planned assignment is only a planning aid. A fixed
/// global schedule has no reserved boards, so the same collision-free list is
/// offered on every free board. Display, quick start and manual selection all
/// use this class to avoid drifting apart after a match starts.
class FixedGlobalSuggestions {
  const FixedGlobalSuggestions();

  List<BoardAssignment> plan({
    required CreatedTournament tournament,
    required int stage,
    required List<PlayEntry> entries,
    required BoardSchedule schedule,
    required bool Function(GroupMatch match) isPreviewable,
    int limit = 16,
  }) {
    if (tournament.leagueMatch != null ||
        !tournament.directorModeEnabled ||
        tournament.directorPlayOrderMode != 'fixed_schedule' ||
        tournament.directorSchedulingStrategy != 'global' ||
        limit <= 0) {
      return const <BoardAssignment>[];
    }
    final stageEntries = entries
        .where((entry) => entry.stageIndex == stage && entry.match.hasPlayers)
        .toList(growable: false);
    final priorityContext = SchedulePriorityContext.build(
      all: stageEntries,
      finished: schedule.finished.where((e) => e.stageIndex == stage).toList(),
      running: schedule.blockingRunning,
    );
    const priority = SchedulePriorityEngine();
    final candidates = <BoardAssignment>[
      for (final assignment in schedule.planned)
        if (assignment.entry.stageIndex == stage &&
            assignment.entry.match.hasPlayers &&
            !assignment.entry.match.isResolved &&
            isPreviewable(assignment.entry.match))
          assignment,
    ];
    candidates.sort((a, b) {
      final fixedOrder = (a.entry.match.fixedScheduleOrder ?? 1 << 30)
          .compareTo(b.entry.match.fixedScheduleOrder ?? 1 << 30);
      return fixedOrder != 0
          ? fixedOrder
          : priority.compare(a.entry, b.entry, context: priorityContext);
    });

    final used = <String>{
      for (final entry in schedule.blockingRunning) ...entry.players,
    };
    final result = <BoardAssignment>[];
    for (final assignment in candidates) {
      if (assignment.entry.players.any(used.contains)) continue;
      result.add(assignment);
      used.addAll(assignment.entry.players);
      if (result.length >= limit) break;
    }
    return result;
  }
}
