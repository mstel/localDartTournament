import '../tournament_models.dart';

/// Reassigns players to existing group slots without changing group sizes.
class GroupPositionEditor {
  static Set<GroupMatch> _matches(GroupTournamentRunStage stage) => {
    for (final group in stage.groups) ...[
      ...group.matches,
      ...group.knockoutRounds.expand((round) => round),
      ...group.placementMatches,
    ],
  };

  static bool canEdit(GroupTournamentRunStage stage) => _matches(stage).every(
    (match) =>
        !match.hasResult &&
        !(match.startedAt != null &&
            match.finishedAt == null &&
            match.boardNumber != null &&
            match.startedPlayers != null &&
            !match.isAnnulled),
  );

  static bool swap(
    GroupTournamentRunStage stage,
    TournamentPlayer first,
    TournamentPlayer second,
  ) {
    if (!canEdit(stage) || first == second) return false;
    final assignments = [
      for (final group in stage.groups) [...group.players],
    ];
    final players = stage.groups.expand((group) => group.players).toList();
    final firstIndex = players.indexOf(first);
    final secondIndex = players.indexOf(second);
    if (firstIndex < 0 || secondIndex < 0) return false;
    players[firstIndex] = second;
    players[secondIndex] = first;
    var offset = 0;
    for (var groupIndex = 0; groupIndex < assignments.length; groupIndex++) {
      for (
        var playerIndex = 0;
        playerIndex < assignments[groupIndex].length;
        playerIndex++
      ) {
        assignments[groupIndex][playerIndex] = players[offset++];
      }
    }
    return reassign(stage, assignments);
  }

  static bool reassign(
    GroupTournamentRunStage stage,
    List<List<TournamentPlayer>> assignments,
  ) {
    if (!canEdit(stage) || assignments.length != stage.groups.length) {
      return false;
    }
    final currentPlayers = stage.groups
        .expand((group) => group.players)
        .toList();
    final assignedPlayers = assignments.expand((group) => group).toList();
    if (assignedPlayers.length != currentPlayers.length ||
        assignedPlayers.toSet().length != currentPlayers.length ||
        currentPlayers.any((player) => !assignedPlayers.contains(player))) {
      return false;
    }
    for (var index = 0; index < stage.groups.length; index++) {
      if (assignments[index].length != stage.groups[index].players.length) {
        return false;
      }
    }

    final replacements = <TournamentPlayer, TournamentPlayer>{
      for (var index = 0; index < currentPlayers.length; index++)
        currentPlayers[index]: assignedPlayers[index],
    };
    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final group = stage.groups[groupIndex];
      for (
        var playerIndex = 0;
        playerIndex < group.players.length;
        playerIndex++
      ) {
        group.players[playerIndex] = assignments[groupIndex][playerIndex];
      }
    }
    for (final match in _matches(stage)) {
      match.homePlayer = replacements[match.homePlayer] ?? match.homePlayer;
      match.awayPlayer = replacements[match.awayPlayer] ?? match.awayPlayer;
      match
        ..boardNumber = null
        ..startedAt = null
        ..finishedAt = null
        ..startedPlayers = null
        ..isAnnulled = false
        ..homeLegs = null
        ..awayLegs = null
        ..homeSets = null
        ..awaySets = null
        ..withdrawalSignature = null
        ..withdrawalIgnored = false
        ..withdrawalHadResult = false
        ..bestPerformances = [];
    }
    return true;
  }
}
