import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const controller = OrderOfPlayController();

  test('three groups on four boards keep their assigned boards', () {
    final players = [
      for (var index = 1; index <= 16; index++)
        TournamentPlayer.generated(index),
    ];
    List<TournamentGroup> buildGroups() {
      List<GroupMatch> matches(List<TournamentPlayer> group) => [
        for (var home = 0; home < group.length; home++)
          for (var away = home + 1; away < group.length; away++)
            GroupMatch(
              homePlayer: group[home],
              awayPlayer: group[away],
              round: 1,
            ),
      ];
      return [
        TournamentGroup(
          name: 'A',
          playType: 'round_robin',
          players: players.sublist(0, 6),
          matches: matches(players.sublist(0, 6)),
        ),
        TournamentGroup(
          name: 'B',
          playType: 'round_robin',
          players: players.sublist(6, 11),
          matches: matches(players.sublist(6, 11)),
        ),
        TournamentGroup(
          name: 'C',
          playType: 'round_robin',
          players: players.sublist(11, 16),
          matches: matches(players.sublist(11, 16)),
        ),
      ];
    }

    final tournament = CreatedTournament(
      name: 'Repro',
      players: players,
      stages: const [],
      boardCount: 4,
      directorModeEnabled: true,
      directorSchedulingStrategy: 'group',
      directorPlayOrderMode: 'fixed_schedule',
      directorMultiBoardAssignmentBehavior: 'mirror',
      groupBoardAssignments: const {
        '0:A': [1, 2],
        '0:B': [3],
        '0:C': [4],
      },
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppen',
          groupPlayType: 'round_robin',
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
          groups: buildGroups(),
        ),
      ],
    );
    controller.initializeFixedSchedule(tournament);
    final snapshot = TournamentDirectorSnapshot(tournament, 0);
    final plan = controller.plan(tournament, 0).planned;
    final fixedGroups = controller
        .entries(tournament)
        .where((entry) => entry.stageIndex == 0)
        .toList()
      ..sort(
        (a, b) => (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
          b.match.fixedScheduleOrder ?? 1 << 30,
        ),
      );

    // Block-major order: best match for every board before the second best.
    expect(
      fixedGroups.take(4).map((entry) => entry.groupKey).toList(),
      ['0:A', '0:A', '0:B', '0:C'],
    );
    expect(
      fixedGroups.skip(4).take(4).map((entry) => entry.groupKey).toList(),
      ['0:A', '0:A', '0:B', '0:C'],
    );

    expect(snapshot.configuredBoardsByGroup()['0:A'], [1, 2]);
    expect(snapshot.configuredBoardsByGroup()['0:B'], [3]);
    expect(snapshot.configuredBoardsByGroup()['0:C'], [4]);

    final groupsByBoard = <int, Set<String>>{
      for (var board = 1; board <= 4; board++)
        board: plan
            .where((assignment) => assignment.board == board)
            .map((assignment) => assignment.entry.groupKey ?? '')
            .toSet(),
    };
    expect(groupsByBoard[1], {'0:A'});
    expect(groupsByBoard[2], {'0:A'});
    expect(groupsByBoard[3], {'0:B'});
    expect(groupsByBoard[4], {'0:C'});

    for (var board = 1; board <= 4; board++) {
      final upcomingGroups = snapshot
          .upcomingForBoard(board)
          .map((assignment) => assignment.entry.groupKey)
          .toSet();
      expect(upcomingGroups.every((group) => group != '0:A' || board <= 2), isTrue);
      final recommendation = snapshot.recommendationForBoard(board);
      if (recommendation != null) {
        expect(
          board <= 2 || recommendation.next.entry.groupKey != '0:A',
          isTrue,
        );
      }
    }
  });
}
