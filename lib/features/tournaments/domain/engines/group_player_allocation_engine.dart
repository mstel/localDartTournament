import 'dart:math';

import '../tournament_models.dart';

enum GroupPlayerAllocationMode { strengthLevels, balanced, random, manual }

class GroupPlayerAllocationEngine {
  const GroupPlayerAllocationEngine();

  List<TournamentPlayer> allocate({
    required List<TournamentPlayer> players,
    required List<int> groupSizes,
    required GroupPlayerAllocationMode mode,
    Map<String, int> ratings = const {},
    Random? random,
  }) {
    if (groupSizes.isEmpty ||
        groupSizes.any((size) => size < 1) ||
        groupSizes.fold<int>(0, (sum, size) => sum + size) != players.length) {
      throw ArgumentError('Group sizes must exactly match the player count.');
    }

    final ordered = [...players];
    switch (mode) {
      case GroupPlayerAllocationMode.strengthLevels:
      case GroupPlayerAllocationMode.balanced:
        ordered.sort((a, b) {
          final ratingComparison = _rating(
            b,
            ratings,
          ).compareTo(_rating(a, ratings));
          return ratingComparison != 0
              ? ratingComparison
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case GroupPlayerAllocationMode.random:
        ordered.shuffle(random ?? Random());
      case GroupPlayerAllocationMode.manual:
        throw ArgumentError(
          'Manual group allocation requires a saved group slot order.',
        );
    }

    final groups = List.generate(
      groupSizes.length,
      (_) => <TournamentPlayer>[],
    );
    if (mode == GroupPlayerAllocationMode.balanced) {
      for (var index = 0; index < ordered.length; index++) {
        var groupIndex = index % groups.length;
        while (groups[groupIndex].length >= groupSizes[groupIndex]) {
          groupIndex = (groupIndex + 1) % groups.length;
        }
        groups[groupIndex].add(ordered[index]);
      }
    } else {
      var playerIndex = 0;
      for (var groupIndex = 0; groupIndex < groupSizes.length; groupIndex++) {
        groups[groupIndex].addAll(
          ordered.skip(playerIndex).take(groupSizes[groupIndex]),
        );
        playerIndex += groupSizes[groupIndex];
      }
    }
    return groups.expand((group) => group).toList(growable: false);
  }

  int _rating(TournamentPlayer player, Map<String, int> ratings) =>
      player.profileId == null ? 1000 : ratings[player.profileId!] ?? 1000;
}
