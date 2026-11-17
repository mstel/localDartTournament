import '../tournament_models.dart';
import 'limited_round_robin_engine.dart';

class TournamentEngine {
  const TournamentEngine();

  int knockoutPlayableMatchCount(int participantCount) {
    return participantCount < 2 ? 0 : participantCount - 1;
  }

  int eliminationMatchEstimate(int participantCount, int lossLimit) {
    if (participantCount < 2) {
      return 0;
    }

    final safeLossLimit = lossLimit < 1 ? 1 : lossLimit;
    return safeLossLimit == 1
        ? knockoutPlayableMatchCount(participantCount)
        : participantCount * safeLossLimit - safeLossLimit;
  }

  int nextPowerOfTwo(int value) {
    var size = 2;
    while (size < value) {
      size *= 2;
    }
    return size;
  }

  List<int> seedOrderForSize(int bracketSize) {
    var order = <int>[1, 2];
    var size = 2;
    while (size < bracketSize) {
      final nextSize = size * 2;
      order = [
        for (final seed in order) ...[seed, nextSize + 1 - seed],
      ];
      size = nextSize;
    }

    return order;
  }

  List<GroupMatch> buildRoundRobinMatches(
    List<TournamentPlayer> players, {
    int repeatCount = 1,
    int? maxGamesPerPlayer,
    String matchmakingStrategy = 'elo',
    Map<String, int> ratings = const {},
    int? seed,
  }) {
    if (maxGamesPerPlayer != null) {
      return LimitedRoundRobinEngine.build(
        players,
        maxGamesPerPlayer: maxGamesPerPlayer,
        repeatCount: repeatCount,
        matchmakingStrategy: matchmakingStrategy,
        ratings: ratings,
        seed: seed,
      );
    }
    final matches = <GroupMatch>[];
    if (players.length < 2) {
      return matches;
    }

    final playerCount = players.length.isOdd
        ? players.length + 1
        : players.length;
    final rounds = playerCount - 1;
    final matchesPerRound = playerCount ~/ 2;
    final safeRepeatCount = repeatCount < 1 ? 1 : repeatCount;

    for (var repeat = 0; repeat < safeRepeatCount; repeat++) {
      final rotation = List<TournamentPlayer?>.from(players);
      if (rotation.length.isOdd) {
        rotation.add(null);
      }

      for (var round = 0; round < rounds; round++) {
        for (var pairIndex = 0; pairIndex < matchesPerRound; pairIndex++) {
          final firstPlayer = rotation[pairIndex];
          final secondPlayer = rotation[playerCount - 1 - pairIndex];
          if (firstPlayer == null || secondPlayer == null) {
            continue;
          }

          final swapHome = repeat.isOdd;
          final homePlayer = swapHome ? secondPlayer : firstPlayer;
          final awayPlayer = swapHome ? firstPlayer : secondPlayer;

          matches.add(
            GroupMatch(
              homePlayer: homePlayer,
              awayPlayer: awayPlayer,
              round: repeat * rounds + round + 1,
            ),
          );
        }

        final fixedPlayer = rotation.first;
        final rotatingPlayers = rotation.sublist(1);
        rotatingPlayers.insert(0, rotatingPlayers.removeLast());
        rotation
          ..clear()
          ..add(fixedPlayer)
          ..addAll(rotatingPlayers);
      }
    }

    return matches;
  }

  int roundRobinMatchCount(
    int groupSize,
    int repeatCount, {
    int? maxGamesPerPlayer,
  }) {
    if (groupSize < 2) {
      return 0;
    }

    final safeRepeatCount = repeatCount < 1 ? 1 : repeatCount;
    if (maxGamesPerPlayer != null) {
      if (maxGamesPerPlayer < 1) {
        throw ArgumentError.value(maxGamesPerPlayer, 'maxGamesPerPlayer');
      }
      final maximum = (groupSize - 1) * safeRepeatCount;
      final games = maxGamesPerPlayer < maximum ? maxGamesPerPlayer : maximum;
      return groupSize * games ~/ 2;
    }
    return (groupSize * (groupSize - 1) ~/ 2) * safeRepeatCount;
  }
}

const tournamentEngine = TournamentEngine();
