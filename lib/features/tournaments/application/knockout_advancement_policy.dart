import '../domain/tournament_models.dart';

class KnockoutAdvancementPolicy {
  const KnockoutAdvancementPolicy();

  bool hasReachedAdvancingCount({
    required List<List<GroupMatch>> rounds,
    required int lossLimit,
    required int advancingCount,
  }) {
    if (rounds.isEmpty || advancingCount < 1) return false;
    final players = <String, TournamentPlayer>{};
    final losses = <String, int>{};
    for (final round in rounds) {
      for (final match in round) {
        for (final player in [match.homePlayer, match.awayPlayer]) {
          if (player == null) continue;
          final key = player.profileId ?? player.name;
          players[key] = player;
          losses.putIfAbsent(key, () => 0);
        }
        if (!match.hasResult) continue;
        final loser = match.loser;
        if (loser == null) continue;
        final key = loser.profileId ?? loser.name;
        losses[key] = (losses[key] ?? 0) + 1;
      }
    }

    final activeCount = players.keys
        .where((key) => (losses[key] ?? 0) < lossLimit)
        .length;
    return activeCount <= advancingCount;
  }

  List<TournamentPlayer> limitAdvancingPlayers(
    List<TournamentPlayer> rankedPlayers,
    int? advancingCount,
  ) => advancingCount == null
      ? List<TournamentPlayer>.from(rankedPlayers)
      : rankedPlayers.take(advancingCount).toList();
}
