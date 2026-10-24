import '../tournament_models.dart';

class GroupDrawAssignment {
  const GroupDrawAssignment._();

  static List<List<T>> partitionDraw<T>({
    required List<T> items,
    required List<int?> slotOrder,
    required List<int> groupSizes,
  }) {
    final participantCount = groupSizes.fold<int>(0, (sum, size) => sum + size);
    if (slotOrder.isNotEmpty &&
        !_isValidSlotOrder(
          slotOrder,
          participantCount: participantCount,
          itemCount: items.length,
        )) {
      throw FormatException(
        'Die gespeicherte Gruppenauslosung passt nicht zu den '
        'Gruppengrößen ($participantCount Plätze).',
      );
    }
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

  static bool _isValidSlotOrder(
    List<int?> slotOrder, {
    required int participantCount,
    required int itemCount,
  }) {
    if (participantCount < 1 ||
        slotOrder.length != participantCount ||
        itemCount < participantCount) {
      return false;
    }

    final seen = <int>{};
    for (final seed in slotOrder) {
      if (seed == null ||
          seed < 1 ||
          seed > participantCount ||
          !seen.add(seed)) {
        return false;
      }
    }
    return true;
  }

  static List<List<T?>> previewPartitionDraw<T>({
    required List<T> items,
    required List<int> drawnSeeds,
    required List<int> groupSizes,
  }) {
    final groups = [for (final size in groupSizes) List<T?>.filled(size, null)];
    final participantCount = groupSizes.fold<int>(0, (sum, size) => sum + size);
    if (drawnSeeds.length > participantCount) return groups;

    final seen = <int>{};
    for (var drawIndex = 0; drawIndex < drawnSeeds.length; drawIndex++) {
      final seed = drawnSeeds[drawIndex];
      if (seed < 1 || seed > items.length || !seen.add(seed)) return groups;

      var slotIndex = drawIndex;
      for (final group in groups) {
        if (slotIndex < group.length) {
          group[slotIndex] = items[seed - 1];
          break;
        }
        slotIndex -= group.length;
      }
    }

    return groups;
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
