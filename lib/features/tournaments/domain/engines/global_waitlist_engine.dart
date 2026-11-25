import 'dart:convert';

import '../tournament_models.dart';
import 'board_scheduling_engine.dart';
import 'schedule_priority_engine.dart';

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

  int get remaining => (total - completed - running - fixed).clamp(0, 1 << 30);

  double get displayedRatio => total == 0 ? 0 : completed / total;

  double get balanceScore =>
      total == 0 ? 0 : (completed + running * 0.5 + fixed * 0.25) / total;

  String get progressLabel =>
      '$completed von $total Partien · ${(displayedRatio * 100).round()} %';

  bool get needsCatchUp {
    if (total == 0) return false;
    return completed < total && balanceScore < 0.5;
  }
}

/// Result of [GlobalWaitlistEngine.plan]. [fixed] is the persisted preview
/// (including temporarily [skipped] entries); [dynamic] is the recalculated,
/// compact remainder behind that preview.
class GlobalWaitlistPlan {
  const GlobalWaitlistPlan({
    required this.fixed,
    required this.skipped,
    required this.dynamic,
    required this.groupProgress,
    required this.fixedCount,
  });

  final List<PlayEntry> fixed;
  final List<PlayEntry> skipped;
  final List<PlayEntry> dynamic;
  final List<GlobalWaitlistGroupProgress> groupProgress;
  final int fixedCount;

  List<PlayEntry> get queue => [...fixed, ...dynamic];

  /// Entries can come from different snapshots, so identity is defined by the
  /// underlying match rather than by the [PlayEntry] instance.
  bool isSkipped(PlayEntry entry) =>
      skipped.any((item) => identical(item.match, entry.match));

  PlayEntry? get next {
    for (final entry in fixed) {
      if (!isSkipped(entry)) return entry;
    }
    return dynamic.firstOrNull;
  }

  bool get isEmpty => queue.isEmpty;
}

/// Testable planning engine for "Dynamisch + turnierweit optimiert".
///
/// [plan] is deliberately pure: it reads the persisted fixed keys but never
/// writes them. Callers persist the preview explicitly through
/// `OrderOfPlayController.initializeGlobalWaitlist` or [recordStart].
///
/// There is no board assignment in this plan. The persisted preview is kept
/// stable (busy entries are shown as SKIPPED instead of being replaced); all
/// other currently open, playable entries are evaluated with the shared
/// [SchedulePriorityEngine] and only a compact remainder is displayed.
class GlobalWaitlistEngine {
  const GlobalWaitlistEngine();

  /// The number of recalculated entries shown after the fixed preview.
  static const dynamicPreviewCount = 4;

