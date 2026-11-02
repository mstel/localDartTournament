import '../../domain/tournament_models.dart';

class KratzerRoundAssignment {
  const KratzerRoundAssignment({
    required this.players,
    required this.scratchEligiblePlayers,
    required this.boardNumber,
  });

  final List<TournamentPlayer> players;
  final List<TournamentPlayer> scratchEligiblePlayers;
  final int boardNumber;
}

class KratzerDurationEstimate {
  const KratzerDurationEstimate({
    required this.games,
    required this.rounds,
    required this.minutes,
  });

  final int games;
  final int rounds;
  final int minutes;
}

class KratzerEngine {
  const KratzerEngine();

  List<KratzerRoundAssignment> assignRound({
    required List<TournamentPlayer> players,
    List<TournamentPlayer> eliminatedFillers = const [],
    required List<int> availableBoards,
    required int round,
  }) {
    if (players.length < 2 || availableBoards.isEmpty) return const [];

    final boardCount = availableBoards.length;
    final groupCount = players.length < 3
        ? 1
        : (players.length ~/ 3).clamp(0, boardCount);
    if (groupCount == 0) return const [];

    final orderedPlayers = _rotate(players, round % players.length);
    final playingPlayerCount = orderedPlayers.length.clamp(0, groupCount * 6);
    final eligibleCount = playingPlayerCount;
    final matchPlayers = orderedPlayers.take(playingPlayerCount).toList();
    if (matchPlayers.length < 3) {
      matchPlayers.addAll(eliminatedFillers.take(3 - matchPlayers.length));
    }
    if (matchPlayers.length < 3) return const [];
    final groups = <KratzerRoundAssignment>[];
    var playerIndex = 0;
    final baseSize = matchPlayers.length ~/ groupCount;
    final largerGroupCount = matchPlayers.length % groupCount;
    for (var index = 0; index < groupCount; index++) {
      final size = baseSize + (index < largerGroupCount ? 1 : 0);
      final groupPlayers = matchPlayers.skip(playerIndex).take(size).toList();
      groups.add(
        KratzerRoundAssignment(
          players: List.unmodifiable(groupPlayers),
          scratchEligiblePlayers: List.unmodifiable(
            groupPlayers.where((player) => players.contains(player)),
          ),
          boardNumber: availableBoards[index],
        ),
      );
      playerIndex += size;
    }
    if (eligibleCount == 0) return const [];
    return List.unmodifiable(groups);
  }

  List<TournamentPlayer> activePlayers({
    required List<TournamentPlayer> players,
    required Iterable<GroupMatch> completedMatches,
    required int lives,
  }) {
    final scratches = <TournamentPlayer, int>{};
    for (final match in completedMatches) {
      final scratched = match.scratchedPlayer;
      if (scratched != null) {
        scratches.update(scratched, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return [
      for (final player in players)
        if ((scratches[player] ?? 0) < lives) player,
    ];
  }

  int requiredScratches(int playerCount, int lives) {
    if (playerCount < 1 || lives < 1) return 0;
    return (playerCount - 1) * lives;
  }

  int estimatedGameCount({
    required int playerCount,
    required int lives,
    required int boards,
  }) {
    if (playerCount <= 1 || lives < 1 || boards < 1) return 0;
    return estimateDuration(
      playerCount: playerCount,
      lives: lives,
      boards: boards,
      baseMatchMinutes: 0,
      boardIdleMinutes: 0,
    ).games;
  }

  KratzerDurationEstimate estimateDuration({
    required int playerCount,
    required int lives,
    required int boards,
    required double baseMatchMinutes,
    required double boardIdleMinutes,
  }) {
    if (playerCount <= 1 || lives < 1 || boards < 1) {
      return const KratzerDurationEstimate(games: 0, rounds: 0, minutes: 0);
    }
    final players = [
      for (var index = 1; index <= playerCount; index++)
        TournamentPlayer.generated(index),
    ];
    final scratches = <TournamentPlayer, int>{};
    var active = List<TournamentPlayer>.from(players);
    var round = 0;
    var games = 0;
    var minutes = 0.0;
    final availableBoards = List.generate(boards, (index) => index + 1);
    while (active.length > 1 && round < playerCount * lives * 2) {
      final assignments = assignRound(
        players: active,
        eliminatedFillers: players.where((p) => !active.contains(p)).toList(),
        availableBoards: availableBoards,
        round: round + 1,
      );
      if (assignments.isEmpty) break;
      round++;
      var longestMatchMinutes = 0.0;
      for (final assignment in assignments) {
        games++;
        final playerMultiplier = 1 + (assignment.players.length - 2) * 0.5;
        longestMatchMinutes =
            longestMatchMinutes > baseMatchMinutes * playerMultiplier
            ? longestMatchMinutes
            : baseMatchMinutes * playerMultiplier;
        final eligible = assignment.scratchEligiblePlayers;
        if (eligible.isNotEmpty) {
          final scratched = eligible.reduce(
            (current, candidate) =>
                (scratches[candidate] ?? 0) > (scratches[current] ?? 0)
                ? candidate
                : current,
          );
          scratches.update(scratched, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      minutes += longestMatchMinutes;
      minutes +=
          (boards - assignments.length).clamp(0, boards) * boardIdleMinutes;
      active = [
        for (final player in players)
          if ((scratches[player] ?? 0) < lives) player,
      ];
    }
    return KratzerDurationEstimate(
      games: games,
      rounds: round,
      minutes: minutes.ceil(),
    );
  }

  List<TournamentPlayer> _rotate(List<TournamentPlayer> players, int offset) {
    return [...players.skip(offset), ...players.take(offset)];
  }
}
