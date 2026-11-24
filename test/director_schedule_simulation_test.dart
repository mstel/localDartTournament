import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/global_waitlist_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/global_waitlist_state.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/modes/swiss/swiss_engine.dart';

const _controller = OrderOfPlayController();

CreatedTournament _tournament({
  required int groupCount,
  required int boards,
  required Set<int> blockedBoards,
}) {
  const names = ['A', 'B', 'C', 'D', 'E', 'F'];
  final players = [
    for (var index = 1; index <= groupCount * 4; index++)
      TournamentPlayer.generated(1000 + index),
  ];
  final freeBoards = [
    for (var board = 1; board <= boards; board++)
      if (!blockedBoards.contains(board)) board,
  ];
  final groups = <TournamentGroup>[];
  final assignments = <String, List<int>>{};
  for (var groupIndex = 0; groupIndex < groupCount; groupIndex++) {
    final name = names[groupIndex];
    final members = players.sublist(groupIndex * 4, groupIndex * 4 + 4);
    groups.add(
      TournamentGroup(
        name: name,
        playType: 'round_robin',
        players: members,
        matches: [
          for (var home = 0; home < members.length; home++)
            for (var away = home + 1; away < members.length; away++)
              GroupMatch(
                homePlayer: members[home],
                awayPlayer: members[away],
                round: 1,
              ),
        ],
      ),
    );
    assignments['0:$name'] = [freeBoards[groupIndex % freeBoards.length]];
  }
  return CreatedTournament(
    id: 'director-simulation-$groupCount-$boards',
    name: 'Simulation',
    players: players,
    stages: const [],
    boardCount: boards,
    blockedBoards: blockedBoards,
    directorGroupBoardAssignments: assignments,
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppen',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: groups,
      ),
    ],
  );
}

void _initializeGlobalWaitlist(CreatedTournament t) {
  final snapshot = TournamentDirectorSnapshot(t, 0);
  _controller.initializeGlobalWaitlist(
    t,
    0,
    allEntries: snapshot.entries,
    schedule: snapshot.schedule,
    isPreviewable: snapshot.isPreviewableMatch,
  );
}

List<int> _freeBoards(CreatedTournament t, BoardSchedule schedule) => [
  for (var board = 1; board <= t.boardCount; board++)
    if (!t.blockedBoards.contains(board) &&
        !schedule.running.any((entry) => entry.match.boardNumber == board))
      board,
];

int _startOpenMatches(
  CreatedTournament t,
  int count, {
  Set<GroupMatch> exclude = const {},
}) {
  var started = 0;
  var attempts = 0;
  while (started < count && attempts < 200) {
    attempts++;
    final schedule = _controller.plan(t, 0);
    final boards = _freeBoards(t, schedule);
    if (boards.isEmpty) break;
    final candidate = schedule.planned
        .where(
          (assignment) =>
              !exclude.contains(assignment.entry.match) &&
              !assignment.entry.match.isResolved &&
              !schedule.running.any(
                (entry) => entry.players.any(assignment.entry.players.contains),
              ),
        )
        .firstOrNull;
    if (candidate == null) break;
    if (!_controller.start(t, 0, candidate.entry.match, boards.first)) {
      exclude = {...exclude, candidate.entry.match};
    } else {
      started++;
      exclude = {...exclude, candidate.entry.match};
    }
  }
  return started;
}

void _assertCollisionFree(CreatedTournament t, BoardSchedule schedule) {
  final runningPlayers = <String>{};
  final runningBoards = <int>{};
  for (final entry in schedule.running) {
    expect(entry.match.boardNumber, isNotNull);
    runningBoards.add(entry.match.boardNumber!);
    for (final player in entry.players) {
      expect(
        runningPlayers.add(player),
        isTrue,
        reason: 'running player $player',
      );
    }
    expect(t.blockedBoards.contains(entry.match.boardNumber), isFalse);
  }
  for (final assignment in schedule.planned) {
    expect(t.blockedBoards.contains(assignment.board), isFalse);
    if (assignment.block == 0) {
      expect(runningBoards.contains(assignment.board), isFalse);
      expect(
        assignment.entry.players.any(runningPlayers.contains),
        isFalse,
        reason: 'planned match collides with a running player',
      );
    }
  }
  final blocks = schedule.planned.map((assignment) => assignment.block).toSet();
  for (final block in blocks) {
    final players = <String>{};
    final boards = <int>{};
    final wave = schedule.planned.where((item) => item.block == block);
    for (final assignment in wave) {
      expect(boards.add(assignment.board), isTrue);
      for (final player in assignment.entry.players) {
        expect(
          players.add(player),
          isTrue,
          reason: 'block $block player $player',
        );
      }
    }
  }
}

