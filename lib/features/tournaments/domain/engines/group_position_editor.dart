import '../tournament_models.dart';

/// Swaps occupied slots without changing group sizes or the match structure.
class GroupPositionEditor {
  static Set<GroupMatch> _matches(GroupTournamentRunStage stage) => {
    for (final group in stage.groups) ...[
      ...group.matches,
      ...group.knockoutRounds.expand((round) => round),
      ...group.placementMatches,
    ],
  };

  static bool canEdit(GroupTournamentRunStage stage) =>
      _matches(stage).every((match) => !match.hasResult);

  static bool swap(
    GroupTournamentRunStage stage,
    TournamentPlayer first,
    TournamentPlayer second,
  ) {
    if (!canEdit(stage) || first == second) return false;
    final players = stage.groups.expand((group) => group.players).toList();
    if (players.where((p) => p == first).length != 1 ||
        players.where((p) => p == second).length != 1) {
      return false;
    }
    TournamentPlayer? replace(TournamentPlayer? player) => player == first
        ? second
        : player == second
        ? first
        : player;
    for (final group in stage.groups) {
      for (var i = 0; i < group.players.length; i++) {
        group.players[i] = replace(group.players[i])!;
      }
    }
    // A mini-KO match may be referenced by both matches and knockoutRounds.
    // Process each object once, including already propagated byes.
    for (final match in _matches(stage)) {
      match.homePlayer = replace(match.homePlayer);
      match.awayPlayer = replace(match.awayPlayer);
      match.boardNumber = null;
      match.startedAt = null;
      match.finishedAt = null;
      match.startedPlayers = null;
      match.isAnnulled = false;
      match.homeLegs = null;
      match.awayLegs = null;
      match.homeSets = null;
      match.awaySets = null;
    }
    return true;
  }
}
