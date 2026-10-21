import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_advancement_forecast_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

GroupTournamentRunStage _stage({
  required List<TournamentPlayer> players,
  required List<GroupMatch> matches,
  int qualifiers = 2,
}) => GroupTournamentRunStage(
  name: 'Gruppenphase',
  groupPlayType: 'round_robin',
  groups: [
    TournamentGroup(
      name: 'Gruppe A',
      playType: 'round_robin',
      players: players,
      matches: matches,
    ),
  ],
  qualificationPlan: QualificationPlan(
    totalQualifiers: qualifiers,
    fixedPerGroup: qualifiers,
    extraCount: 0,
    extraRank: 0,
    eligibleGroupSize: players.length,
    extraGroups: const [],
  ),
  tieBreakers: const ['points', 'legDifference', 'legsFor'],
);

void main() {
  test('equal six-player group starts with an even group-win forecast', () {
    final players = [
      for (var index = 0; index < 6; index++)
        TournamentPlayer.generated(index + 1),
    ];
    final matches = [
      for (var home = 0; home < players.length; home++)
        for (var away = home + 1; away < players.length; away++)
          GroupMatch(
            homePlayer: players[home],
            awayPlayer: players[away],
            round: 1,
          ),
    ];
    final result = const GroupAdvancementForecastEngine().calculate(
      stage: _stage(players: players, matches: matches),
      simulations: 3000,
      seed: 7,
    );

    expect(result, hasLength(6));
    for (final chance in result.values) {
      expect(chance.groupWinProbability, inInclusiveRange(11, 22));
      expect(chance.advancementProbability, inInclusiveRange(28, 39));
    }
  });

  test('forecast combines Elo and historical win rate', () {
    final stronger = TournamentPlayer(
      name: 'Stark',
      profileId: 'strong',
      isGenerated: false,
    );
    final weaker = TournamentPlayer(
      name: 'Schwach',
      profileId: 'weak',
      isGenerated: false,
    );
    final result = const GroupAdvancementForecastEngine().calculate(
      stage: _stage(
        players: [stronger, weaker],
        matches: [
          GroupMatch(homePlayer: stronger, awayPlayer: weaker, round: 1),
        ],
        qualifiers: 1,
      ),
      players: const {
        'strong': GroupAdvancementPlayerData(
          rating: 1300,
          historicalWinRate: 0.7,
        ),
        'weak': GroupAdvancementPlayerData(rating: 700, historicalWinRate: 0.3),
      },
      simulations: 2000,
      seed: 11,
    );

    expect(
      result['strong']!.groupWinProbability,
      greaterThan(result['weak']!.groupWinProbability),
    );
    expect(result['strong']!.groupWinProbability, greaterThan(80));
  });

  test('a completed win raises the winner chance over the even baseline', () {
    final players = [
      for (var index = 0; index < 6; index++)
        TournamentPlayer.generated(index + 1),
    ];
    final matches = [
      GroupMatch(
        homePlayer: players[0],
        awayPlayer: players[1],
        round: 1,
        homeLegs: 2,
        awayLegs: 0,
      ),
      for (var home = 0; home < players.length; home++)
        for (var away = home + 1; away < players.length; away++)
          if (home != 0 || away != 1)
            GroupMatch(
              homePlayer: players[home],
              awayPlayer: players[away],
              round: 1,
            ),
    ];
    final result = const GroupAdvancementForecastEngine().calculate(
      stage: _stage(players: players, matches: matches),
      simulations: 3000,
      seed: 23,
    );

    expect(result[players[0].name]!.groupWinProbability, greaterThan(16.7));
    expect(result[players[1].name]!.groupWinProbability, lessThan(16.7));
  });
}
