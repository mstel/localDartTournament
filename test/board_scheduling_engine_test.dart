import 'package:flutter_test/flutter_test.dart';

import 'package:dart_tournament_manager/features/tournaments/domain/engines/board_scheduling_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/schedule_priority_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

TournamentPlayer _player(String name) =>
    TournamentPlayer(name: name, isGenerated: false, profileId: name);

GroupMatch _match(
  String home,
  String away, {
  int? homeLegs,
  int? awayLegs,
  DateTime? finishedAt,
  int round = 1,
}) => GroupMatch(
  homePlayer: _player(home),
  awayPlayer: _player(away),
  round: round,
  homeLegs: homeLegs,
  awayLegs: awayLegs,
  finishedAt: finishedAt,
);

PlayEntry _entry(
  String home,
  String away, {
  String? group = 'A',
  int stage = 0,
  int? homeLegs,
  int? awayLegs,
  DateTime? finishedAt,
  int round = 1,
}) => PlayEntry(
  _match(
    home,
    away,
    homeLegs: homeLegs,
    awayLegs: awayLegs,
    finishedAt: finishedAt,
    round: round,
  ),
  stage,
  '$home vs $away',
  group == null ? null : '0:$group',
);

void main() {
  final now = DateTime(2026, 11, 24, 12);

  test('shared priority context prefers a long waiting match over a lower '
      'play count', () {
    final longWait = _entry('A1', 'A2');
    final shortWait = _entry('B1', 'B2');
    final oldEnd = now.subtract(const Duration(minutes: 40));
    final recentEnd = now.subtract(const Duration(minutes: 2));
    final finished = [
      _entry('B1', 'Z', homeLegs: 3, awayLegs: 1, finishedAt: recentEnd),
      for (var i = 0; i < 3; i++)
        _entry(
          'A1',
          'X$i',
          homeLegs: 3,
          awayLegs: 0,
          finishedAt: oldEnd,
          round: i + 1,
        ),
      for (var i = 0; i < 3; i++)
        _entry(
          'A2',
          'Y$i',
          homeLegs: 3,
          awayLegs: 0,
          finishedAt: oldEnd,
          round: i + 1,
        ),
    ];
    final all = [longWait, shortWait, ...finished];
    final context = SchedulePriorityContext.build(
      all: all,
      finished: finished,
      running: const [],
      now: now,
    );
    const engine = BoardSchedulingEngine();

    final shared = engine.schedule(
      all: all,
      ready: [shortWait, longWait],
      finished: finished,
      boardCount: 1,
      strategy: 'global',
      priorityContext: context,
    );
    expect(shared.first.entry, longWait);

    final withoutContext = engine.schedule(
      all: all,
      ready: [shortWait, longWait],
      finished: finished,
      boardCount: 1,
      strategy: 'global',
    );
    expect(withoutContext.first.entry, shortWait);
  });

  test('bindGroupBoards leaves a board idle instead of borrowing another '
      'group', () {
    final groupA = _entry('A1', 'A2', group: 'A');
    final groupB = _entry('B1', 'B2', group: 'B');
    final planned = const BoardSchedulingEngine().schedule(
      all: [groupA, groupB],
      ready: [groupA, groupB],
      boardCount: 2,
      blockedBoards: {2},
      strategy: 'group',
      assignGroupsToBoards: true,
      groupBoardAssignments: {
        '0:A': {1},
        '0:B': {2},
      },
      bindGroupBoards: true,
    );

    expect(planned, hasLength(1));
    expect(planned.single.entry, groupA);
    expect(planned.single.board, 1);
  });

  test('bindGroupBoards=false lets another group use an idle board', () {
    final groupA = _entry('A1', 'A2', group: 'A');
    final groupB = _entry('B1', 'B2', group: 'B');
    final planned = const BoardSchedulingEngine().schedule(
      all: [groupA, groupB],
      ready: [groupA, groupB],
      boardCount: 2,
      blockedBoards: {2},
      strategy: 'group',
      assignGroupsToBoards: true,
      groupBoardAssignments: {
        '0:A': {1},
        '0:B': {2},
      },
    );

    expect(planned, hasLength(2));
    expect(planned.first.entry, groupA);
    expect(planned.last.entry, groupB);
    expect(planned.last.board, 1);
  });

  test('sequence strategy keeps the original entry order with a priority '
      'context', () {
    final first = _entry('S1', 'S2');
    final second = _entry('S3', 'S4', group: 'B');
    final finished = [
      _entry(
        'S3',
        'X',
        homeLegs: 3,
        awayLegs: 0,
        finishedAt: now.subtract(const Duration(minutes: 2)),
      ),
    ];
    final all = [first, second, ...finished];
    final context = SchedulePriorityContext.build(
      all: all,
      finished: finished,
      running: const [],
      now: now,
    );
    const engine = BoardSchedulingEngine();

    final shared = engine.schedule(
      all: all,
      ready: [second, first],
      finished: finished,
      boardCount: 1,
      strategy: 'sequence',
      priorityContext: context,
    );
    expect(shared.first.entry, first);

    final withoutContext = engine.schedule(
      all: all,
      ready: [second, first],
      finished: finished,
      boardCount: 1,
      strategy: 'sequence',
    );
    expect(withoutContext.first.entry, first);
  });
}
