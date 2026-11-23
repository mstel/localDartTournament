import '../../domain/tournament_models.dart';
import 'order_of_play_controller.dart';

/// Stable, tournament-wide ("gruppenübergreifend") order-of-play state.
///
/// The scheduling engine deliberately recalculates the whole queue after a
/// result. For the dynamic global mode the Leitung and the second screen
/// nevertheless need one *fixed* suggestion per board that does not jump
/// around when a match is merely started. This service keeps that snapshot:
///
/// * the fingerprint only changes when a result (or the board configuration)
///   changes, so starting a match leaves the suggestions untouched;
/// * after a result the remaining open queue is recalculated in the background
///   and new, collision-free per-board suggestions are published.
class GlobalOrderOfPlayService {
  GlobalOrderOfPlayService({Map<String, GlobalOrderOfPlayPlan>? cache})
    : _cache = cache ?? <String, GlobalOrderOfPlayPlan>{};

  /// Shared instance used by the production snapshot.
  static final GlobalOrderOfPlayService instance = GlobalOrderOfPlayService();

  final Map<String, GlobalOrderOfPlayPlan> _cache;

  /// The stable per-board suggestions, including their origin and block.
  Map<int, BoardAssignment> boardAssignments(
    CreatedTournament tournament,
    int stage,
  ) => Map<int, BoardAssignment>.unmodifiable(
    _plan(tournament, stage).suggestions,
  );

  /// The stable per-board suggestions as board -> match, for simple consumers.
  Map<int, GroupMatch> boardSuggestions(
    CreatedTournament tournament,
    int stage,
  ) => {
    for (final entry in boardAssignments(tournament, stage).entries)
      entry.key: entry.value.entry.match,
  };

  /// All open matches in the recalculated global order. Matches that are
  /// already running are excluded so they are not announced twice.
  List<GroupMatch> remainingQueue(CreatedTournament tournament, int stage) =>
      List<GroupMatch>.unmodifiable(_plan(tournament, stage).remainingQueue);

  /// Drops cached state for one stage, e.g. after a stage reset.
  void invalidate(CreatedTournament tournament, int stage) =>
      _cache.remove(_key(tournament, stage));

  /// Drops all cached state, e.g. when a different tournament is loaded.
  void invalidateAll() => _cache.clear();

  /// Monotonically increasing generation of the cached plan (for diagnostics
  /// and tests). A new generation means a result or configuration change.
  int generation(CreatedTournament tournament, int stage) =>
      _plan(tournament, stage).generation;

  GlobalOrderOfPlayPlan _plan(CreatedTournament tournament, int stage) {
    final key = _key(tournament, stage);
    final fingerprint = _fingerprint(tournament, stage);
    final cached = _cache[key];
    if (cached != null && cached.fingerprint == fingerprint) return cached;

    const controller = OrderOfPlayController();
    final schedule = controller.plan(tournament, stage);
    final running = schedule.running.map((entry) => entry.match).toSet();
    final runningBoards = {
      for (final entry in schedule.running) entry.match.boardNumber,
    };
    final freeBoards = <int>{
      for (var board = 1; board <= tournament.boardCount; board++)
        if (!tournament.blockedBoards.contains(board) &&
            !runningBoards.contains(board))
          board,
    };

    final remaining = <GroupMatch>[];
    void addRemaining(GroupMatch match) {
      if (match.isResolved || !match.hasPlayers) return;
      if (running.contains(match) || remaining.contains(match)) return;
      remaining.add(match);
    }

    for (final assignment in schedule.planned) {
      if (assignment.entry.stageIndex == stage) {
        addRemaining(assignment.entry.match);
      }
    }
    for (final entry in controller.entries(tournament)) {
      if (entry.stageIndex == stage) addRemaining(entry.match);
    }

    // The engine already keeps the first block collision free. The extra pass
    // guards against assignments added by hand or by a future strategy change:
    // a colliding suggestion is deferred into the remaining queue instead of
    // being shown as fixed on a second board.
    final used = <String>{
      for (final entry in schedule.running) ...entry.players,
    };
    final suggestions = <int, BoardAssignment>{};
    final firstBlock = <BoardAssignment>[
      for (final assignment in schedule.planned)
        if (assignment.entry.stageIndex == stage &&
            assignment.block == 0 &&
            freeBoards.contains(assignment.board))
          assignment,
    ]..sort((a, b) => a.board.compareTo(b.board));
    for (final assignment in firstBlock) {
      if (assignment.entry.players.any(used.contains)) continue;
      suggestions[assignment.board] = assignment;
      used.addAll(assignment.entry.players);
    }

    final plan = GlobalOrderOfPlayPlan(
      fingerprint: fingerprint,
      generation: (cached?.generation ?? 0) + 1,
      suggestions: suggestions,
      remainingQueue: remaining,
    );
    _cache[key] = plan;
    return plan;
  }

  String _key(CreatedTournament tournament, int stage) =>
      '${tournament.id}:$stage';

  String _fingerprint(CreatedTournament tournament, int stage) {
    final buffer = StringBuffer()
      ..writeln(tournament.boardCount)
      ..writeln((tournament.blockedBoards.toList()..sort()).join(','))
      ..writeln(tournament.directorPlayOrderMode)
      ..writeln(tournament.directorSchedulingStrategy)
      ..writeln(stage);
    for (final entry in const OrderOfPlayController().entries(tournament)) {
      if (entry.stageIndex != stage) continue;
      final match = entry.match;
      buffer
        ..writeln(match.fixedScheduleOrder ?? -1)
        ..writeln(match.isResolved ? '1' : '0')
        ..writeln(match.finishedAt?.microsecondsSinceEpoch ?? 0);
    }
    return buffer.toString();
  }
}

/// Internal cache entry of [GlobalOrderOfPlayService]. Public only so the
/// injectable cache type does not leak a private type through the constructor.
class GlobalOrderOfPlayPlan {
  const GlobalOrderOfPlayPlan({
    required this.fingerprint,
    required this.generation,
    required this.suggestions,
    required this.remainingQueue,
  });

  final String fingerprint;
  final int generation;
  final Map<int, BoardAssignment> suggestions;
  final List<GroupMatch> remainingQueue;
}
