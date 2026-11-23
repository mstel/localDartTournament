import 'dart:convert';

import '../tournament_models.dart';
import 'board_scheduling_engine.dart';

/// One group's progress in the shared waiting list.
///
/// [completed] is the displayed finished/total value. [running] and [fixed]
/// are included in [balanceScore] so currently occupied players and already
/// committed matches influence the optimisation without being reported as
/// finished results.
class GlobalWaitlistGroupProgress {
  const GlobalWaitlistGroupProgress({
    required this.key,
    required this.label,
    required this.total,
    required this.completed,
    required this.running,
    required this.fixed,
  });

  final String key;
  final String label;
  final int total;
  final int completed;
  final int running;
  final int fixed;

  double get displayedRatio => total == 0 ? 0 : completed / total;

  double get balanceScore =>
      total == 0 ? 0 : (completed + running * 0.5 + fixed * 0.5) / total;

  String get progressLabel =>
      '$completed von $total Partien · ${(displayedRatio * 100).round()} %';

  bool get needsCatchUp {
    if (total == 0) return false;
    return completed < total && balanceScore < 0.5;
  }
}

/// Result of [GlobalWaitlistEngine.plan]. [fixed] is the persisted, immutable
/// preview; [dynamic] is the recalculated remainder behind that preview.
class GlobalWaitlistPlan {
  const GlobalWaitlistPlan({
    required this.fixed,
    required this.dynamic,
    required this.groupProgress,
    required this.fixedCount,
  });

  final List<PlayEntry> fixed;
  final List<PlayEntry> dynamic;
  final List<GlobalWaitlistGroupProgress> groupProgress;
  final int fixedCount;

  List<PlayEntry> get queue => [...fixed, ...dynamic];

  PlayEntry? get next => fixed.isEmpty ? dynamic.firstOrNull : fixed.first;

  bool get isEmpty => queue.isEmpty;
}

/// Testable planning engine for "Dynamisch + turnierweit optimiert".
///
/// There is no board assignment in this plan. The first [fixedCount] matches
/// form a stable, collision-free preview. Only the matches after that preview
/// are recalculated, using relative group progress, running and fixed matches,
/// player match counts and rest blocks.
class GlobalWaitlistEngine {
  const GlobalWaitlistEngine();

  bool applies(CreatedTournament tournament) =>
      tournament.leagueMatch == null &&
      tournament.directorModeEnabled &&
      tournament.directorPlayOrderMode == 'dynamic' &&
      tournament.directorSchedulingStrategy == 'global';

