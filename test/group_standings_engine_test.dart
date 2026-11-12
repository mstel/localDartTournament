import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_standings_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates the persisted previous default tie-breaker order', () {
    const previousDefault = [
      'points',
      'headToHead',
      'legDifference',
      'legsFor',
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
    'default tie-breakers use aggregate leg difference before head-to-head',
    () {
      final first =
          PlayerStanding(
              TournamentPlayer.generated(1).copyWith(name: 'Teilnehmer A'),
            )
            ..points = 6
            ..legsFor = 19
            ..legsAgainst = 12;
      final second =
          PlayerStanding(
              TournamentPlayer.generated(2).copyWith(name: 'Teilnehmer B'),
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
        'legDifference',
        'legsFor',
        'headToHead',
      ]);
      expect(
        const GroupStandingsEngine().compare(
          first,
          second,
          defaultGroupTieBreakers,
          matches: [directMatch],
        ),
        lessThan(0),
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

  test(
    'decider round robin orders three or more tied players by its table',
    () {
      final first = TournamentPlayer.generated(1).copyWith(name: 'A');
      final second = TournamentPlayer.generated(2).copyWith(name: 'B');
      final third = TournamentPlayer.generated(3).copyWith(name: 'C');
      final standings = [first, second, third].map(PlayerStanding.new).toList();
      final matches = [
        GroupMatch(
          homePlayer: first,
          awayPlayer: third,
          round: 1,
          label: 'Decider',
          isDecider: true,
          homeLegs: 2,
          awayLegs: 0,
        ),
        GroupMatch(
          homePlayer: third,
          awayPlayer: second,
          round: 1,
          label: 'Decider',
          isDecider: true,
          homeLegs: 2,
          awayLegs: 1,
        ),
      ];

      expect(
        const GroupStandingsEngine().compare(
          standings[0],
          standings[1],
          defaultGroupTieBreakers,
          matches: matches,
        ),
        lessThan(0),
      );
    },
  );

  test('stores optional decider settings and its format', () {
    const format = TournamentGameFormat(bestOfLegs: 3);
    final configured = TournamentStage(
      name: 'Gruppenphase',
      type: 'groups',
      groupSizes: const [4, 4],
      allowGroupTieBreakDeciders: true,
      tieBreakGameFormat: format,
    );

    final restored = TournamentStage.fromJson(configured.toJson());
    expect(restored.allowGroupTieBreakDeciders, isTrue);
    expect(restored.tieBreakGameFormat.toJson(), format.toJson());
  });
}
