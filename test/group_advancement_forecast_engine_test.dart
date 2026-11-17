import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_advancement_forecast_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

GroupTournamentRunStage _stage({
  required List<TournamentPlayer> players,
  required List<GroupMatch> matches,
  int qualifiers = 2,
  List<String> tieBreakers = defaultGroupTieBreakers,
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
  tieBreakers: tieBreakers,
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

  test(
    'forecast applies direct comparison before aggregate leg difference',
    () {
      final first = TournamentPlayer.generated(
        1,
      ).copyWith(name: 'Teilnehmer A');
      final second = TournamentPlayer.generated(
        2,
      ).copyWith(name: 'Teilnehmer B');
      final third = TournamentPlayer.generated(
        3,
      ).copyWith(name: 'Teilnehmer C');
      final matches = [
        GroupMatch(
          homePlayer: second,
          awayPlayer: first,
          round: 1,
          homeLegs: 2,
          awayLegs: 1,
        ),
        GroupMatch(
          homePlayer: first,
          awayPlayer: third,
          round: 1,
          homeLegs: 2,
          awayLegs: 0,
        ),
        GroupMatch(
          homePlayer: first,
          awayPlayer: third,
          round: 2,
          homeLegs: 2,
          awayLegs: 0,
        ),
        GroupMatch(
          homePlayer: second,
          awayPlayer: third,
          round: 1,
          homeLegs: 2,
          awayLegs: 0,
        ),
        GroupMatch(
          homePlayer: third,
          awayPlayer: second,
          round: 2,
          homeLegs: 2,
          awayLegs: 0,
        ),
      ];

      final result = const GroupAdvancementForecastEngine().calculate(
        stage: _stage(
          players: [first, second, third],
          matches: matches,
          qualifiers: 1,
          tieBreakers: const [
            'points',
            'headToHead',
            'legDifference',
            'legsFor',
          ],
        ),
        simulations: 20,
        seed: 41,
      );

      expect(result[second.name]!.groupWinProbability, 100);
      expect(result[first.name]!.groupWinProbability, 0);
    },
  );

  test('eight players with two advancing per group forecast a 12.5% tournament win', () {
    final players = [
      for (var index = 0; index < 8; index++)
        TournamentPlayer.generated(index + 1),
    ];
    final groups = [
      for (var groupIndex = 0; groupIndex < 2; groupIndex++)
        TournamentGroup(
          name: 'Gruppe ${groupIndex + 1}',
          playType: 'round_robin',
          players: players.sublist(groupIndex * 4, groupIndex * 4 + 4),
          matches: [
            for (var home = 0; home < 4; home++)
              for (var away = home + 1; away < 4; away++)
                GroupMatch(
                  homePlayer: players[groupIndex * 4 + home],
                  awayPlayer: players[groupIndex * 4 + away],
                  round: 1,
                ),
          ],
        ),
    ];
    final stage = GroupTournamentRunStage(
      name: 'Gruppenphase',
      groupPlayType: 'round_robin',
      groups: groups,
      qualificationPlan: QualificationPlan(
        totalQualifiers: 4,
        fixedPerGroup: 2,
        extraCount: 0,
        extraRank: 0,
        eligibleGroupSize: 4,
        extraGroups: const [],
        fixedByGroup: const [2, 2],
      ),
      tieBreakers: defaultGroupTieBreakers,
    );
    final knockout = KnockoutTournamentRunStage(
      name: 'K.-o.-Phase',
      rounds: [
        [
          GroupMatch(round: 1),
          GroupMatch(round: 1),
        ],
        [GroupMatch(round: 2)],
      ],
      participants: players,
    );
    final result = const GroupAdvancementForecastEngine().calculate(
      stage: stage,
      knockoutStage: knockout,
      simulations: 4000,
      seed: 31,
    );

    expect(result, hasLength(8));
    for (final chance in result.values) {
      expect(chance.advancementProbability, inInclusiveRange(47, 53));
      expect(chance.tournamentWinProbability, inInclusiveRange(11, 14));
    }
  });
}
