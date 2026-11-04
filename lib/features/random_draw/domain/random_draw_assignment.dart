class RandomDrawAssignment {
  const RandomDrawAssignment._();

  static List<List<String?>> groupSlots({
    required List<String> drawnPlayers,
    required int groupCount,
    required int totalPlayerCount,
    List<int>? groupSizes,
  }) {
    if (groupCount < 1) {
      throw ArgumentError.value(groupCount, 'groupCount', 'Must be positive.');
    }
    if (totalPlayerCount < 0) {
      throw ArgumentError.value(
        totalPlayerCount,
        'totalPlayerCount',
        'Cannot be negative.',
      );
    }
    if (drawnPlayers.length > totalPlayerCount) {
      throw ArgumentError(
        'Drawn players cannot exceed the total player count.',
      );
    }
    final resolvedGroupSizes =
        groupSizes ??
        List<int>.generate(
          groupCount,
          (index) =>
              totalPlayerCount ~/ groupCount +
              (index < totalPlayerCount % groupCount ? 1 : 0),
        );
    if (resolvedGroupSizes.length != groupCount ||
        resolvedGroupSizes.any((size) => size < 0) ||
        resolvedGroupSizes.fold<int>(0, (sum, size) => sum + size) !=
            totalPlayerCount) {
      throw ArgumentError.value(groupSizes, 'groupSizes');
    }
    final groups = [
      for (final size in resolvedGroupSizes) List<String?>.filled(size, null),
    ];
    var drawnIndex = 0;
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      for (
        var slotIndex = 0;
        slotIndex < groups[groupIndex].length &&
            drawnIndex < drawnPlayers.length;
        slotIndex++
      ) {
        groups[groupIndex][slotIndex] = drawnPlayers[drawnIndex++];
      }
    }
    return groups;
  }
}
