import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/application/order_of_play/order_of_play_controller.dart';

/// Adapts league fixtures to the existing scheduling and result-entry logic.
/// Only the league document is persisted; the projection is rebuilt on load.
class LeagueBoardRuntime {
  LeagueBoardRuntime(CreatedTournament source) {
    final league = source.leagueMatch!;
    TournamentPlayer entrant(int side, List<int> indexes) {
      final names = side == 0 ? league.homePlayers : league.awayPlayers;
      final offset = side == 0 ? 0 : league.homePlayers.length;
      final people = [
        for (final i in indexes)
          if (source.players.length > offset + i &&
              source.players[offset + i].name == names[i])
            source.players[offset + i].copyWith(
              profileId:
                  source.players[offset + i].profileId ??
                  'league:${source.id}:$side:$i',
            )
          else
            TournamentPlayer(
              name: names[i],
              profileId: 'league:${source.id}:$side:$i',
              isGenerated: false,
            ),
      ];
      return people.length == 1 ? people.single : TournamentPlayer.team(people);
    }

    matches = [
      for (var i = 0; i < league.games.length; i++)
        GroupMatch.fromJson({
          ...?league.games[i].runtime,
          'round': i + 1,
          'homePlayer': entrant(0, league.games[i].home).toJson(),
          'awayPlayer': entrant(1, league.games[i].away).toJson(),
          'homeLegs': league.games[i].homeLegs,
          'awayLegs': league.games[i].awayLegs,
          'homeSets': league.games[i].homeSets,
          'awaySets': league.games[i].awaySets,
        }),
    ];
    tournament = CreatedTournament(
      id: source.id,
      name: source.name,
      countsForRanking: source.countsForRanking,
      rankingIds: source.rankingIds,
      boardCount: source.boardCount,
      players: source.players,
      stages: [
        TournamentStage(
          name: 'Ligaspiel',
          type: 'groups',
          gameFormat: league.gameFormat,
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Ligaspiel',
          groupPlayType: 'round_robin',
          qualificationPlan: null,
          tieBreakers: const [],
          groups: [
            TournamentGroup(
              name: 'Spielplan',
              playType: 'round_robin',
              players: source.players,
              matches: matches,
            ),
          ],
        ),
      ],
      completedStageIndexes: league.complete ? {0} : {},
    );
  }
  late final CreatedTournament tournament;
  late final List<GroupMatch> matches;
  void installOn(CreatedTournament target) {
    target.stages
      ..clear()
      ..addAll(tournament.stages);
    target.runStages
      ..clear()
      ..addAll(tournament.runStages);
    target.completedStageIndexes
      ..clear()
      ..addAll(tournament.completedStageIndexes);
    target.activeStageIndex = 0;
  }

  BoardSchedule get schedule =>
      const OrderOfPlayController().plan(tournament, 0);
  void writeTo(CreatedTournament target) {
    for (var i = 0; i < matches.length; i++) {
      final game = target.leagueMatch!.games[i];
      final match = matches[i];
      if (target.leagueMatch!.gameFormat.bestOfSets > 1) {
        game.score(
          match.homeSets,
          match.awaySets,
          format: target.leagueMatch!.gameFormat,
          legsHome: match.homeLegs,
          legsAway: match.awayLegs,
        );
      } else {
        game.score(
          match.homeLegs,
          match.awayLegs,
          format: target.leagueMatch!.gameFormat,
        );
      }
      game.runtime = match.toJson();
    }
  }
}
