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
    int? playersPerBoard,
    bool preferSameScratchCount = false,
    Iterable<GroupMatch> completedMatches = const [],
  }) {
    if (playersPerBoard != null &&
        (playersPerBoard < 3 || playersPerBoard > 6)) {
      throw ArgumentError.value(playersPerBoard, 'playersPerBoard');
    }
    if (players.length < 2 || availableBoards.isEmpty) return const [];
    final boardCount = availableBoards.length;
    final groupCount = playersPerBoard == null
        ? players.length < 3
              ? 1
              : (players.length ~/ 3).clamp(0, boardCount)
        : (players.length ~/ playersPerBoard).clamp(1, boardCount);
    if (groupCount == 0) return const [];

    final orderedPlayers = _rotate(players, round % players.length);
    if (preferSameScratchCount) {
      final scratches = scratchCounts(completedMatches);
      for (final player in orderedPlayers) {
        scratches.putIfAbsent(player, () => player.kratzerStartingScratches);
      }
      final rotationOrder = {
        for (var index = 0; index < orderedPlayers.length; index++)
          orderedPlayers[index]: index,
      };
      orderedPlayers.sort((a, b) {
        final scratchCompare = (scratches[a] ?? 0).compareTo(scratches[b] ?? 0);
        return scratchCompare != 0
            ? scratchCompare
            : rotationOrder[a]!.compareTo(rotationOrder[b]!);
      });
    }
    final maxPlayersPerBoard = playersPerBoard ?? 6;
    final playingPlayerCount = orderedPlayers.length.clamp(
      0,
      groupCount * maxPlayersPerBoard,
    );
    final eligibleCount = playingPlayerCount;
    final matchPlayers = orderedPlayers.take(playingPlayerCount).toList();
    if (matchPlayers.length < 3) {
      matchPlayers.addAll(eliminatedFillers.take(3 - matchPlayers.length));
    }
    if (matchPlayers.length < 3) return const [];
    final groups = <KratzerRoundAssignment>[];
    var playerIndex = 0;
    final baseSize = playersPerBoard ?? matchPlayers.length ~/ groupCount;
    final largerGroupCount = playersPerBoard == null
        ? matchPlayers.length % groupCount
        : 0;
    for (var index = 0; index < groupCount; index++) {
      final size = playersPerBoard == null
          ? baseSize + (index < largerGroupCount ? 1 : 0)
          : (matchPlayers.length - playerIndex).clamp(0, playersPerBoard);
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
    final scratches = scratchCounts(completedMatches);
    return [
      for (final player in players)
        if ((scratches[player] ?? player.kratzerStartingScratches) < lives)
          player,
    ];
  }

  Map<TournamentPlayer, int> scratchCounts(
    Iterable<GroupMatch> completedMatches,
  ) {
    final scratches = <TournamentPlayer, int>{};
    for (final match in completedMatches) {
      for (final player in match.players) {
        scratches.putIfAbsent(player, () => player.kratzerStartingScratches);
      }
      final scratched = match.scratchedPlayer;
      if (scratched != null) {
        scratches.update(
          scratched,
          (count) => count + 1,
          ifAbsent: () => scratched.kratzerStartingScratches + 1,
        );
      }
      for (final bonus in match.kratzerBonusLives) {
        scratches.update(
          bonus.player,
          (count) => count - 1,
          ifAbsent: () => bonus.player.kratzerStartingScratches - 1,
        );
      }
    }
    return scratches;
  }

  bool wasEliminatedInRound({
    required Iterable<GroupMatch> round,
    required List<TournamentPlayer> activePlayers,
  }) {
    final active = activePlayers.toSet();
    return round
        .expand((match) => match.scratchEligiblePlayers)
        .any((player) => !active.contains(player));
  }

  List<KratzerRoundAssignment> assignNextRound({
    required List<TournamentPlayer> activePlayers,
    required List<TournamentPlayer> eliminatedPlayers,
    required List<int> availableBoards,
    required int round,
    required List<GroupMatch> previousRound,
    required Iterable<GroupMatch> completedMatches,
    int? playersPerBoard,
    bool preferSameScratchCount = false,
    bool playUntilElimination = false,
  }) {
    if (playUntilElimination &&
        previousRound.isNotEmpty &&
        !wasEliminatedInRound(
          round: previousRound,
          activePlayers: activePlayers,
        )) {
      return [
        for (final match in previousRound)
          KratzerRoundAssignment(
            players: List.unmodifiable(match.players),
            scratchEligiblePlayers: List.unmodifiable(
              match.scratchEligiblePlayers,
            ),
            boardNumber: match.boardNumber ?? 1,
          ),
      ];
    }

    return assignRound(
      players: activePlayers,
      eliminatedFillers: eliminatedPlayers,
      availableBoards: availableBoards,
      round: round,
      playersPerBoard: playersPerBoard,
      preferSameScratchCount: preferSameScratchCount,
      completedMatches: completedMatches,
    );
  }

  int requiredScratches(int playerCount, int lives) {
    if (playerCount < 1 || lives < 1) return 0;
    return (playerCount - 1) * lives;
  }

  int estimatedGameCount({
    required int playerCount,
    required int lives,
    required int boards,
    int? playersPerBoard,
    bool preferSameScratchCount = false,
    bool playUntilElimination = false,
  }) {
    if (playerCount <= 1 || lives < 1 || boards < 1) return 0;
    return estimateDuration(
      playerCount: playerCount,
      lives: lives,
      boards: boards,
      playersPerBoard: playersPerBoard,
      preferSameScratchCount: preferSameScratchCount,
      playUntilElimination: playUntilElimination,
      baseMatchMinutes: 0,
      boardIdleMinutes: 0,
    ).games;
  }

  KratzerDurationEstimate estimateDuration({
    required int playerCount,
    required int lives,
    required int boards,
    int? playersPerBoard,
    bool preferSameScratchCount = false,
    bool playUntilElimination = false,
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
    var previousRoundAssignments = <KratzerRoundAssignment>[];
    final completedMatches = <GroupMatch>[];
    final availableBoards = List.generate(boards, (index) => index + 1);
    while (active.length > 1 && round < playerCount * lives * 2) {
      final previousRoundMatches = completedMatches
          .where((match) => match.round == round)
          .toList();
      final repeatGroups =
          playUntilElimination &&
          previousRoundAssignments.isNotEmpty &&
          !wasEliminatedInRound(
            round: previousRoundMatches,
            activePlayers: active,
          );
      final assignments = repeatGroups
          ? previousRoundAssignments
          : assignRound(
              players: active,
              eliminatedFillers: players
                  .where((p) => !active.contains(p))
                  .toList(),
              availableBoards: availableBoards,
              round: round + 1,
              playersPerBoard: playersPerBoard,
              preferSameScratchCount: preferSameScratchCount,
              completedMatches: completedMatches,
            );
      if (assignments.isEmpty) break;
      round++;
      var longestMatchMinutes = 0.0;
      final currentRound = <GroupMatch>[];
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
          currentRound.add(
            GroupMatch(
              players: assignment.players,
              scratchEligiblePlayers: assignment.scratchEligiblePlayers,
              isKratzer: true,
              scratchedPlayer: scratched,
              round: round,
              boardNumber: assignment.boardNumber,
            ),
          );
        }
      }
      completedMatches.addAll(currentRound);
      previousRoundAssignments = assignments;
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