  GlobalWaitlistPlan plan(
    CreatedTournament tournament,
    int stage, {
    required List<PlayEntry> allEntries,
    required BoardSchedule schedule,
    bool Function(GroupMatch match)? isPreviewable,
    Set<GroupMatch> excludedMatches = const {},
    List<PlayEntry> additionalRunning = const [],
  }) {
    if (!applies(tournament)) {
      return GlobalWaitlistPlan(
        fixed: const [],
        dynamic: const [],
        groupProgress: const [],
        fixedCount: tournament.directorGlobalWaitlist.fixedCount,
      );
    }
    final previewable = isPreviewable ?? (match) => true;
    final state = tournament.directorGlobalWaitlist;
    final stageEntries = allEntries
        .where((entry) => entry.stageIndex == stage)
        .toList(growable: false);
    final keyByMatch = _keyIndex(stageEntries);
    final running = [
      ...schedule.running.where((entry) => entry.stageIndex == stage),
      ...additionalRunning.where((entry) => entry.stageIndex == stage),
    ];
    final runningMatches = {
      ...running.map((entry) => entry.match),
      ...excludedMatches,
    };
    final candidates = <PlayEntry>[];
    final seen = <GroupMatch>{};
    for (final assignment in schedule.planned) {
      final entry = assignment.entry;
      if (entry.stageIndex != stage || !seen.add(entry.match)) continue;
      if (_isPlayable(entry, runningMatches, previewable)) {
        candidates.add(entry);
      }
    }

    final matchByKey = {
      for (final item in keyByMatch.entries) item.value: item.key,
    };
    final entriesByMatch = <GroupMatch, PlayEntry>{
      for (final entry in stageEntries) entry.match: entry,
    };

    final busy = <String>{for (final entry in running) ...entry.players};
    final fixed = <PlayEntry>[];
    for (final key in state.fixedKeys(stage)) {
      final match = matchByKey[key];
      final entry = match == null ? null : entriesByMatch[match];
      if (entry == null || !_isPlayable(entry, runningMatches, previewable)) {
        continue;
      }
      if (entry.players.any(busy.contains)) continue;
      fixed.add(entry);
      busy.addAll(entry.players);
      if (fixed.length >= state.fixedCount) break;
    }

    final fixedMatches = fixed.map((entry) => entry.match).toSet();
    final availableCandidates = candidates
        .where((entry) => !fixedMatches.contains(entry.match))
        .toList(growable: false);
    final missing = state.fixedCount - fixed.length;
    if (missing > 0) {
      final additions = _select(
        candidates: availableCandidates,
        count: missing,
        locked: fixed,
        running: running,
        stageEntries: stageEntries,
        schedule: schedule,
        order: {for (var i = 0; i < candidates.length; i++) candidates[i]: i},
      );
      fixed.addAll(additions);
    }
    state.setFixedKeys(
      stage,
      fixed
          .map((entry) => keyByMatch[entry.match])
          .whereType<String>()
          .toList(),
    );
    final remainingMatches = fixed.map((entry) => entry.match).toSet();
    final dynamicEntries = _select(
      candidates: candidates
          .where((entry) => !remainingMatches.contains(entry.match))
          .toList(growable: false),
      count: (state.fixedCount * 2).clamp(4, 12),
      locked: fixed,
      running: running,
      stageEntries: stageEntries,
      schedule: schedule,
      order: {for (var i = 0; i < candidates.length; i++) candidates[i]: i},
    );

    return GlobalWaitlistPlan(
      fixed: List<PlayEntry>.unmodifiable(fixed),
      dynamic: List<PlayEntry>.unmodifiable(dynamicEntries),
      groupProgress: _groupProgress(
        stageEntries: stageEntries,
        running: running,
        fixed: fixed,
      ),
      fixedCount: state.fixedCount,
    );
  }

  /// Removes the started match from the fixed preview and refills it from the
  /// dynamic area. Called after a successful start so every start path uses
  /// the same behaviour.
  void recordStart(
    CreatedTournament tournament,
    int stage,
    GroupMatch match, {
    required List<PlayEntry> allEntries,
    required BoardSchedule schedule,
    bool Function(GroupMatch match)? isPreviewable,
  }) {
    if (!applies(tournament)) return;
    final startedEntry = allEntries
        .where((entry) => identical(entry.match, match))
        .firstOrNull;
    plan(
      tournament,
      stage,
      allEntries: allEntries,
      schedule: schedule,
      isPreviewable: isPreviewable,
      excludedMatches: {match},
      additionalRunning: startedEntry == null ? const [] : [startedEntry],
    );
  }

  bool _isPlayable(
    PlayEntry entry,
    Set<GroupMatch> running,
    bool Function(GroupMatch match) isPreviewable,
  ) =>
      entry.match.hasPlayers &&
      !entry.match.isResolved &&
      !running.contains(entry.match) &&
      isPreviewable(entry.match);

