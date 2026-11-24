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

  test('waiting time outweighs the number of already played matches', () {
    final longWaiting = _entry('Marvin', 'A', round: 1);
    final fresh = _entry('B', 'C', round: 2);
    final finished = [
      _entry(
        'Marvin',
        'X',
        homeLegs: 3,
        awayLegs: 0,
        finishedAt: now.subtract(const Duration(minutes: 40)),
      ),
      _entry(
        'B',
        'Y',
        homeLegs: 3,
        awayLegs: 1,
        finishedAt: now.subtract(const Duration(minutes: 2)),
      ),
      _entry(
        'B',
        'Z',
        homeLegs: 3,
        awayLegs: 2,
        finishedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];
    final context = SchedulePriorityContext.build(
      all: [longWaiting, fresh, ...finished],
      finished: finished,
      running: const [],
      now: now,
    );
    final engine = const SchedulePriorityEngine();
    expect(
      engine.waitingSinceLastMatch(longWaiting, context),
      const Duration(minutes: 40),
    );
    expect(
      engine.waitingSinceLastMatch(fresh, context),
      const Duration(minutes: 1),
    );
    expect(engine.sorted([fresh, longWaiting], context).first, longWaiting);
  });

  test('group progress separates finished, running and previewed matches', () {
    final context = SchedulePriorityContext.build(
      all: [
        _entry('A1', 'A2'),
        _entry('A3', 'A4'),
        _entry('B1', 'B2', group: 'B'),
      ],
      finished: [_entry('A1', 'A2', homeLegs: 3, awayLegs: 0, finishedAt: now)],
      running: const [],
      projected: [_entry('A3', 'A4')],
      now: now,
    );
    final groupA = context.groups['0:A']!;
    final groupB = context.groups['0:B']!;
    expect(groupA.completed, 1);
    expect(groupA.projected, 1);
    expect(groupA.progressScore, closeTo(0.625, 0.0001));
    expect(groupB.progressScore, 0);
    expect(groupB.remaining, greaterThan(groupA.remaining));
  });

  test('absolute remaining workload breaks equal progress ratios', () {
    final small = _entry('S1', 'S2', group: 'small');
    final large = _entry('L1', 'L2', group: 'large');
    final context = SchedulePriorityContext.build(
      all: [
        small,
        _entry('S3', 'S4', group: 'small'),
        ...[for (var i = 0; i < 5; i++) _entry('L$i', 'X$i', group: 'large')],
      ],
      finished: const [],
      running: const [],
      now: now,
    );
    final engine = const SchedulePriorityEngine();
    expect(
      engine.sorted([small, large], context).first.match.homePlayer!.name,
      'L1',
    );
  });

  test('original order is the stable tie breaker', () {
    final first = _entry('A', 'B');
    final second = _entry('C', 'D');
    final context = SchedulePriorityContext.build(
      all: [first, second],
      finished: const [],
      running: const [],
      now: now,
    );
    const engine = SchedulePriorityEngine();
    expect(engine.sorted([second, first], context).first, first);
  });
}
