class GroupBoardAssignment {
  const GroupBoardAssignment();

  static String keyFor(int stageIndex, String groupName) =>
      '$stageIndex:$groupName';

  static Map<String, Set<int>> defaults({
    required List<String> groupNames,
    required int boardCount,
    String Function(String groupName)? keyBuilder,
  }) {
    final assignments = <String, Set<int>>{};
    if (groupNames.isEmpty || boardCount < 1) return assignments;
    final keyOf = keyBuilder ?? (groupName) => groupName;

    if (boardCount < groupNames.length) {
      for (var index = 0; index < groupNames.length; index++) {
        assignments[keyOf(groupNames[index])] = {index % boardCount + 1};
      }
      return assignments;
    }

    final boardsPerGroup = boardCount ~/ groupNames.length;
    final extraBoards = boardCount % groupNames.length;
    var nextBoard = 1;
    for (var index = 0; index < groupNames.length; index++) {
      final count = boardsPerGroup + (index < extraBoards ? 1 : 0);
      assignments[keyOf(groupNames[index])] = {
        for (var board = nextBoard; board < nextBoard + count; board++) board,
      };
      nextBoard += count;
    }
    return assignments;
  }

  /// Default board distribution keyed exactly like persisted assignments.
  /// Legacy group names stay available as aliases for older callers and tests.
  static Map<String, Set<int>> defaultsForStage({
    required int stageIndex,
    required List<String> groupNames,
    required int boardCount,
  }) => <String, Set<int>>{
    ...defaults(groupNames: groupNames, boardCount: boardCount),
    ...defaults(
      groupNames: groupNames,
      boardCount: boardCount,
      keyBuilder: (groupName) => keyFor(stageIndex, groupName),
    ),
  };

  /// Reads a board assignment regardless of whether the caller uses the
  /// stage-prefixed persisted key or a legacy bare group name.
  static Set<int> lookup(
    Map<String, Iterable<int>> assignments,
    int stageIndex,
    String groupKey,
  ) {
    final separator = groupKey.indexOf(':');
    final groupName = separator >= 0
        ? groupKey.substring(separator + 1)
        : groupKey;
    return assignments[keyFor(stageIndex, groupName)]?.toSet() ??
        assignments[groupKey]?.toSet() ??
        assignments[groupName]?.toSet() ??
        const <int>{};
  }
}