  List<GlobalWaitlistGroupProgress> _groupProgress({
    required List<PlayEntry> stageEntries,
    required List<PlayEntry> running,
    required List<PlayEntry> fixed,
  }) {
    final keys = <String>{for (final entry in stageEntries) _groupKey(entry)};
    final result = <GlobalWaitlistGroupProgress>[];
    for (final key in keys) {
      final entries = stageEntries.where((entry) => _groupKey(entry) == key);
      final known = entries.where((entry) => entry.match.hasPlayers).toList();
      final completed = known.where((entry) => entry.match.isResolved).length;
      final runningCount = running
          .where((entry) => _groupKey(entry) == key)
          .length;
      final fixedCount = fixed.where((entry) => _groupKey(entry) == key).length;
      result.add(
        GlobalWaitlistGroupProgress(
          key: key,
          label: _groupLabel(key),
          total: known.length,
          completed: completed,
          running: runningCount,
          fixed: fixedCount,
        ),
      );
    }
    result.sort((a, b) {
      final score = a.balanceScore.compareTo(b.balanceScore);
      if (score != 0) return score;
      final size = b.total.compareTo(a.total);
      return size != 0 ? size : a.label.compareTo(b.label);
    });
    return List<GlobalWaitlistGroupProgress>.unmodifiable(result);
  }

  List<PlayEntry> _select({
    required List<PlayEntry> candidates,
    required int count,
    required List<PlayEntry> locked,
    required List<PlayEntry> running,
    required List<PlayEntry> stageEntries,
    required BoardSchedule schedule,
    required Map<PlayEntry, int> order,
  }) {
    if (count <= 0 || candidates.isEmpty) return const [];

    final finished = schedule.finished
        .where((entry) => entry.stageIndex == candidates.first.stageIndex)
        .toList();
    final played = <String, int>{};
    final lastPlayed = <String, int>{};
    for (var index = 0; index < finished.length; index++) {
      for (final player in finished[index].players) {
        played[player] = (played[player] ?? 0) + 1;
        lastPlayed[player] = index - finished.length;
      }
    }
    for (final entry in running) {
      for (final player in entry.players) {
        played[player] = (played[player] ?? 0) + 1;
        lastPlayed[player] = 0;
      }
    }

    final groupStats = <String, _GroupCounters>{};
    for (final entry in stageEntries) {
      final key = _groupKey(entry);
      final stats = groupStats.putIfAbsent(key, () => _GroupCounters());
      if (!entry.match.hasPlayers) continue;
      stats.total++;
      if (entry.match.isResolved) stats.completed++;
    }
    for (final entry in running) {
      groupStats
          .putIfAbsent(_groupKey(entry), () => _GroupCounters())
          .running++;
    }
    for (final entry in locked) {
      final stats = groupStats.putIfAbsent(
        _groupKey(entry),
        () => _GroupCounters(),
      );
      stats.fixed++;
      for (final player in entry.players) {
        played[player] = (played[player] ?? 0) + 1;
        lastPlayed[player] = 0;
      }
    }

    final remainingCounts = <String, int>{};
    for (final entry in stageEntries) {
      if (entry.match.isResolved || !entry.match.hasPlayers) continue;
      for (final player in entry.players) {
        remainingCounts[player] = (remainingCounts[player] ?? 0) + 1;
      }
    }

    final busy = <String>{for (final entry in locked) ...entry.players};
    for (final entry in running) {
      busy.addAll(entry.players);
    }
    final selected = <PlayEntry>[];
    while (selected.length < count) {
      final available = candidates
          .where(
            (entry) =>
                !selected.contains(entry) && !entry.players.any(busy.contains),
          )
          .toList();
      if (available.isEmpty) break;
      final block = selected.length + 1;
      available.sort(
        (a, b) => _compare(
          a,
          b,
          block: block,
          groupStats: groupStats,
          played: played,
          lastPlayed: lastPlayed,
          remainingCounts: remainingCounts,
          order: order,
        ),
      );
      final winner = available.first;
      selected.add(winner);
      busy.addAll(winner.players);
      groupStats[_groupKey(winner)]!.fixed++;
      for (final player in winner.players) {
        played[player] = (played[player] ?? 0) + 1;
        lastPlayed[player] = block;
        remainingCounts[player] = (remainingCounts[player] ?? 1) - 1;
      }
    }
    return List<PlayEntry>.unmodifiable(selected);
  }

