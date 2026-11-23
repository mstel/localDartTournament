import '../../league/application/league_board_runtime.dart';
import '../../tournaments/application/tournament_info_summary.dart';
import '../../tournaments/application/tournament_timing.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/domain/engines/group_standings_engine.dart';
import '../../tournaments/domain/knockout_round_names.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/tournament_winner.dart';
import 'live_tournament_names.dart';
import '../domain/live_tournament_payload.dart';

/// Projects an existing tournament into the public spectator read model.
///
/// All standings, progression and format text come from the production
/// engines; this class only selects allowed fields and anonymises names.
class LiveTournamentPayloadBuilder {
  const LiveTournamentPayloadBuilder({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  LiveTournamentPayload build(
    CreatedTournament source, {
    String channel = 'verein-live',
    Map<String, PlayerProfile> profiles = const {},
  }) {
    final now = _now();
    final effective = source.leagueMatch == null
        ? source
        : LeagueBoardRuntime(source).tournament;
    final timing = TournamentTiming.snapshot(source, now);
    final resultMatches = TournamentTiming.matches(effective)
        .where((match) => !match.isAnnulled)
        .toList();
    final scheduled = TournamentTiming.scheduledMatches(effective)
        .where((match) => !match.isAnnulled)
        .toList();

    final playerIds = <TournamentPlayer, String>{};
    for (var i = 0; i < effective.players.length; i++) {
      final player = effective.players[i];
      playerIds[player] = player.profileId ?? 'player-${i + 1}';
    }
    String idOf(TournamentPlayer? player) {
      if (player == null) return 'open';
      final known = playerIds[player];
      if (known != null) return known;
      final byName = effective.players
          .where((candidate) => candidate.name == player.name)
          .firstOrNull;
      return byName == null
          ? 'player-${player.name.hashCode.toRadixString(16)}'
          : (playerIds[byName] ?? 'player-unknown');
    }

    String nameOf(TournamentPlayer? player) =>
        livePlayerName(player, profiles: profiles);

    String anonymizeText(String value) {
      final known = effective.players
          .where((player) => player.name == value)
          .firstOrNull;
      if (known != null) return nameOf(known);
      final parts = value.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) return value;
      return '${parts.first} ${parts.last[0]}.';
    }

    final players = <String, LiveTournamentPlayer>{};
    for (final player in effective.players) {
      final id = idOf(player);
      players.putIfAbsent(
        id,
        () => LiveTournamentPlayer(id: id, name: nameOf(player)),
      );
    }

    final matches = [for (final match in scheduled) _liveMatch(match, nameOf)];

    final standings = <LiveStandingGroup>[];
    for (final stage in effective.runStages) {
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          final rows = const GroupStandingsEngine()
              .calculate(group, stage.tieBreakers, tournament: effective)
              .map(
                (standing) => LiveStandingRow(
                  playerId: idOf(standing.player),
                  name: nameOf(standing.player),
                  played: standing.played,
                  wins: standing.wins,
                  draws: standing.draws,
                  losses: standing.losses,
                  points: standing.points,
                ),
              )
              .toList();
          standings.add(LiveStandingGroup(name: group.name, rows: rows));
        }
      }
    }

