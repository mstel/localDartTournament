import '../tournament_models.dart';

class PlayEntry {
  const PlayEntry(this.match, this.stageIndex, this.origin, [this.groupKey]);
  final GroupMatch match;
  final int stageIndex;
  final String origin;
  final String? groupKey;
  Set<String> get players => {
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
    String strategy = 'group',
  }) {
    if (boardCount < 1) throw ArgumentError.value(boardCount, 'boardCount');
    if (List.generate(boardCount, (i) => i + 1).every(blockedBoards.contains)) return [];

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

      final playedCounts = <String, int>{};
      for (final finishedEntry in finished) {
        if (!finishedEntry.match.hasResult) continue;
        for (final player in finishedEntry.players) {
          playedCounts[player] = (playedCounts[player] ?? 0) + 1;
        }
      }
      for (final runningEntry in running) {
        for (final player in runningEntry.players) {
          playedCounts[player] = (playedCounts[player] ?? 0) + 1;
        }
      }

      int fairnessSpread(PlayEntry e) {
        final counts = Map<String, int>.from(playedCounts);
        for (final player in e.players) {
          counts[player] = (counts[player] ?? 0) + 1;
        }
        final values = e.players.map((player) => counts[player] ?? 0).toList();
        if (values.length < 2) return 0;
        final min = values.reduce((a, b) => a < b ? a : b);
        final max = values.reduce((a, b) => a > b ? a : b);
        return max - min;
      }

      var selected = <PlayEntry>[];
      final available =
          pending.where((e) => !e.players.any(busy.contains)).toList()
            ..sort((a, b) {
              if (normalizedStrategy == 'group') {
                final groupCompare = (a.groupKey ?? '').compareTo(
                  b.groupKey ?? '',
                );
                if (groupCompare != 0) return groupCompare;
              }

              final fairness = fairnessSpread(a).compareTo(fairnessSpread(b));
              if (fairness != 0) return fairness;

              final preferredGap = minimumRestGap(b).compareTo(
                minimumRestGap(a),
              );
              if ((minimumRestGap(a) < preferredPlayerRestBlocks) !=
                  (minimumRestGap(b) < preferredPlayerRestBlocks)) {
                return preferredGap;
              }

              final r = rest(a).compareTo(rest(b));
              if (r != 0) return r;
              final rem = maxRemaining(b).compareTo(maxRemaining(a));
              return rem != 0 ? rem : all.indexOf(a).compareTo(all.indexOf(b));
            });
      for (final first in available.take(64)) {
        final batch = <PlayEntry>[];
        final used = <String>{...busy};
        for (final entry in [first, ...available.where((e) => e != first)]) {
          if (batch.length >= boards.length) break;
          if (entry.players.any(used.contains)) continue;
          batch.add(entry);
          used.addAll(entry.players);
        }
        if (batch.length > selected.length) selected = batch;
        if (selected.length == boards.length) break;
      }

      for (var i = 0; i < selected.length; i++) {
        final entry = selected[i];
        planned.add(BoardAssignment(entry, block, boards[i]));
        pending.remove(entry);
        for (final player in entry.players) {
          lastPlayed[player] = block;
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