  int _compare(
    PlayEntry a,
    PlayEntry b, {
    required int block,
    required Map<String, _GroupCounters> groupStats,
    required Map<String, int> played,
    required Map<String, int> lastPlayed,
    required Map<String, int> remainingCounts,
    required Map<PlayEntry, int> order,
  }) {
    final aGroup = groupStats[_groupKey(a)] ?? _GroupCounters();
    final bGroup = groupStats[_groupKey(b)] ?? _GroupCounters();
    final progress = aGroup.balanceScore.compareTo(bGroup.balanceScore);
    if (progress != 0) return progress;
    final size = bGroup.total.compareTo(aGroup.total);
    if (size != 0) return size;

    final aCounts =
        a.players.map((player) => (played[player] ?? 0) + 1).toList()..sort();
    final bCounts =
        b.players.map((player) => (played[player] ?? 0) + 1).toList()..sort();
    final aMax = aCounts.isEmpty ? 0 : aCounts.last;
    final bMax = bCounts.isEmpty ? 0 : bCounts.last;
    final maxPlayed = aMax.compareTo(bMax);
    if (maxPlayed != 0) return maxPlayed;
    final aSum = aCounts.fold<int>(0, (sum, value) => sum + value);
    final bSum = bCounts.fold<int>(0, (sum, value) => sum + value);
    final sumPlayed = aSum.compareTo(bSum);
    if (sumPlayed != 0) return sumPlayed;

    final aRest = _minimumRest(a, block, lastPlayed);
    final bRest = _minimumRest(b, block, lastPlayed);
    final rest = bRest.compareTo(aRest);
    if (rest != 0) return rest;

    final aRemaining = a.players.fold<int>(
      0,
      (sum, player) => sum + (remainingCounts[player] ?? 0),
    );
    final bRemaining = b.players.fold<int>(
      0,
      (sum, player) => sum + (remainingCounts[player] ?? 0),
    );
    final remaining = bRemaining.compareTo(aRemaining);
    if (remaining != 0) return remaining;
    return (order[a] ?? 1 << 30).compareTo(order[b] ?? 1 << 30);
  }

  int _minimumRest(PlayEntry entry, int block, Map<String, int> lastPlayed) {
    if (entry.players.isEmpty) {
      return BoardSchedulingEngine.preferredPlayerRestBlocks;
    }
    return entry.players
        .map(
          (player) => lastPlayed[player] == null
              ? BoardSchedulingEngine.preferredPlayerRestBlocks
              : block - lastPlayed[player]!,
        )
        .reduce((a, b) => a < b ? a : b);
  }

  Map<GroupMatch, String> _keyIndex(List<PlayEntry> stageEntries) {
    final occurrences = <String, int>{};
    final result = <GroupMatch, String>{};
    for (final entry in stageEntries) {
      final base = _baseKey(entry);
      final occurrence = occurrences[base] ?? 0;
      occurrences[base] = occurrence + 1;
      result[entry.match] = '$base#$occurrence';
    }
    return result;
  }

  String _baseKey(PlayEntry entry) => jsonEncode([
    entry.stageIndex,
    entry.groupKey,
    entry.match.round,
    entry.match.label,
    entry.match.placementKey,
    entry.match.placementRank,
    entry.match.isDecider,
    entry.playerSignature,
  ]);

  String _groupKey(PlayEntry entry) =>
      entry.groupKey ?? '${entry.stageIndex}:turnierweit';

  String _groupLabel(String key) {
    final separator = key.indexOf(':');
    final name = separator >= 0 ? key.substring(separator + 1) : key;
    return name.startsWith('Gruppe ') ? name : 'Gruppe $name';
  }
}

class _GroupCounters {
  int total = 0;
  int completed = 0;
  int running = 0;
  int fixed = 0;

  double get balanceScore =>
      total == 0 ? 0 : (completed + running * 0.5 + fixed * 0.5) / total;
}
