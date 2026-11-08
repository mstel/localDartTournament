import '../domain/tournament_models.dart';
import '../domain/tournament_settings.dart';
import 'tournament_flow_priority.dart';
import '../domain/tournament_flow_priority_settings.dart';
import 'order_of_play/order_of_play_controller.dart';

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
  late final Set<GroupMatch> _prioritizedMatches =
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
      ).prioritizedMatches;

  List<BoardAssignment> upcomingForBoard(int board) => schedule.planned
      .where(
        (assignment) =>
            assignment.entry.stageIndex == stage &&
            assignment.board == board &&
            assignment.entry.match.hasPlayers,
      )
      .take(4)
      .toList();

  List<BoardAssignment> selectableForBoard(int board) {
    if (!freeBoards.contains(board)) return [];
    final busyPlayers = {
      for (final running in schedule.running) ...running.players,
    };
    return schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == stage &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved &&
              !assignment.entry.players.any(busyPlayers.contains),
        )
        .toList();
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
      final aPriority = _prioritizedMatches.contains(a.entry.match);
      final bPriority = _prioritizedMatches.contains(b.entry.match);
      if (aPriority != bPriority) return aPriority ? -1 : 1;
      final blockOrder = a.block.compareTo(b.block);
      return blockOrder != 0
          ? blockOrder
          : originalOrder[a]!.compareTo(originalOrder[b]!);
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
    final prioritized = TournamentFlowPriority.forStage(
      tournament.runStages[stage],
      settings: TournamentFlowPrioritySettings(
        playerMatchDeficitThreshold: settings.playerMatchDeficitThreshold,
        groupMatchDeficitThreshold: settings.groupMatchDeficitThreshold,
        usePercentageForGroups: settings.usePercentageForGroups,
      ),
    ).prioritizedMatches;
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
      final priority =
          prioritized.contains(a.entry.match) ==
              prioritized.contains(b.entry.match)
          ? 0
          : prioritized.contains(a.entry.match)
          ? -1
          : 1;
      if (priority != 0) return priority;
      final blockOrder = a.block.compareTo(b.block);
      if (blockOrder != 0) return blockOrder;
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
    return entries
        .where(
          (e) =>
              e.stageIndex == stage &&
              !e.match.isResolved &&
              (matches(e.match.homePlayer) || matches(e.match.awayPlayer)),
        )
        .toList()
      ..sort((a, b) {
        int order(PlayEntry e) =>
            schedule.running.any((r) => identical(r.match, e.match))
            ? -1
            : schedule.planned.indexWhere(
                (p) => identical(p.entry.match, e.match),
              );
        return order(a).compareTo(order(b));
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
