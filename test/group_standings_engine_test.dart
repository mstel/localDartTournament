import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_standings_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates the persisted previous default tie-breaker order', () {
    const previousDefault = [
      'points',
      'legDifference',
      'legsFor',
      'headToHead',
    ];
    final stage = TournamentStage(
      name: 'Gruppenphase',
      type: 'groups',
      groupSizes: const [2],
      groupTieBreakers: previousDefault,
    );
    final tournament = CreatedTournament.fromJson({
      'name': 'Testturnier',
      'players': const [],
      'stages': [stage.toJson()],
      'runStages': [
        {
          'kind': 'groups',
          'name': 'Gruppenphase',
          'groupPlayType': 'round_robin',
          'groups': const [],
          'tieBreakers': previousDefault,
        },
      ],
    });

    expect(tournament.stages.single.groupTieBreakers, defaultGroupTieBreakers);
    expect(
      (tournament.runStages.single as GroupTournamentRunStage).tieBreakers,
      defaultGroupTieBreakers,
    );
  });

  test(
    'default tie-breakers use head-to-head before aggregate leg difference',
    () {
      final first =
          PlayerStanding(
              TournamentPlayer.generated(1).copyWith(name: 'Spieler A'),
            )
            ..points = 6
            ..legsFor = 19
            ..legsAgainst = 12;
      final second =
          PlayerStanding(
              TournamentPlayer.generated(2).copyWith(name: 'Spieler B'),
            )
            ..points = 6
            ..legsFor = 20
            ..legsAgainst = 15;
      final directMatch = GroupMatch(
        homePlayer: second.player,
        awayPlayer: first.player,
        round: 1,
        homeLegs: 2,
        awayLegs: 1,
      );

      expect(defaultGroupTieBreakers, [
        'points',
        'headToHead',
        'legDifference',
        'legsFor',
      ]);
      expect(
        const GroupStandingsEngine().compare(
          first,
          second,
          defaultGroupTieBreakers,
          matches: [directMatch],
        ),
        greaterThan(0),
      );
    },
  );

  test('unfinished direct matches do not decide tied standings', () {
    final first = PlayerStanding(TournamentPlayer.generated(1));
    final second = PlayerStanding(TournamentPlayer.generated(2));
    final unfinishedMatch = GroupMatch(
      homePlayer: first.player,
      awayPlayer: second.player,
      round: 1,
    );

    expect(
      () => const GroupStandingsEngine().compare(
        first,
        second,
        defaultGroupTieBreakers,
        matches: [unfinishedMatch],
      ),
      returnsNormally,
    );
  });
}
