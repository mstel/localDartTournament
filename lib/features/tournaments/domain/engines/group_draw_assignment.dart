import '../tournament_models.dart';

class GroupDrawAssignment {
  const GroupDrawAssignment._();

  static List<TournamentPlayer> orderPlayers({
    required List<TournamentPlayer> players,
    required List<int?> slotOrder,
    required int participantCount,
  }) {
    if (participantCount < 1 || slotOrder.length != participantCount) {
      return players;
    }

    final seen = <int>{};
    for (final seed in slotOrder) {
      if (seed == null || seed < 1 || seed > participantCount) {
        return players;
      }
      if (!seen.add(seed)) return players;
    }

    return [
      for (final seed in slotOrder)
        if (seed case final int value when value <= players.length)
          players[value - 1],
    ];
  }

  static List<List<T>> partition<T>(List<T> players, List<int> groupSizes) {
    var playerIndex = 0;
    return [
      for (final groupSize in groupSizes)
        () {
          final groupEnd = (playerIndex + groupSize).clamp(
            playerIndex,
            players.length,
          );
          final group = players.sublist(playerIndex, groupEnd);
          playerIndex = groupEnd;
          return group;
        }(),
    ];
  }
}
