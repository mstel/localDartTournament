class GroupBoardAssignment {
  const GroupBoardAssignment();

  static String keyFor(int stageIndex, String groupName) =>
      '$stageIndex:$groupName';

  static Map<String, Set<int>> defaults({
    required List<String> groupNames,
    required int boardCount,
  }) {
    final assignments = <String, Set<int>>{};
    if (groupNames.isEmpty || boardCount < 1) return assignments;

    if (boardCount < groupNames.length) {
      for (var index = 0; index < groupNames.length; index++) {
        assignments[groupNames[index]] = {index % boardCount + 1};
      }
      return assignments;
    }

    final boardsPerGroup = boardCount ~/ groupNames.length;
    final extraBoards = boardCount % groupNames.length;
    var nextBoard = 1;
    for (var index = 0; index < groupNames.length; index++) {
      final count = boardsPerGroup + (index < extraBoards ? 1 : 0);
      assignments[groupNames[index]] = {
        for (var board = nextBoard; board < nextBoard + count; board++) board,
      };
      nextBoard += count;
    }
    return assignments;
  }
}