  /// Dynamic play order is always global. A persisted legacy "dynamic +
  /// group" selection is normalised by the model layer, but accepting it here
  /// keeps old data consistent.
  bool applies(CreatedTournament tournament) =>
      tournament.leagueMatch == null &&
      tournament.directorModeEnabled &&
      tournament.directorPlayOrderMode == 'dynamic';

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
      return _emptyPlan(tournament.directorGlobalWaitlist.fixedCount);
    }
    return _buildPlan(
      tournament,
      stage,
      allEntries: allEntries,
      schedule: schedule,
      previewable: isPreviewable ?? (match) => true,
      fixedKeys: tournament.directorGlobalWaitlist.fixedKeys(stage),
      excludedMatches: excludedMatches,
      additionalRunning: additionalRunning,
    );
  }

  /// Writes the compact preview of [waitlistPlan] to the versioned state.
  ///
  /// Kept separate from [plan] so reads (snapshots, second screen, dev tools)
  /// never mutate the tournament.
  void persistFixedKeys(
    CreatedTournament tournament,
    int stage,
    GlobalWaitlistPlan waitlistPlan, {
    required List<PlayEntry> allEntries,
  }) {
    if (!applies(tournament)) return;
    final stageEntries = allEntries
        .where((entry) => entry.stageIndex == stage)
        .toList(growable: false);
    final keyByMatch = _keyIndex(stageEntries);
    final limit = tournament.directorGlobalWaitlist.fixedCount.clamp(1, 12);
    final keys = waitlistPlan.fixed
        .map((entry) => keyByMatch[entry.match])
        .whereType<String>()
        .take(limit)
        .toList();
    tournament.directorGlobalWaitlist.setFixedKeys(stage, keys);
  }

  /// Removes the started match from the preview and refills the free slot from
  /// the dynamically evaluated area. Every other preview entry (including a
  /// temporarily busy one) keeps its position and its persisted key.
  void recordStart(
    CreatedTournament tournament,
    int stage,
    GroupMatch match, {
    required List<PlayEntry> allEntries,
    required BoardSchedule schedule,
    bool Function(GroupMatch match)? isPreviewable,
  }) {
    if (!applies(tournament)) return;
    final stageEntries = allEntries
        .where((entry) => entry.stageIndex == stage)
        .toList(growable: false);
    final keyByMatch = _keyIndex(stageEntries);
    final startedKey = keyByMatch[match];
    final keptKeys = tournament.directorGlobalWaitlist
        .fixedKeys(stage)
        .where((key) => key != startedKey)
        .toList();
    final startedEntry = stageEntries
        .where((entry) => identical(entry.match, match))
        .firstOrNull;

    final waitlistPlan = _buildPlan(
      tournament,
      stage,
      allEntries: allEntries,
      schedule: schedule,
      previewable: isPreviewable ?? (match) => true,
      fixedKeys: keptKeys,
      excludedMatches: {match},
      additionalRunning: startedEntry == null ? const [] : [startedEntry],
    );
    persistFixedKeys(tournament, stage, waitlistPlan, allEntries: allEntries);
  }

  GlobalWaitlistPlan _buildPlan(
    CreatedTournament tournament,
    int stage, {
    required List<PlayEntry> allEntries,
    required BoardSchedule schedule,
    required bool Function(GroupMatch match) previewable,
    required List<String> fixedKeys,
    required Set<GroupMatch> excludedMatches,
    required List<PlayEntry> additionalRunning,
  }) {
    final state = tournament.directorGlobalWaitlist;
    final fixedCount = state.fixedCount.clamp(1, 12);
    final stageEntries = allEntries
        .where((entry) => entry.stageIndex == stage)
        .toList(growable: false);
    final keyByMatch = _keyIndex(stageEntries);
    final matchByKey = {
      for (final item in keyByMatch.entries) item.value: item.key,
    };
    final entriesByMatch = <GroupMatch, PlayEntry>{
      for (final entry in stageEntries) entry.match: entry,
    };
    // Every running match blocks its players and board until it finishes, even
    // when it belongs to another stage. Group counters below only use the
    // entries of the active stage.
    final running = [...schedule.blockingRunning, ...additionalRunning];
    final runningMatches = {
      ...running.map((entry) => entry.match),
      ...excludedMatches,
    };
    final finished = schedule.finished
        .where((entry) => entry.stageIndex == stage)
        .toList(growable: false);

    // Every currently open, playable entry is a candidate - not just the
    // matches that happen to appear in the board plan.
    final candidates = <PlayEntry>[];
    final seen = <GroupMatch>{};
    for (final entry in stageEntries) {
      if (!seen.add(entry.match)) continue;
      if (_isPlayable(entry, runningMatches, previewable)) {
        candidates.add(entry);
      }
    }

    final now = DateTime.now();
    final runningPlayers = <String>{
      for (final entry in running) ...entry.players,
    };

    // Resolve persisted keys. Finished/invalid entries are dropped; entries
    // whose players are busy elsewhere stay in the preview as SKIPPED.
    final fixed = <PlayEntry>[];
    final previewPlayers = <String>{};
    for (final key in fixedKeys) {
      if (fixed.length >= fixedCount) break;
      final match = matchByKey[key];
      final entry = match == null ? null : entriesByMatch[match];
      if (entry == null || !_isPlayable(entry, runningMatches, previewable)) {
        continue;
      }
      fixed.add(entry);
      previewPlayers.addAll(entry.players);
    }

    SchedulePriorityContext contextFor(Iterable<PlayEntry> projected) =>
        SchedulePriorityContext.build(
          all: stageEntries,
          finished: finished,
          running: running,
          projected: projected,
          now: now,
          groupKeyOf: _groupKey,
        );

    List<PlayEntry> select(
      Iterable<PlayEntry> source,
      int count,
      Iterable<PlayEntry> projected,
    ) => _select(
      candidates: source.toList(growable: false),
      count: count,
      busy: {...runningPlayers, ...previewPlayers},
      buildContext: (added) => contextFor([...projected, ...added]),
    );

    // The dynamically evaluated remainder is the refill pool for the preview.
    final fixedMatches = fixed.map((entry) => entry.match).toSet();
    var dynamicPreview = select(
      candidates.where((entry) => !fixedMatches.contains(entry.match)),
      dynamicPreviewCount,
      fixed,
    );

    final missing = fixedCount - fixed.length;
    if (missing > 0) {
      final refilled = <PlayEntry>[];
      for (final entry in dynamicPreview) {
        if (refilled.length >= missing) break;
        if (entry.players.any(
          (player) =>
              runningPlayers.contains(player) ||
              previewPlayers.contains(player),
        )) {
          continue;
        }
        refilled.add(entry);
        fixed.add(entry);
        previewPlayers.addAll(entry.players);
      }
      if (refilled.length < missing) {
        final stillAvailable = candidates.where(
          (entry) =>
              !fixed.map((item) => item.match).contains(entry.match) &&
              !refilled.contains(entry),
        );
        final extra = select(stillAvailable, missing - refilled.length, fixed);
        fixed.addAll(extra);
        previewPlayers.addAll(extra.expand((entry) => entry.players));
      }
    }

    final committedMatches = fixed.map((entry) => entry.match).toSet();
    dynamicPreview = select(
      candidates.where((entry) => !committedMatches.contains(entry.match)),
      dynamicPreviewCount,
      fixed,
    );

    final skipped = <PlayEntry>[
      for (final entry in [...fixed, ...dynamicPreview])
        if (entry.players.any(runningPlayers.contains)) entry,
    ];
    return GlobalWaitlistPlan(
      fixed: List<PlayEntry>.unmodifiable(fixed),
      skipped: List<PlayEntry>.unmodifiable(skipped),
      dynamic: List<PlayEntry>.unmodifiable(dynamicPreview),
      groupProgress: _groupProgress(
        stageEntries: stageEntries,
        running: running,
        fixed: fixed,
      ),
      fixedCount: fixedCount,
    );
  }

  GlobalWaitlistPlan _emptyPlan(int fixedCount) => GlobalWaitlistPlan(
    fixed: const [],
    skipped: const [],
    dynamic: const [],
    groupProgress: const [],
    fixedCount: fixedCount.clamp(1, 12),
  );

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
      final workload = b.remaining.compareTo(a.remaining);
      if (workload != 0) return workload;
      final size = b.total.compareTo(a.total);
      return size != 0 ? size : a.label.compareTo(b.label);
    });
    return List<GlobalWaitlistGroupProgress>.unmodifiable(result);
  }

  /// Selects entries with the shared priority engine. It first prefers matches
  /// whose players are free, then fills the sequential queue with the best
  /// remaining matches even when all players are currently busy. Those rows
  /// are marked skipped until their running games finish.
  List<PlayEntry> _select({
    required List<PlayEntry> candidates,
    required int count,
    required Set<String> busy,
    required SchedulePriorityContext Function(List<PlayEntry> added)
    buildContext,
  }) {
    if (count <= 0 || candidates.isEmpty) return const [];
    const scorer = SchedulePriorityEngine();
    final selected = <PlayEntry>[];
    final used = <String>{...busy};
    while (selected.length < count) {
      final available = candidates
          .where(
            (entry) =>
                !selected.contains(entry) && !entry.players.any(used.contains),
          )
          .toList(growable: false);
      final pool = available.isEmpty
          ? candidates
                .where((entry) => !selected.contains(entry))
                .toList(growable: false)
          : available;
      if (pool.isEmpty) break;
      final winner = scorer.sorted(pool, buildContext(selected)).first;
      selected.add(winner);
      used.addAll(winner.players);
    }
    return List<PlayEntry>.unmodifiable(selected);
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
