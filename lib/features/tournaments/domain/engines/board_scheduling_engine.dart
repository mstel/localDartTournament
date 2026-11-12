import '../tournament_models.dart';
import 'group_board_assignment.dart';

class PlayEntry {
  const PlayEntry(this.match, this.stageIndex, this.origin, [this.groupKey]);
  final GroupMatch match;
  final int stageIndex;
  final String origin;
  final String? groupKey;
  Set<String> get players => {
    if (match.isKratzer)
      ...match.players.expand(
        (player) => player.individuals.map((p) => p.profileId ?? p.name),
      ),
    if (match.homePlayer != null)
      ...match.homePlayer!.individuals.map((p) => p.profileId ?? p.name),
    if (match.awayPlayer != null)
      ...match.awayPlayer!.individuals.map((p) => p.profileId ?? p.name),
  };
  String get playerSignature => (players.toList()..sort()).join('\u0000');
}

class BoardAssignment {
  const BoardAssignment(this.entry, this.block, this.board);
  final PlayEntry entry;
  final int block;
  final int board;
}

class BoardSchedule {
  const BoardSchedule(this.planned, this.running, this.finished, this.waiting);
  final List<BoardAssignment> planned;
  final List<PlayEntry> running;
  final List<PlayEntry> finished;
  final List<PlayEntry> waiting;
}

class BoardSchedulingEngine {
  static const preferredPlayerRestBlocks = 2;

  const BoardSchedulingEngine();

