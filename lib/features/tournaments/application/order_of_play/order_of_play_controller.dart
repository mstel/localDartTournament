import '../../domain/knockout_round_names.dart';
import '../../domain/tournament_models.dart';
import '../../domain/engines/board_scheduling_engine.dart';
export '../../domain/engines/board_scheduling_engine.dart';

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
                group.name,
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

  BoardSchedule plan(CreatedTournament tournament, int activeStage) {
    if (tournament.boardCount < 1 || tournament.boardCount > 64) {
      throw ArgumentError.value(tournament.boardCount, 'boardCount');
    }
    final all = entries(tournament);
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
      blockedBoards: tournament.blockedBoards,
      strategy: tournament.directorSchedulingStrategy,
    );
    return BoardSchedule(planned, running, finished, waiting);
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
    final board = [
      for (var b = 1; b <= tournament.boardCount; b++)
        if (!occupied.contains(b) && !tournament.blockedBoards.contains(b)) b,
    ].firstOrNull;
    if (board == null) return null;
    for (final assignment in schedule.planned) {
      final entry = assignment.entry;
      if (!entry.players.any(identities.contains) ||
          entry.players.any(busy.contains)) {
        continue;
      }
      return BoardAssignment(entry, 0, board);
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
      if (entry.players.any(busy.contains)) continue;
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
    int board,
  ) {
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
    match.startedAt = DateTime.now();
    match.startedPlayers = entry.playerSignature;
    match.finishedAt = null;
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
