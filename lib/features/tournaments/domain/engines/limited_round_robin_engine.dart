import 'dart:math';

import '../../../rankings/domain/local_elo_calculator.dart';
import '../tournament_models.dart';

/// Configurable opponent selection for a limited round robin.
const List<String> limitedRoundRobinMatchmakingStrategies = [
  'elo',
  'random',
  'similar',
  'mixed',
];

String limitedRoundRobinMatchmakingLabel(String strategy) => switch (strategy) {
  'random' => 'Zufällig',
  'similar' => 'Etwa gleichstarke Gegner',
  'mixed' => 'Ausgewogene Mischung aus starken und schwachen Gegnern',
  _ => 'Nach Elo',
};

/// Fixed, balanced opponent schedule. Unlike Swiss, results do not affect draws.
class LimitedRoundRobinEngine {
  static List<GroupMatch> build(
    List<TournamentPlayer> players, {
    required int maxGamesPerPlayer,
    int repeatCount = 1,
    String matchmakingStrategy = 'elo',
    Map<String, int> ratings = const {},
    int? seed,
  }) {
    if (maxGamesPerPlayer < 1) {
      throw ArgumentError.value(maxGamesPerPlayer, 'maxGamesPerPlayer');
    }
    final n = players.length;
    if (n < 2) return [];
    final orderedPlayers = _orderPlayers(
      players,
      strategy: matchmakingStrategy,
      ratings: ratings,
      seed: seed,
    );
    final capacity = (n - 1) * (repeatCount < 1 ? 1 : repeatCount);
    var remaining = maxGamesPerPlayer < capacity ? maxGamesPerPlayer : capacity;
    final result = <GroupMatch>[];
    var offset = 0;
    while (remaining > 0) {
      final degree = remaining < n - 1 ? remaining : n - 1;
      final pairs = <(int, int)>[];
      for (var distance = 1; distance <= degree ~/ 2; distance++) {
        for (var i = 0; i < n; i++) {
          pairs.add((i, (i + distance) % n));
        }
      }
      if (degree.isOdd) {
        if (n.isEven) {
          for (var i = 0; i < n ~/ 2; i++) {
            pairs.add((i, i + n ~/ 2));
          }
        } else {
          final step = n ~/ 2;
          for (var i = 0; i < n - 1; i += 2) {
            pairs.add(((i * step) % n, ((i + 1) * step) % n));
          }
        }
      }
      final occupied = <Set<int>>[];
      for (final pair in pairs) {
        var round = 0;
        while (round < occupied.length &&
            (occupied[round].contains(pair.$1) ||
                occupied[round].contains(pair.$2))) {
          round++;
        }
        if (round == occupied.length) occupied.add({});
        occupied[round].addAll([pair.$1, pair.$2]);
        result.add(
          GroupMatch(
            homePlayer: orderedPlayers[pair.$1],
            awayPlayer: orderedPlayers[pair.$2],
            round: offset + round + 1,
          ),
        );
      }
      offset += occupied.length;
      remaining -= degree;
    }
    result.sort((a, b) => a.round.compareTo(b.round));
    return result;
  }

  static List<TournamentPlayer> _orderPlayers(
    List<TournamentPlayer> players, {
    required String strategy,
    required Map<String, int> ratings,
    int? seed,
  }) {
    final ordered = List<TournamentPlayer>.from(players);
    final hasRatings = players.every(
      (player) => ratings.containsKey(player.profileId ?? player.name),
    );
    int ratingOf(TournamentPlayer player) =>
        ratings[player.profileId ?? player.name] ?? defaultEloRating;

    switch (strategy) {
      case 'random':
        final deterministicSeed =
            seed ?? players.fold<int>(17, (sum, p) => sum + p.name.hashCode);
        ordered.shuffle(Random(deterministicSeed));
        return ordered;
      case 'similar':
        if (!hasRatings) return ordered;
        ordered.sort((a, b) => ratingOf(b).compareTo(ratingOf(a)));
        final similar = <TournamentPlayer>[];
        for (var index = 0; index < ordered.length; index += 4) {
          similar.addAll(ordered.skip(index).take(2));
          similar.addAll(
            ordered.skip(index + 2).take(2).toList().reversed,
          );
        }
        return similar;
      case 'mixed':
        if (!hasRatings) return ordered;
        ordered.sort((a, b) => ratingOf(b).compareTo(ratingOf(a)));
        final mixed = <TournamentPlayer>[];
        var start = 0;
        var end = ordered.length - 1;
        while (start <= end) {
          mixed.add(ordered[start++]);
          if (start <= end) mixed.add(ordered[end--]);
        }
        return mixed;
      case 'elo':
      default:
        if (!hasRatings) return ordered;
        ordered.sort((a, b) => ratingOf(b).compareTo(ratingOf(a)));
        return ordered;
    }
  }
}
