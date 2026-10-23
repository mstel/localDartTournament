class RandomDrawAssignment {
  const RandomDrawAssignment._();

  static List<List<String>> distributeRoundRobin({
    required List<String> drawnPlayers,
    required int groupCount,
  }) {
    if (groupCount < 1) {
      throw ArgumentError.value(groupCount, 'groupCount', 'Must be positive.');
    }
    final groups = List.generate(groupCount, (_) => <String>[]);
    for (var index = 0; index < drawnPlayers.length; index++) {
      groups[index % groupCount].add(drawnPlayers[index]);
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
