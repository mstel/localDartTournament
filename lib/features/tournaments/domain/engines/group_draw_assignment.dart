import '../tournament_models.dart';

class GroupDrawAssignment {
  const GroupDrawAssignment._();

  static List<List<T>> partitionDraw<T>({
    required List<T> items,
    required List<int?> slotOrder,
    required List<int> groupSizes,
  }) {
    final participantCount = groupSizes.fold<int>(0, (sum, size) => sum + size);
    return partition(
      slotOrder.isEmpty
          ? items
          : orderItems(
              items: items,
              slotOrder: slotOrder,
              participantCount: participantCount,
            ),
      groupSizes,
    );
  }

  static List<TournamentPlayer> orderPlayers({
    required List<TournamentPlayer> players,
    required List<int?> slotOrder,
    required int participantCount,
  }) => orderItems(
    items: players,
    slotOrder: slotOrder,
    participantCount: participantCount,
  );

  static List<T> orderItems<T>({
    required List<T> items,
    required List<int?> slotOrder,
    required int participantCount,
  }) {
    if (participantCount < 1 || slotOrder.length != participantCount) {
      return items;
    }

    final seen = <int>{};
    for (final seed in slotOrder) {
      if (seed == null || seed < 1 || seed > participantCount) {
        return items;
      }
      if (!seen.add(seed)) return items;
    }

    return [
      for (final seed in slotOrder)
        if (seed case final int value when value <= items.length)
          items[value - 1],
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
