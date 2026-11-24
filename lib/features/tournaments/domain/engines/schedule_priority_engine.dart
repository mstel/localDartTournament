import 'board_scheduling_engine.dart';

/// Progress of one group for scheduling decisions.
///
/// The three stages are deliberately kept separate: a match in the preview is
/// not a played match, and a running match is not a finished match.
class SchedulePriorityGroup {
  const SchedulePriorityGroup({
    required this.key,
    required this.total,
    required this.completed,
    required this.running,
    required this.projected,
  });

  final String key;
  final int total;
  final int completed;
  final int running;
  final int projected;

  int get remaining =>
      (total - completed - running - projected).clamp(0, 1 << 30);

  /// Lower means this group is further behind and should be preferred.
  ///
  /// Projected matches count less than running matches, running matches less
  /// than completed matches. Absolute remaining work is compared separately so
  /// a small group is not preferred only because its percentage is lower.
  double get progressScore =>
      total == 0 ? 0 : (completed + running * 0.5 + projected * 0.25) / total;
}

/// Immutable input for [SchedulePriorityEngine].
///
/// Callers build this once per re-evaluation, so both fixed schedule creation
/// and the dynamic waitlist use exactly the same criteria and counters.
class SchedulePriorityContext {
  SchedulePriorityContext({
    required this.now,
    required this.fallbackLastEndedAt,
    required this.originalOrder,
    required this.lastEndedAt,
    required this.playedCounts,
    required this.remainingCounts,
    required this.groups,
  });

  final DateTime now;
  final DateTime fallbackLastEndedAt;
  final Map<PlayEntry, int> originalOrder;
  final Map<String, DateTime> lastEndedAt;
  final Map<String, int> playedCounts;
  final Map<String, int> remainingCounts;
  final Map<String, SchedulePriorityGroup> groups;

  factory SchedulePriorityContext.build({
    required List<PlayEntry> all,
    required List<PlayEntry> finished,
    required List<PlayEntry> running,
    Iterable<PlayEntry> projected = const [],
    DateTime? now,
    DateTime? fallbackLastEndedAt,
    String Function(PlayEntry entry)? groupKeyOf,
  }) {
    final reference = now ?? DateTime.now();
    final fallback =
        fallbackLastEndedAt ?? reference.subtract(const Duration(days: 365));
    final groupKey =
        groupKeyOf ??
        (PlayEntry entry) =>
            entry.groupKey ?? '${entry.stageIndex}:turnierweit';
    final order = <PlayEntry, int>{
      for (var index = 0; index < all.length; index++) all[index]: index,
    };
    final lastEnded = <String, DateTime>{};
    final played = <String, int>{};
    final remaining = <String, int>{};
    final groupTotals = <String, int>{};
    final groupCompleted = <String, int>{};
    final groupRunning = <String, int>{};
    final groupProjected = <String, int>{};

    for (final entry in all) {
      if (!entry.match.hasPlayers) continue;
      final key = groupKey(entry);
      groupTotals[key] = (groupTotals[key] ?? 0) + 1;
      if (!entry.match.isResolved) {
        for (final player in entry.players) {
          remaining[player] = (remaining[player] ?? 0) + 1;
        }
      }
    }
    for (final entry in finished) {
      if (!entry.match.hasResult) continue;
      final key = groupKey(entry);
      groupCompleted[key] = (groupCompleted[key] ?? 0) + 1;
      final ended = entry.match.finishedAt ?? fallback;
      for (final player in entry.players) {
        played[player] = (played[player] ?? 0) + 1;
        final previous = lastEnded[player];
        if (previous == null || previous.isBefore(ended)) {
          lastEnded[player] = ended;
        }
      }
    }
    for (final entry in running) {
      final key = groupKey(entry);
      groupRunning[key] = (groupRunning[key] ?? 0) + 1;
      for (final player in entry.players) {
        played[player] = (played[player] ?? 0) + 1;
        lastEnded[player] = reference;
      }
    }
    for (final entry in projected) {
      final key = groupKey(entry);
      groupProjected[key] = (groupProjected[key] ?? 0) + 1;
    }

    return SchedulePriorityContext(
      now: reference,
      fallbackLastEndedAt: fallback,
      originalOrder: order,
      lastEndedAt: Map<String, DateTime>.unmodifiable(lastEnded),
      playedCounts: Map<String, int>.unmodifiable(played),
      remainingCounts: Map<String, int>.unmodifiable(remaining),
      groups: Map<String, SchedulePriorityGroup>.unmodifiable({
        for (final entry in groupTotals.entries)
          entry.key: SchedulePriorityGroup(
            key: entry.key,
            total: entry.value,
            completed: groupCompleted[entry.key] ?? 0,
            running: groupRunning[entry.key] ?? 0,
            projected: groupProjected[entry.key] ?? 0,
          ),
      }),
    );
  }
}