    final bracket = <LiveBracketRound>[];
    for (final stage in effective.runStages) {
      if (stage is KnockoutTournamentRunStage) {
        for (var i = 0; i < stage.rounds.length; i++) {
          final round = stage.rounds[i];
          if (round.isEmpty) continue;
          bracket.add(
            LiveBracketRound(
              name: knockoutRoundColumnTitle(round, i, stage.rounds.length),
              matches: [for (final match in round) _liveMatch(match, nameOf)],
            ),
          );
        }
        if (stage.placementMatches.isNotEmpty) {
          bracket.add(
            LiveBracketRound(
              name: 'Platzierung',
              matches: [
                for (final match in stage.placementMatches)
                  _liveMatch(match, nameOf),
              ],
            ),
          );
        }
      } else if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          for (var i = 0; i < group.knockoutRounds.length; i++) {
            final round = group.knockoutRounds[i];
            if (round.isEmpty) continue;
            bracket.add(
              LiveBracketRound(
                name: knockoutRoundColumnTitle(
                  round,
                  i,
                  group.knockoutRounds.length,
                ),
                matches: [for (final match in round) _liveMatch(match, nameOf)],
              ),
            );
          }
          if (group.placementMatches.isNotEmpty) {
            bracket.add(
              LiveBracketRound(
                name: 'Platzierung',
                matches: [
                  for (final match in group.placementMatches)
                    _liveMatch(match, nameOf),
                ],
              ),
            );
          }
        }
      }
    }

    final bestPerformances = <LiveBestPerformance>[];
    final seenPerformances = <String>{};
    for (final match in resultMatches) {
      for (final performance in match.bestPerformances) {
        final performer = performance.playerProfileId == null
            ? anonymizeText(performance.playerName)
            : livePlayerName(
                TournamentPlayer(
                  name: performance.playerName,
                  profileId: performance.playerProfileId,
                  isGenerated: false,
                ),
                profiles: profiles,
              );
        final key =
            '$performer|${performance.normalizedType.name}|'
            '${performance.value}|${performance.details}';
        if (!seenPerformances.add(key)) continue;
        bestPerformances.add(
          LiveBestPerformance(
            player: performer,
            label: performance.label,
            value: performance.value,
            details: performance.details,
          ),
        );
      }
    }

    final finished = source.finishedAt != null;
    final winnerName = TournamentWinner.name(effective);
    final finalMatch = _finalMatch(effective, nameOf);
    final endScreen = finished
        ? LiveEndScreen(
            winner: winnerName == null ? null : anonymizeText(winnerName),
            resultLine: finalMatch == null
                ? null
                : '${finalMatch.home} ${finalMatch.homeLegs ?? '–'} : '
                    '${finalMatch.awayLegs ?? '–'} ${finalMatch.away}',
            finishedAt: source.finishedAt,
          )
        : null;

    return LiveTournamentPayload(
      channel: channel,
      generatedAt: now,
      tournamentName: source.name,
      tournamentDate: source.tournamentDate,
      status: finished ? 'finished' : 'running',
      formatLines: _formatLines(effective),
      clock: LiveTournamentClock(
        startedAt: source.startedAt,
        forecastEnd: timing.forecast,
        elapsedSeconds: timing.elapsed.inSeconds,
        finishedAt: source.finishedAt,
      ),
      players: players.values.toList(),
      standings: standings,
      bracket: bracket,
      matches: matches,
      bestPerformances: bestPerformances,
      endScreen: endScreen,
    );
  }

  List<String> _formatLines(CreatedTournament tournament) {
    final lines = <String>[];
    for (final stage in tournament.stages) {
      final format = stage.gameFormat.label.replaceFirst(' · ', ' ');
      if (stage.isGroupStage) {
        lines.add(format);
        lines.add('Gruppen');
        final advancement = TournamentInfoSummary.advancement(stage);
        if (advancement != 'Keine Weiterkommen-Regel') {
          final match = RegExp(r'^(\d+) weiter').firstMatch(advancement);
          lines.add(
            match == null ? advancement : 'Top ${match.group(1)} weiter',
          );
        }
      } else {
        lines.add('Single KO Finale $format');
      }
      lines.add(
        'Tie-Breaker: '
        '${TournamentInfoSummary.tieBreakers(stage.groupTieBreakers)}',
      );
    }
    final hasPlacementMatch = tournament.runStages.any(
      (stage) => switch (stage) {
        KnockoutTournamentRunStage() => stage.placementMatches.isNotEmpty,
        GroupTournamentRunStage() => stage.groups.any(
          (group) => group.placementMatches.isNotEmpty,
        ),
        _ => false,
      },
    );
    if (hasPlacementMatch) lines.add('Spiel um Platz 3');
    return lines;
  }

  LiveMatch _liveMatch(
    GroupMatch match,
    String Function(TournamentPlayer?) nameOf,
  ) {
    final home = nameOf(match.homePlayer);
    final away = nameOf(match.awayPlayer);
    final status = match.hasResult
        ? 'finished'
        : match.startedAt != null
        ? 'running'
        : 'open';
    return LiveMatch(
      id: 'm${match.round}-$home-$away',
      home: home,
      away: away,
      homeLegs: match.hasResult ? match.homeLegs : null,
      awayLegs: match.hasResult ? match.awayLegs : null,
      status: status,
      label: match.label ?? '',
    );
  }

  LiveMatch? _finalMatch(
    CreatedTournament tournament,
    String Function(TournamentPlayer?) nameOf,
  ) {
    for (var i = tournament.runStages.length - 1; i >= 0; i--) {
      final stage = tournament.runStages[i];
      if (stage is KnockoutTournamentRunStage &&
          stage.rounds.isNotEmpty &&
          stage.rounds.last.length == 1 &&
          stage.rounds.last.single.hasResult) {
        final match = stage.rounds.last.single;
        return LiveMatch(
          id: 'final-${match.round}',
          home: nameOf(match.homePlayer),
          away: nameOf(match.awayPlayer),
          homeLegs: match.homeLegs,
          awayLegs: match.awayLegs,
          status: 'finished',
          label: 'Finale',
        );
      }
    }
    return null;
  }
}
