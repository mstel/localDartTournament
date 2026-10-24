class RandomDrawAssignment {
  const RandomDrawAssignment._();

  static List<List<String?>> groupSlots({
    required List<String> drawnPlayers,
    required int groupCount,
    required int totalPlayerCount,
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
    final groupSizes = List<int>.generate(
      groupCount,
      (index) =>
          totalPlayerCount ~/ groupCount +
          (index < totalPlayerCount % groupCount ? 1 : 0),
    );
    final groups = [
      for (final size in groupSizes) List<String?>.filled(size, null),
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

  static String formatText({
    required List<String> groupNames,
    required List<List<String>> groups,
  }) {
    if (groupNames.length != groups.length || groups.isEmpty) {
      throw ArgumentError('Each group must have exactly one name.');
    }
    return [
      for (var index = 0; index < groups.length; index++)
        '${groupNames[index]}: ${groups[index].join(', ')}',
    ].join('\n');
  }
}