void main() {
  for (final groupCount in [2, 4, 6]) {
    for (final boards in [2, 4, 5]) {
      for (final runningCount in [0, 2]) {
        final blockedBoards = boards >= 4 ? <int>{boards} : <int>{};
        final label =
            '$groupCount groups / $boards boards / $runningCount running';

        test('fixed + group binding boards - $label', () {
          final t =
              _tournament(
                  groupCount: groupCount,
                  boards: boards,
                  blockedBoards: blockedBoards,
                )
                ..directorModeEnabled = true
                ..directorSchedulingStrategy = 'group'
                ..directorPlayOrderMode = 'fixed_schedule';
          _controller.initializeFixedSchedule(t);
          expect(_startOpenMatches(t, runningCount), runningCount);

          final schedule = _controller.plan(t, 0);
          for (final assignment in schedule.planned) {
            final groupKey = assignment.entry.groupKey!;
            expect(
              t.directorGroupBoardAssignments[groupKey],
              contains(assignment.board),
              reason: '$groupKey spilled onto board ${assignment.board}',
            );
          }
          _assertCollisionFree(t, schedule);
        });

        test('fixed + global recommendation start - $label', () {
          final t =
              _tournament(
                  groupCount: groupCount,
                  boards: boards,
                  blockedBoards: blockedBoards,
                )
                ..directorModeEnabled = true
                ..directorSchedulingStrategy = 'global'
                ..directorPlayOrderMode = 'fixed_schedule';
          _controller.initializeFixedSchedule(t);
          final entries = _controller.entries(t);
          final orders = {
            for (final entry in entries)
              entry.match: entry.match.fixedScheduleOrder,
          };
          final last = entries.reduce(
            (a, b) => a.match.fixedScheduleOrder! > b.match.fixedScheduleOrder!
                ? a
                : b,
          );
          final freeBoard = _freeBoards(t, _controller.plan(t, 0)).first;

          expect(_controller.start(t, 0, last.match, freeBoard), isTrue);
          if (runningCount > 1) {
            expect(
              _startOpenMatches(t, runningCount - 1, exclude: {last.match}),
              runningCount - 1,
            );
          }
          for (final entry in entries) {
            expect(entry.match.fixedScheduleOrder, orders[entry.match]);
          }
          _assertCollisionFree(t, _controller.plan(t, 0));
        });

        test('dynamic global preview and collisions - $label', () {
          final t =
              _tournament(
                  groupCount: groupCount,
                  boards: boards,
                  blockedBoards: blockedBoards,
                )
                ..directorModeEnabled = true
                ..directorSchedulingStrategy = 'global'
                ..directorPlayOrderMode = 'dynamic';
          _initializeGlobalWaitlist(t);
          final before = TournamentDirectorSnapshot(t, 0).globalWaitlist;
          expect(before.fixed.length, GlobalWaitlistState.defaultFixedCount);

          final busyPreview = before.fixed.first;
          final blocker = TournamentDirectorSnapshot(t, 0).entries.firstWhere(
            (entry) =>
                !before.fixed.any(
                  (fixed) => identical(fixed.match, entry.match),
                ) &&
                entry.players.any(busyPreview.players.contains) &&
                !entry.match.isResolved,
          );
          final blockerBoard = _freeBoards(t, _controller.plan(t, 0)).first;
          expect(_controller.start(t, 0, blocker.match, blockerBoard), isTrue);
          if (runningCount > 1) {
            expect(
              _startOpenMatches(
                t,
                runningCount - 1,
                exclude: {blocker.match, busyPreview.match},
              ),
              runningCount - 1,
            );
          }

          final after = TournamentDirectorSnapshot(t, 0).globalWaitlist;
          expect(
            after.fixed.map((entry) => entry.match),
            contains(busyPreview.match),
          );
          expect(after.isSkipped(busyPreview), isTrue);
          expect(after.next?.match, isNot(busyPreview.match));
          // A temporarily busy preview keeps its slot as SKIPPED; if no
          // collision-free refill exists the compact preview may be shorter.
          expect(
            after.fixed.length,
            lessThanOrEqualTo(GlobalWaitlistState.defaultFixedCount),
          );
          expect(
            after.fixed.map((entry) => entry.match),
            isNot(contains(blocker.match)),
          );
          expect(
            t.directorGlobalWaitlist.fixedKeys(0),
            hasLength(after.fixed.length),
          );
          expect(
            after.dynamic.length,
            lessThanOrEqualTo(GlobalWaitlistEngine.dynamicPreviewCount),
          );
          _assertCollisionFree(t, _controller.plan(t, 0));
        });

        test('newly appended pairing is playable - $label', () {
          final t =
              _tournament(
                  groupCount: groupCount,
                  boards: boards,
                  blockedBoards: blockedBoards,
                )
                ..directorModeEnabled = true
                ..directorSchedulingStrategy = 'global'
                ..directorPlayOrderMode = 'fixed_schedule';
          _controller.initializeFixedSchedule(t);
          final stage = t.runStages.single as GroupTournamentRunStage;
          final group = stage.groups.first;
          final newPlayer = TournamentPlayer.generated(9000 + groupCount);
          t.players.add(newPlayer);
          group.players.add(newPlayer);
          final newMatch = GroupMatch(
            homePlayer: newPlayer,
            awayPlayer: group.players.first,
            round: 2,
          );
          group.matches.add(newMatch);

          _controller.initializeFixedSchedule(t);
          final orders = _controller
              .entries(t)
              .map((entry) => entry.match.fixedScheduleOrder)
              .toList();
          expect(
            newMatch.fixedScheduleOrder,
            orders.reduce((a, b) => a! > b! ? a : b),
          );

          final board = _freeBoards(t, _controller.plan(t, 0)).first;
          expect(_controller.start(t, 0, newMatch, board), isTrue);
          _assertCollisionFree(t, _controller.plan(t, 0));
        });
      }
    }
  }

  test('fixedScheduleOrder covers Swiss, Kratzer and KO bracket slots', () {
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(2000 + index).copyWith(name: 'P$index'),
    ];
    final swissPlayers = players.sublist(0, 6);
    final swissMatches = SwissEngine.build(swissPlayers, 2);
    final koMatches = [
      [
        GroupMatch(homePlayer: players[0], awayPlayer: players[1], round: 1),
        GroupMatch(homePlayer: players[2], awayPlayer: players[3], round: 1),
      ],
      [GroupMatch(round: 2), GroupMatch(round: 2)],
    ];
    final kratzerMatch = GroupMatch(
      homePlayer: players[4],
      awayPlayer: players[5],
      round: 1,
      isKratzer: true,
    );
    final tournament = CreatedTournament(
      id: 'director-simulation-stage-orders',
      name: 'Stages',
      players: players,
      stages: const [],
      boardCount: 4,
      directorModeEnabled: true,
      directorSchedulingStrategy: 'global',
      directorPlayOrderMode: 'fixed_schedule',
      runStages: [
        GroupTournamentRunStage(
          name: 'Swiss',
          groupPlayType: 'swiss',
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
          groups: [
            TournamentGroup(
              name: 'Swiss',
              playType: 'swiss',
              players: swissPlayers,
              matches: swissMatches,
            ),
          ],
        ),
        KnockoutTournamentRunStage(name: 'KO', rounds: koMatches),
        KnockoutTournamentRunStage(
          name: 'Kratzer',
          isKratzer: true,
          rounds: [
            [kratzerMatch],
          ],
        ),
      ],
    );

    _controller.initializeFixedSchedule(tournament);
    final entries = _controller.entries(tournament);
    expect(entries, isNotEmpty);
    expect(
      entries.every((entry) => entry.match.fixedScheduleOrder != null),
      isTrue,
    );

    final orders = entries
        .map((entry) => entry.match.fixedScheduleOrder!)
        .toList();
    expect(orders.toSet(), hasLength(orders.length));

    final orderedByStage = <int, List<PlayEntry>>{
      for (final stage in {0, 1, 2})
        stage: entries.where((entry) => entry.stageIndex == stage).toList()
          ..sort(
            (a, b) => a.match.fixedScheduleOrder!.compareTo(
              b.match.fixedScheduleOrder!,
            ),
          ),
    };
    expect(orderedByStage[0]!.isNotEmpty, isTrue);
    expect(orderedByStage[1]!.isNotEmpty, isTrue);
    expect(orderedByStage[2]!.isNotEmpty, isTrue);
    expect(
      orderedByStage[0]!.last.match.fixedScheduleOrder,
      lessThan(orderedByStage[1]!.first.match.fixedScheduleOrder!),
    );
    expect(
      orderedByStage[1]!.last.match.fixedScheduleOrder,
      lessThan(orderedByStage[2]!.first.match.fixedScheduleOrder!),
    );
    // Future bracket slots have no players yet, but still keep a fixed place.
    expect(koMatches.last.first.fixedScheduleOrder, isNotNull);
  });

  test(
    'a running match in an earlier stage blocks later-stage players and boards',
    () {
      final players = [
        for (var index = 1; index <= 6; index++)
          TournamentPlayer.generated(3000 + index).copyWith(name: 'P$index'),
      ];
      final stageOneMatch = GroupMatch(
        homePlayer: players[0],
        awayPlayer: players[1],
        round: 1,
      );
      final collidingPlayer = GroupMatch(
        homePlayer: players[0],
        awayPlayer: players[2],
        round: 1,
      );
      final collidingBoard = GroupMatch(
        homePlayer: players[2],
        awayPlayer: players[3],
        round: 1,
      );
      final freeMatch = GroupMatch(
        homePlayer: players[4],
        awayPlayer: players[5],
        round: 1,
      );
      final tournament = CreatedTournament(
        id: 'director-simulation-cross-stage',
        name: 'Stage overlap',
        players: players,
        stages: const [],
        boardCount: 2,
        directorModeEnabled: true,
        directorSchedulingStrategy: 'global',
        directorPlayOrderMode: 'fixed_schedule',
        runStages: [
          GroupTournamentRunStage(
            name: 'Gruppen',
            groupPlayType: 'round_robin',
            qualificationPlan: null,
            tieBreakers: defaultGroupTieBreakers,
            groups: [
              TournamentGroup(
                name: 'A',
                playType: 'round_robin',
                players: players.sublist(0, 2),
                matches: [stageOneMatch],
              ),
            ],
          ),
          KnockoutTournamentRunStage(
            name: 'KO',
            rounds: [
              [collidingPlayer, collidingBoard, freeMatch],
            ],
          ),
        ],
      );
      _controller.initializeFixedSchedule(tournament);
      expect(_controller.start(tournament, 0, stageOneMatch, 1), isTrue);

      final schedule = _controller.plan(tournament, 1);
      expect(schedule.running, isEmpty);
      expect(
        schedule.blockingRunning.map((entry) => entry.match),
        contains(stageOneMatch),
      );
      expect(
        schedule.planned
            .where((assignment) => assignment.block == 0)
            .map((assignment) => assignment.entry.match),
        orderedEquals([freeMatch]),
      );

      expect(_controller.suggestForBoard(tournament, 1, 1), isNull);
      expect(
        _controller.suggestForBoard(tournament, 1, 2)?.entry.match,
        freeMatch,
      );
      expect(_controller.start(tournament, 1, collidingPlayer, 2), isFalse);
      expect(_controller.start(tournament, 1, freeMatch, 1), isFalse);
      expect(_controller.start(tournament, 1, freeMatch, 2), isTrue);
    },
  );
}
