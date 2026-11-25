import '../domain/tournament_models.dart';
import '../domain/tournament_flow_priority_settings.dart';

class TournamentFlowPriority {
  const TournamentFlowPriority({
    required this.prioritizedMatches,
    required this.deprioritizedMatches,
    required this.delayedGroups,
    required this.notices,
  });

  static const defaultSettings = TournamentFlowPrioritySettings();

  final Set<GroupMatch> prioritizedMatches;
  final Set<GroupMatch> deprioritizedMatches;
  final Set<String> delayedGroups;
  final List<String> notices;

  factory TournamentFlowPriority.forStage(
    TournamentRunStage? stage, {
    TournamentFlowPrioritySettings settings = defaultSettings,
    CreatedTournament? tournament,
  }) {
    if (!settings.enabled ||
        stage is! GroupTournamentRunStage ||
        stage.groups.isEmpty) {
      return const TournamentFlowPriority(
        prioritizedMatches: {},
        deprioritizedMatches: {},
        delayedGroups: {},
        notices: [],
      );
    }

    final priorities = <GroupMatch>{};
    final deprioritized = <GroupMatch>{};
    final delayedGroups = <String>{};
    final notices = <String>[];
    final leagueScope = _leaguePlayerScope(tournament);
    if (leagueScope == null) {
      final groupProgress = [
        for (final group in stage.groups)
          _GroupProgress(
            played: _playedMatches(group.matches),
            possible: _possibleMatches(group),
          ),
      ];
      final referenceMatches = groupProgress
          .map((progress) => progress.possible)
          .reduce((a, b) => a > b ? a : b);
      final leadingProgress = groupProgress
          .map((progress) => progress.fraction)
          .reduce((a, b) => a > b ? a : b);
      // Keep the configured match threshold meaningful using the longest group schedule.
      final groupDeficits = <int>[
        for (final progress in groupProgress)
          settings.usePercentageForGroups && referenceMatches > 0
              ? ((leadingProgress - progress.fraction) * referenceMatches)
                    .round()
              : groupProgress
                        .map((item) => item.played)
                        .reduce((a, b) => a > b ? a : b) -
                    progress.played,
      ];
      final maximumGroupDeficit = groupDeficits.reduce(
        (a, b) => a > b ? a : b,
      );
      if (maximumGroupDeficit >= settings.groupMatchDeficitThreshold) {
        final trailingGroups = <String>[];
        for (var index = 0; index < stage.groups.length; index++) {
          if (groupDeficits[index] < settings.groupMatchDeficitThreshold) {
            continue;
          }
          final group = stage.groups[index];
          delayedGroups.add(group.name);
          trailingGroups.add(group.name);
          priorities.addAll(group.matches.where(_isPrioritizable));
        }
        if (trailingGroups.isNotEmpty) {
          notices.add(
            settings.usePercentageForGroups
                ? 'Priorität: ${trailingGroups.join(', ')} liegen im Spielplanfortschritt '
                      'mindestens ${settings.groupMatchDeficitThreshold} von '
                      '$referenceMatches möglichen Partien zurück. Offene Partien '
                      'dieser Gruppen bevorzugt ansetzen.'
                : 'Priorität: ${trailingGroups.join(', ')} liegen bei den gespielten Partien '
                      'mindestens $maximumGroupDeficit Partien zurück. Offene Partien '
                      'dieser Gruppen bevorzugt ansetzen.',
          );
        }
      }
    }

    final playerNotices = <String>[];
    for (final group in stage.groups) {
      final playedByPlayer = <String, int>{};
      final namesByPlayer = <String, String>{};
      if (leagueScope == null) {
        for (final player in group.players) {
          for (final individual in player.individuals) {
            final id = individual.profileId ?? individual.name;
            playedByPlayer.putIfAbsent(id, () => 0);
            namesByPlayer[id] = individual.name;
          }
        }
      } else {
        playedByPlayer.addAll({
          for (final entry in leagueScope.activePlayers.entries) entry.key: 0,
        });
        namesByPlayer.addAll(leagueScope.activePlayers);
      }
      for (final match in group.matches) {
        if (!_countsAsPlayed(match)) continue;
        for (final player in [match.homePlayer, match.awayPlayer]) {
          if (player == null) continue;
          for (final individual in player.individuals) {
            final id = individual.profileId ?? individual.name;
            if (leagueScope != null &&
                !leagueScope.activePlayers.containsKey(id)) {
              continue;
            }
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
                mostPlayedPlayer - entry.value >=
                    settings.playerMatchDeficitThreshold &&
                (leagueScope == null ||
                    leagueScope.substitutedPlayers.contains(entry.key)),
          )
          .map((entry) => entry.key)
          .toSet();
      if (laggingPlayers.isEmpty) continue;
      final leadingPlayers = playedByPlayer.entries
          .where((entry) => entry.value == mostPlayedPlayer)
          .map((entry) => entry.key)
          .toSet();

      final names = laggingPlayers.map((id) => namesByPlayer[id] ?? id).toList()
        ..sort();
      playerNotices.add(
        'Priorität: ${names.join(', ')} haben in ${group.name} mindestens '
        '${settings.playerMatchDeficitThreshold} Partien Rückstand. Offene Partien mit '
        'diesen Teilnehmern bevorzugt ansetzen.',
      );
      for (final match in group.matches.where(_isPrioritizable)) {
        final matchPlayers = {
          for (final player in [match.homePlayer, match.awayPlayer])
            if (player != null)
              ...player.individuals.map((p) => p.profileId ?? p.name),
        };
        if (matchPlayers.any(laggingPlayers.contains)) {
          priorities.add(match);
          if (matchPlayers.any(leadingPlayers.contains)) {
            deprioritized.add(match);
          }
        }
      }
    }
    // Group-level delays can prioritize every open match; keep matches involving
    // a caught-up player behind opportunities for lagging players to catch up.
    for (final group in leagueScope == null ? stage.groups : const <TournamentGroup>[]) {
      final playedByPlayer = <String, int>{};
      for (final player in group.players) {
        for (final individual in player.individuals) {
          playedByPlayer.putIfAbsent(
            individual.profileId ?? individual.name,
            () => 0,
          );
        }
      }
      for (final match in group.matches.where(_countsAsPlayed)) {
        for (final player in [match.homePlayer, match.awayPlayer]) {
          if (player == null) continue;
          for (final individual in player.individuals) {
            final id = individual.profileId ?? individual.name;
            playedByPlayer.update(id, (count) => count + 1, ifAbsent: () => 1);
          }
        }
      }
      if (playedByPlayer.isEmpty) continue;
      final highestPlayed = playedByPlayer.values.reduce(
        (a, b) => a > b ? a : b,
      );
      final leadingPlayers = playedByPlayer.entries
          .where((entry) => entry.value == highestPlayed)
          .map((entry) => entry.key)
          .toSet();
      for (final match in group.matches.where(priorities.contains)) {
        final matchPlayers = {
          for (final player in [match.homePlayer, match.awayPlayer])
            if (player != null)
              ...player.individuals.map((p) => p.profileId ?? p.name),
        };
        if (matchPlayers.any(leadingPlayers.contains)) {
          deprioritized.add(match);
        }
      }
    }
    notices.insertAll(0, playerNotices);

    return TournamentFlowPriority(
      prioritizedMatches: Set.unmodifiable(priorities),
      deprioritizedMatches: Set.unmodifiable(deprioritized),
      delayedGroups: Set.unmodifiable(delayedGroups),
      notices: List.unmodifiable(notices),
    );
  }

  static int _playedMatches(Iterable<GroupMatch> matches) =>
      matches.where(_countsAsPlayed).length;

  static int _possibleMatches(TournamentGroup group) =>
      group.matches.where((match) => match.hasPlayers).length;

  static bool _countsAsPlayed(GroupMatch match) =>
      match.hasResult && match.hasPlayers && !match.withdrawalIgnored;

  static bool _isPrioritizable(GroupMatch match) =>
      match.hasPlayers &&
      !match.isResolved &&
      match.startedAt == null &&
      match.boardNumber == null;

  static _LeaguePlayerScope? _leaguePlayerScope(
    CreatedTournament? tournament,
  ) {
    final league = tournament?.leagueMatch;
    if (league == null || tournament == null) return null;
    final activePlayers = <String, String>{};
    final substitutedPlayers = <String>{};
    for (var side = 0; side < 2; side++) {
      final roster = side == 0 ? league.homePlayers : league.awayPlayers;
      final offset = side == 0 ? 0 : league.homePlayers.length;
      final substitutedIndexes = league.substitutions
          .where((event) => event.teamSide == side)
          .map((event) => event.inPlayerIndex)
          .toSet();
      for (final index in league.activePlayers(side)) {
        if (index < 0 || index >= roster.length) continue;
        final sourceIndex = offset + index;
        final hasSourcePlayer = tournament.players.length > sourceIndex &&
            tournament.players[sourceIndex].name == roster[index];
        final id = hasSourcePlayer
            ? tournament.players[sourceIndex].profileId ??
                  'league:${tournament.id}:$side:$index'
            : 'league:${tournament.id}:$side:$index';
        activePlayers[id] = roster[index];
        if (substitutedIndexes.contains(index)) substitutedPlayers.add(id);
      }
    }
    return _LeaguePlayerScope(
      activePlayers: activePlayers,
      substitutedPlayers: substitutedPlayers,
    );
  }
}

class _GroupProgress {
  const _GroupProgress({required this.played, required this.possible});

  final int played;
  final int possible;

  double get fraction => possible == 0 ? 0 : played / possible;
}

class _LeaguePlayerScope {
  const _LeaguePlayerScope({
    required this.activePlayers,
    required this.substitutedPlayers,
  });

  final Map<String, String> activePlayers;
  final Set<String> substitutedPlayers;
}
