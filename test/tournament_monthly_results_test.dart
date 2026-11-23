import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/statistics/domain/tournament_monthly_results.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

CreatedTournament _tournament({
  required String id,
  required DateTime date,
  required TournamentPlayer player,
  required TournamentPlayer opponent,
  required List<GroupMatch> matches,
}) {
  return CreatedTournament(
    id: id,
    name: id,
    players: [player, opponent],
    stages: const [],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppe',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          TournamentGroup(
            name: 'Gruppe A',
            playType: 'round_robin',
            players: [player, opponent],
            matches: matches,
          ),
        ],
      ),
    ],
    tournamentDate: date,
  );
}

void main() {
  const calculator = TournamentMonthlyResultCalculator();
  final player = TournamentPlayer(
    profileId: 'player-1',
    name: 'Ada',
    isGenerated: false,
  );
  final other = TournamentPlayer(
    profileId: 'player-2',
    name: 'Bert',
    isGenerated: false,
  );
  final unassigned = TournamentPlayer.generated(9);

  test('derives monthly wins, losses and matches from assigned tournaments', () {
    final tournaments = [
      _tournament(
        id: 'october',
        date: DateTime(2026, 10, 5),
        player: player,
        opponent: other,
        matches: [
          GroupMatch(
            homePlayer: player,
            awayPlayer: other,
            round: 1,
            homeLegs: 3,
            awayLegs: 1,
            finishedAt: DateTime(2026, 10, 5),
          ),
          GroupMatch(
            homePlayer: other,
            awayPlayer: player,
            round: 2,
            homeLegs: 3,
            awayLegs: 3,
            finishedAt: DateTime(2026, 10, 6),
          ),
          GroupMatch(
            homePlayer: player,
            awayPlayer: unassigned,
            round: 3,
            homeLegs: 3,
            awayLegs: 2,
            finishedAt: DateTime(2026, 10, 7),
          ),
          GroupMatch(
            homePlayer: player,
            awayPlayer: other,
            round: 4,
            homeLegs: 3,
            awayLegs: 0,
            isAnnulled: true,
            finishedAt: DateTime(2026, 10, 8),
          ),
        ],
      ),
      _tournament(
        id: 'november',
        date: DateTime(2026, 11, 2),
        player: player,
        opponent: other,
        matches: [
          GroupMatch(
            homePlayer: other,
            awayPlayer: player,
            round: 1,
            homeLegs: 3,
            awayLegs: 2,
            finishedAt: DateTime(2026, 11, 2),
          ),
        ],
      ),
    ];

    final results = calculator.calculate(tournaments, playerIds: {'player-1'});

    expect(results, hasLength(2));
    expect(results.first.playerId, 'player-1');
    expect(results.first.year, 2026);
    expect(results.first.month, 10);
    expect(results.first.matches, 3);
    expect(results.first.wins, 2);
    expect(results.first.losses, 0);
    expect(results.first.weightedLegs, 15);
    expect(results.first.winRate, closeTo(66.666, 0.001));
    expect(results.last.month, 11);
    expect(results.last.matches, 1);
    expect(results.last.wins, 0);
    expect(results.last.losses, 1);
    expect(results.last.winRate, 0);
  });

  test('includes singles results from league and friendly matches', () {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: const ['Ada'],
      awayPlayers: const ['Bert'],
      singlesPerPlayer: 1,
      doublesCount: 0,
      gameFormat: const TournamentGameFormat(bestOfLegs: 3),
    );
    league.games.single.score(2, 1, format: league.gameFormat);
    final tournament = CreatedTournament(
      id: 'league',
      name: 'Ligaspiel',
      players: [player, other],
      stages: const [],
      runStages: const [],
      leagueMatch: league,
      tournamentDate: DateTime(2026, 9, 12),
    );

    final results = calculator.calculate([tournament], playerIds: {'player-1'});

    expect(results, hasLength(1));
    expect(results.single.year, 2026);
    expect(results.single.month, 9);
    expect(results.single.matches, 1);
    expect(results.single.wins, 1);
    expect(results.single.losses, 0);
  });

  test('recomputing from the same tournaments never inflates counters', () {
    final tournaments = [
      _tournament(
        id: 'same',
        date: DateTime(2026, 8, 1),
        player: player,
        opponent: other,
        matches: [
          GroupMatch(
            homePlayer: player,
            awayPlayer: other,
            round: 1,
            homeLegs: 3,
            awayLegs: 1,
            finishedAt: DateTime(2026, 8, 1),
          ),
        ],
      ),
    ];

    final first = calculator.calculate(tournaments, playerIds: {'player-1'});
    final second = calculator.calculate(tournaments, playerIds: {'player-1'});

    expect(second.single.matches, first.single.matches);
    expect(second.single.wins, first.single.wins);
    expect(second.single.losses, first.single.losses);
  });
}