  List<BoardAssignment> schedule({
    required List<PlayEntry> all,
    required List<PlayEntry> ready,
    List<PlayEntry> running = const [],
    List<PlayEntry> finished = const [],
    required int boardCount,
    Set<int> blockedBoards = const {},
    Map<String, List<int>> preferredBoardsByGroup = const {},
    String strategy = 'group',
    bool assignGroupsToBoards = false,
    Map<String, Set<int>> groupBoardAssignments = const {},
  }) {
    if (boardCount < 1) throw ArgumentError.value(boardCount, 'boardCount');
    if (List.generate(boardCount, (i) => i + 1).every(blockedBoards.contains)) {
      return [];
    }
    final normalizedStrategy = strategy.trim().toLowerCase();
    final pending = List<PlayEntry>.from(ready);
    final lastPlayed = <String, int>{};
    for (var i = 0; i < finished.length; i++) {
      if (!finished[i].match.hasResult) continue;
      for (final player in finished[i].players) {
        lastPlayed[player] = i - finished.length;
      }
    }

    final planned = <BoardAssignment>[];
    final entryOrder = {
      for (var index = 0; index < all.length; index++) all[index]: index,
    };
    final playedCounts = <String, int>{};
    final activeStage =
        ready.firstOrNull?.stageIndex ?? running.firstOrNull?.stageIndex;
    for (final entry in [...finished, ...running]) {
      if (activeStage != null && entry.stageIndex != activeStage) continue;
      if (!entry.match.hasResult && !running.contains(entry)) continue;
      for (final player in entry.players) {
        playedCounts[player] = (playedCounts[player] ?? 0) + 1;
      }
    }
    final groupBoards = <String, Set<int>>{
      for (final entry in preferredBoardsByGroup.entries)
        entry.key: entry.value.toSet(),
    };
    final useGroupAssignments =
        assignGroupsToBoards &&
        normalizedStrategy == 'group' &&
        ready.isNotEmpty &&
        ready.every((entry) => entry.groupKey != null);
    if (useGroupAssignments) {
      final groupKeys = all
          .where((entry) => entry.stageIndex == ready.first.stageIndex)
          .map((entry) => entry.groupKey)
          .whereType<String>()
          .toSet()
          .toList();
      final defaults = GroupBoardAssignment.defaults(
        groupNames: groupKeys,
        boardCount: boardCount,
      );
      for (final groupKey in groupKeys) {
        final assigned = groupBoardAssignments[groupKey];
        final preferred = groupBoards[groupKey];
        groupBoards[groupKey] =
            (assigned?.isNotEmpty == true
                    ? assigned!
                    : preferred?.isNotEmpty == true
                    ? preferred!
                    : defaults[groupKey] ?? const <int>{})
                .where(
                  (board) =>
                      board >= 1 &&
                      board <= boardCount &&
                      !blockedBoards.contains(board),
                )
                .toSet();
      }
    }
    var block = 0;
    while (pending.isNotEmpty) {
      final busy = block == 0
          ? <String>{for (final e in running) ...e.players}
          : <String>{};
      final boards = [
        for (var b = 1; b <= boardCount; b++)
          if (!blockedBoards.contains(b) &&
              (block != 0 || !running.any((e) => e.match.boardNumber == b)))
            b,
      ];

      final remainingCount = <String, int>{};
      for (final e in pending) {
        for (final p in e.players) {
          remainingCount[p] = (remainingCount[p] ?? 0) + 1;
        }
      }

      int rest(PlayEntry e) => e.players
          .map((p) => lastPlayed[p] ?? -100000)
          .reduce((a, b) => a > b ? a : b);
      int minimumRestGap(PlayEntry e) => e.players
          .map(
            (p) => lastPlayed[p] == null
                ? preferredPlayerRestBlocks
                : block - lastPlayed[p]!,
          )
          .reduce((a, b) => a < b ? a : b);
      int maxRemaining(PlayEntry e) => e.players
          .map((p) => remainingCount[p] ?? 0)
          .fold<int>(0, (a, b) => a > b ? a : b);

      int lowestPlayedAfter(PlayEntry entry) => entry.players
          .map((player) => (playedCounts[player] ?? 0) + 1)
          .reduce((a, b) => a < b ? a : b);
      int highestPlayedAfter(PlayEntry entry) => entry.players
          .map((player) => (playedCounts[player] ?? 0) + 1)
          .reduce((a, b) => a > b ? a : b);

      final available =
          pending.where((e) => !e.players.any(busy.contains)).toList()..sort((
            a,
            b,
          ) {
            if (normalizedStrategy == 'group') {
              final groupCompare = (a.groupKey ?? '').compareTo(
                b.groupKey ?? '',
              );
              if (groupCompare != 0) return groupCompare;
            }

            final lowest = lowestPlayedAfter(a).compareTo(lowestPlayedAfter(b));
            if (lowest != 0) return lowest;
            final highest = highestPlayedAfter(
              a,
            ).compareTo(highestPlayedAfter(b));
            if (highest != 0) return highest;

            final preferredGap = minimumRestGap(b).compareTo(minimumRestGap(a));
            if ((minimumRestGap(a) < preferredPlayerRestBlocks) !=
                (minimumRestGap(b) < preferredPlayerRestBlocks)) {
              return preferredGap;
            }

            final r = rest(a).compareTo(rest(b));
            if (r != 0) return r;
            final rem = maxRemaining(b).compareTo(maxRemaining(a));
            return rem != 0 ? rem : entryOrder[a]!.compareTo(entryOrder[b]!);
          });
      var selectedEntries = <PlayEntry>[];
      var bestPreferenceScore = -1;
      for (final first in available.take(64)) {
        final batch = <PlayEntry>[];
        final used = <String>{...busy};
        for (final entry in [first, ...available.where((e) => e != first)]) {
          if (batch.length >= boards.length) break;
          if (entry.players.any(used.contains)) continue;
          batch.add(entry);
          used.addAll(entry.players);
        }

        var preferenceScore = 0;
        final unassigned = List<PlayEntry>.from(batch);
        for (final board in boards) {
          final preferredIndex = unassigned.indexWhere(
            (entry) => groupBoards[entry.groupKey]?.contains(board) == true,
          );
          if (preferredIndex >= 0) preferenceScore++;
          if (unassigned.isNotEmpty) {
            unassigned.removeAt(preferredIndex < 0 ? 0 : preferredIndex);
          }
        }
        if (batch.length > selectedEntries.length ||
            (batch.length == selectedEntries.length &&
                preferenceScore > bestPreferenceScore)) {
          selectedEntries = batch;
          bestPreferenceScore = preferenceScore;
        }
        if (selectedEntries.length == boards.length &&
            (groupBoards.isEmpty || preferenceScore == boards.length)) {
          break;
        }
      }

      final selected = <({PlayEntry entry, int board})>[];
      final remaining = List<PlayEntry>.from(selectedEntries);
      final selectedBoards = <int>{};
      for (final board in boards) {
        final preferredIndex = remaining.indexWhere(
          (entry) => groupBoards[entry.groupKey]?.contains(board) == true,
        );
        if (preferredIndex < 0) continue;
        selected.add((entry: remaining.removeAt(preferredIndex), board: board));
        selectedBoards.add(board);
      }
      final reservedBoards = {
        for (final entry in available) ...?groupBoards[entry.groupKey],
      };
      for (final board in boards) {
        if (remaining.isEmpty) break;
        if (selectedBoards.contains(board) ||
            (useGroupAssignments && reservedBoards.contains(board))) {
          continue;
        }
        selected.add((entry: remaining.removeAt(0), board: board));
        selectedBoards.add(board);
      }

      if (selected.isEmpty) {
        if (block == 0) {
          if (useGroupAssignments &&
              groupBoards.values.every((boards) => boards.isEmpty)) {
            break;
          }
          block++;
          continue;
        }
        if (useGroupAssignments) break;
        if (block > 0) {
          throw StateError(
            'Unable to assign a ready match to an available board.',
          );
        }
        break;
      }

      for (final assignment in selected) {
        final entry = assignment.entry;
        planned.add(BoardAssignment(entry, block, assignment.board));
        pending.remove(entry);
        for (final player in entry.players) {
          lastPlayed[player] = block;
          playedCounts[player] = (playedCounts[player] ?? 0) + 1;
        }
      }

      if (block == 0) {
        for (final entry in running) {
          for (final player in entry.players) {
            lastPlayed[player] = 0;
          }
        }
      }
      block++;
    }
    return planned;
  }
}