/// The single scoring function used by all schedule strategies.
///
/// Player collisions are a hard constraint and must be filtered by the caller
/// before calling [sorted]. The remaining criteria are applied in this order:
/// waiting time, group progress (including absolute remaining work), player
/// load, remaining matches and finally the original entry order.
class SchedulePriorityEngine {
  const SchedulePriorityEngine();

  List<PlayEntry> sorted(
    Iterable<PlayEntry> entries,
    SchedulePriorityContext context,
  ) {
    final result = entries.toList();
    result.sort((a, b) => compare(a, b, context: context));
    return result;
  }

  int compare(
    PlayEntry a,
    PlayEntry b, {
    required SchedulePriorityContext context,
  }) {
    final waitComparison = _waitingSinceLastMatch(
      b,
      context,
    ).compareTo(_waitingSinceLastMatch(a, context));
    if (waitComparison != 0) return waitComparison;

    final aGroup = context.groups[a.groupKey ?? '${a.stageIndex}:turnierweit'];
    final bGroup = context.groups[b.groupKey ?? '${b.stageIndex}:turnierweit'];
    if (aGroup != null || bGroup != null) {
      final progress = (aGroup?.progressScore ?? 0).compareTo(
        bGroup?.progressScore ?? 0,
      );
      if (progress != 0) return progress;
      final workload = (bGroup?.remaining ?? 0).compareTo(
        aGroup?.remaining ?? 0,
      );
      if (workload != 0) return workload;
      final size = (bGroup?.total ?? 0).compareTo(aGroup?.total ?? 0);
      if (size != 0) return size;
    }

    final aCounts =
        a.players
            .map((player) => (context.playedCounts[player] ?? 0) + 1)
            .toList()
          ..sort();
    final bCounts =
        b.players
            .map((player) => (context.playedCounts[player] ?? 0) + 1)
            .toList()
          ..sort();
    final maxPlayed = (aCounts.isEmpty ? 0 : aCounts.last).compareTo(
      bCounts.isEmpty ? 0 : bCounts.last,
    );
    if (maxPlayed != 0) return maxPlayed;
    final sumPlayed = aCounts
        .fold<int>(0, (sum, value) => sum + value)
        .compareTo(bCounts.fold<int>(0, (sum, value) => sum + value));
    if (sumPlayed != 0) return sumPlayed;

    final aRemaining = a.players.fold<int>(
      0,
      (sum, player) => sum + (context.remainingCounts[player] ?? 0),
    );
    final bRemaining = b.players.fold<int>(
      0,
      (sum, player) => sum + (context.remainingCounts[player] ?? 0),
    );
    final remaining = bRemaining.compareTo(aRemaining);
    if (remaining != 0) return remaining;

    return (context.originalOrder[a] ?? 1 << 30).compareTo(
      context.originalOrder[b] ?? 1 << 30,
    );
  }

  /// Real time since the last finished match, not the number of past matches.
  /// Players without a previous match use [SchedulePriorityContext.fallbackLastEndedAt].
  Duration waitingSinceLastMatch(
    PlayEntry entry,
    SchedulePriorityContext context,
  ) => _waitingSinceLastMatch(entry, context);

  Duration _waitingSinceLastMatch(
    PlayEntry entry,
    SchedulePriorityContext context,
  ) {
    if (entry.players.isEmpty) return Duration.zero;
    final ends = entry.players
        .map((player) => context.lastEndedAt[player])
        .whereType<DateTime>()
        .toList();
    if (ends.isEmpty) {
      return context.now.difference(context.fallbackLastEndedAt);
    }
    final earliest = ends.reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = context.now.difference(earliest);
    return wait.isNegative ? Duration.zero : wait;
  }
}
