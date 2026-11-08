import '../../tournaments/domain/tournament_models.dart';

class AchievementMatchResolver {
  const AchievementMatchResolver();

  GroupMatch? resolve({
    required String playerProfileId,
    required DateTime? unlockedAt,
    required Iterable<GroupMatch> matches,
    required DateTime tournamentDate,
    DateTime? tournamentFinishedAt,
    GroupMatch? fallbackMatch,
  }) {
    final candidates =
        matches
            .where(
              (match) =>
                  match.countsForStatistics &&
                  _containsPlayer(match, playerProfileId),
            )
            .toList()
          ..sort(
            (left, right) => _matchDate(
              left,
              tournamentDate,
            ).compareTo(_matchDate(right, tournamentDate)),
          );
    if (candidates.isEmpty) return null;

    final unlockTime = unlockedAt;
    if (unlockTime == null) {
      if (fallbackMatch != null && candidates.contains(fallbackMatch)) {
        return fallbackMatch;
      }
      return candidates.last;
    }

    for (final match in candidates) {
      if (_matchDate(match, tournamentDate).isAtSameMomentAs(unlockTime)) {
        return match;
      }
    }
    for (final match in candidates) {
      if (_matchDate(match, tournamentDate).isAfter(unlockTime)) {
        return match;
      }
    }

    if (tournamentFinishedAt != null &&
        !unlockTime.isAfter(tournamentFinishedAt)) {
      for (final match in candidates.reversed) {
        if (!_matchDate(match, tournamentDate).isAfter(tournamentFinishedAt)) {
          return match;
        }
      }
    }
    return null;
  }

  bool _containsPlayer(GroupMatch match, String profileId) {
    final players = [
      if (match.homePlayer != null) match.homePlayer!,
      if (match.awayPlayer != null) match.awayPlayer!,
      ...match.players,
    ];
    return players.any(
      (player) => player.individuals.any(
        (individual) => individual.profileId == profileId,
      ),
    );
  }

  DateTime _matchDate(GroupMatch match, DateTime tournamentDate) =>
      match.finishedAt ?? match.startedAt ?? tournamentDate;
}
