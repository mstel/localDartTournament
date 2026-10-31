import '../domain/tournament_models.dart';

class TournamentFlowPriority {
  const TournamentFlowPriority({
    required this.prioritizedMatches,
    required this.notices,
  });

  static const playerMatchDeficitThreshold = 2;
  static const groupMatchDeficitThreshold = 3;

  final Set<GroupMatch> prioritizedMatches;
  final List<String> notices;

  factory TournamentFlowPriority.forStage(TournamentRunStage? stage) {
    if (stage is! GroupTournamentRunStage || stage.groups.isEmpty) {
      return const TournamentFlowPriority(prioritizedMatches: {}, notices: []);
    }

    final priorities = <GroupMatch>{};
    final notices = <String>[];
    final groupPlayedCounts = [
      for (final group in stage.groups) _playedMatches(group.matches),
    ];
    final groupMatchTotals = [
      for (final group in stage.groups) group.matches.length,
    ];
    final mostPlayedGroup = groupPlayedCounts.reduce((a, b) => a > b ? a : b);
    final leastPlayedGroup = groupPlayedCounts.reduce((a, b) => a < b ? a : b);
    final groupDeficit = mostPlayedGroup - leastPlayedGroup;
    final groupProgress = <double>[];
    for (var index = 0; index < stage.groups.length; index++) {
      final total = groupMatchTotals[index];
      groupProgress.add(total == 0 ? 0.0 : groupPlayedCounts[index] / total);
    }
    final mostPlayedRatio = groupProgress.isEmpty ? 0.0 : groupProgress.reduce((a, b) => a > b ? a : b);
    final lowestPlayedRatio = groupProgress.isEmpty ? 0.0 : groupProgress.reduce((a, b) => a < b ? a : b);
    final shouldPrioritizeGroupLag =
        groupDeficit >= groupMatchDeficitThreshold ||
        (groupProgress.length > 1 && (mostPlayedRatio - lowestPlayedRatio) >= 0.5);
    if (shouldPrioritizeGroupLag) {
      final trailingGroups = <String>[];
      for (var index = 0; index < stage.groups.length; index++) {
        final groupMatches = groupPlayedCounts[index];
        final totalMatches = groupMatchTotals[index];
        final ratio = totalMatches == 0 ? 0.0 : groupMatches / totalMatches;
        final lagBehindLeader =
            mostPlayedGroup - groupMatches >= groupMatchDeficitThreshold ||
            (groupDeficit >= groupMatchDeficitThreshold &&
                (mostPlayedRatio - ratio) >= 0.25);
        if (!lagBehindLeader) {
          continue;
        }
        final group = stage.groups[index];
        trailingGroups.add(group.name);
        priorities.addAll(group.matches.where(_isPrioritizable));
      }
      if (trailingGroups.isNotEmpty) {
        notices.add(
          'Priorität: ${trailingGroups.join(', ')} liegen bei den gespielten Partien '
          'mindestens $groupDeficit Partien zurück. Offene Partien dieser '
          'Gruppen bevorzugt ansetzen.',
        );
      }
    }

    final playerNotices = <String>[];
    for (final group in stage.groups) {
      final playedByPlayer = <String, int>{};
      final namesByPlayer = <String, String>{};
      for (final player in group.players) {
        for (final individual in player.individuals) {
          final id = individual.profileId ?? individual.name;
          playedByPlayer.putIfAbsent(id, () => 0);
          namesByPlayer[id] = individual.name;
        }
      }
      for (final match in group.matches) {
        if (!_countsAsPlayed(match)) continue;
        for (final player in [match.homePlayer, match.awayPlayer]) {
          if (player == null) continue;
          for (final individual in player.individuals) {
            final id = individual.profileId ?? individual.name;
            playedByPlayer.update(id, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      }
      if (playedByPlayer.isEmpty) continue;

      final mostPlayedPlayer = playedByPlayer.values.reduce(
        (a, b) => a > b ? a : b,
      );
      final laggingPlayers = playedByPlayer.entries
          .where(
            (entry) =>
                mostPlayedPlayer - entry.value >= playerMatchDeficitThreshold,
          )
          .map((entry) => entry.key)
          .toSet();
      if (laggingPlayers.isEmpty) continue;

      final names = laggingPlayers.map((id) => namesByPlayer[id] ?? id).toList()
        ..sort();
      playerNotices.add(
        'Priorität: ${names.join(', ')} haben in ${group.name} mindestens '
        '$playerMatchDeficitThreshold Partien Rückstand. Offene Partien mit '
        'diesen Spielern bevorzugt ansetzen.',
      );
      for (final match in group.matches.where(_isPrioritizable)) {
        final matchPlayers = {
          for (final player in [match.homePlayer, match.awayPlayer])
            if (player != null)
              ...player.individuals.map((p) => p.profileId ?? p.name),
        };
        if (matchPlayers.any(laggingPlayers.contains)) {
          priorities.add(match);
        }
      }
    }
    notices.insertAll(0, playerNotices);

    return TournamentFlowPriority(
      prioritizedMatches: Set.unmodifiable(priorities),
      notices: List.unmodifiable(notices),
    );
  }

  static int _playedMatches(Iterable<GroupMatch> matches) =>
      matches.where(_countsAsPlayed).length;

  static bool _countsAsPlayed(GroupMatch match) =>
      match.hasResult && match.hasPlayers && !match.withdrawalIgnored;

  static bool _isPrioritizable(GroupMatch match) =>
      match.hasPlayers &&
      !match.isResolved &&
      match.startedAt == null &&
      match.boardNumber == null;
}
