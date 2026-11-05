import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

CreatedTournament fixture({int boards = 2}) {
  final players = [for (var i = 1; i <= 6; i++) TournamentPlayer.generated(i)];
  return CreatedTournament(
    name: 'Test',
    players: players,
    stages: [],
    boardCount: boards,
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
            players: players,
            matches: [
              for (var a = 0; a < players.length; a++)
                for (var b = a + 1; b < players.length; b++)
                  GroupMatch(
                    homePlayer: players[a],
                    awayPlayer: players[b],
                    round: 1,
                  ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  const controller = OrderOfPlayController();
  test(
    'participant suggestion excludes busy opponents and occupied boards',
    () {
      final t = fixture();
      final first = controller.suggestForPlayer(t, 0, t.players.first)!;
      expect(controller.start(t, 0, first.entry.match, first.board), true);
      expect(controller.suggestForPlayer(t, 0, t.players.first), isNull);
      final idle = t.players.firstWhere(
        (p) => !first.entry.players.contains(p.name),
      );
      final next = controller.suggestForPlayer(t, 0, idle)!;
      expect(next.board, isNot(first.board));
      expect(next.entry.players.intersection(first.entry.players), isEmpty);
      expect(controller.start(t, 0, next.entry.match, next.board), true);
      expect(controller.suggestForPlayer(t, 0, t.players.last), isNull);
    },
  );
  test('all matches scheduled once with no board or player conflicts', () {
    for (final boards in [1, 2, 3, 4]) {
      final tournament = fixture(boards: boards);
      final schedule = controller.plan(tournament, 0);
      expect(schedule.planned.length, 15);
      expect(schedule.planned.map((e) => e.entry.match).toSet().length, 15);
      for (final block in schedule.planned.map((e) => e.block).toSet()) {
        final wave = schedule.planned.where((e) => e.block == block).toList();
        expect(wave.length, lessThanOrEqualTo(boards));
        expect(wave.map((e) => e.board).toSet().length, wave.length);
        expect(
          wave.expand((e) => e.entry.players).toSet().length,
          wave.length * 2,
        );
      }
    }
  });
  test('one group can use several boards in the same play block', () {
    final schedule = controller.plan(fixture(boards: 4), 0);
    final firstBlock = schedule.planned.where((entry) => entry.block == 0);

    expect(firstBlock.length, greaterThan(1));
    expect(firstBlock.map((entry) => entry.board).toSet(), {1, 2, 3});
    expect(firstBlock.map((entry) => entry.entry.origin).toSet(), hasLength(1));
  });
  test(
    'group board preferences use assigned boards and release idle boards',
    () {
      final players = [
        for (var index = 1; index <= 8; index++)
          TournamentPlayer.generated(index),
      ];
      List<GroupMatch> matches(List<TournamentPlayer> group) => [
        for (var home = 0; home < group.length; home++)
          for (var away = home + 1; away < group.length; away++)
            GroupMatch(
              homePlayer: group[home],
              awayPlayer: group[away],
              round: 1,
            ),
      ];
      CreatedTournament tournament(List<GroupMatch> aMatches) =>
          CreatedTournament(
            name: 'Board-Zuordnung',
            players: players,
            stages: [],
            boardCount: 2,
            groupBoardAssignments: const {
              '0:A': [2],
              '0:B': [1],
            },
            runStages: [
              GroupTournamentRunStage(
                name: 'Gruppenphase',
                groupPlayType: 'round_robin',
                qualificationPlan: null,
                tieBreakers: defaultGroupTieBreakers,
                groups: [
                  TournamentGroup(
                    name: 'A',
                    playType: 'round_robin',
                    players: players.take(4).toList(),
                    matches: aMatches,
                  ),
                  TournamentGroup(
                    name: 'B',
                    playType: 'round_robin',
                    players: players.skip(4).toList(),
                    matches: matches(players.skip(4).toList()),
                  ),
                ],
              ),
            ],
          );

      final aMatches = matches(players.take(4).toList());
      final configured = tournament(aMatches);
      final restored = CreatedTournament.fromJson(configured.toJson());
      expect(restored.groupBoardAssignments, {
        '0:A': [2],
        '0:B': [1],
      });
      final assigned = controller
          .plan(configured, 0)
          .planned
          .where((entry) => entry.block == 0)
          .toList();
      expect(
        {
          for (final entry in assigned)
            entry.entry.groupKey!.endsWith(':A')
                ? entry.board == 2
                : entry.board == 1,
        },
        {true},
      );
      expect(assigned.map((entry) => entry.entry.groupKey).toSet(), {
        '0:A',
        '0:B',
      });
      expect(
        controller.suggestForPlayer(configured, 0, players.first)?.board,
        2,
      );

      for (final match in aMatches) {
        match
          ..homeLegs = 2
          ..awayLegs = 0;
      }
      final catchUp = controller.plan(tournament(aMatches), 0).planned;
      expect(
        catchUp.any(
          (entry) => entry.entry.groupKey == '0:B' && entry.board == 2,
        ),
        isTrue,
      );
    },
  );
  test('queue prefers a two-block rest before reusing a recent player', () {
    final players = [
      TournamentPlayer.generated(101),
      TournamentPlayer.generated(102),
      TournamentPlayer.generated(103),
      TournamentPlayer.generated(104),
    ];
    final recentlyPlayed = GroupMatch(
      homePlayer: players[0],
      awayPlayer: players[1],
      round: 1,
      homeLegs: 2,
      awayLegs: 1,
    );
    final reuseRecentPlayer = GroupMatch(
      homePlayer: players[0],
      awayPlayer: players[2],
      round: 2,
    );
    final playRestedPair = GroupMatch(
      homePlayer: players[2],
      awayPlayer: players[3],
      round: 2,
    );
    final pastEntry = PlayEntry(recentlyPlayed, 0, 'Gruppen');
    final reuseEntry = PlayEntry(reuseRecentPlayer, 0, 'Gruppen');
    final restedEntry = PlayEntry(playRestedPair, 0, 'Gruppen');

    final schedule = const BoardSchedulingEngine().schedule(
      all: [pastEntry, reuseEntry, restedEntry],
      ready: [reuseEntry, restedEntry],
      finished: [pastEntry],
      boardCount: 1,
    );

    expect(BoardSchedulingEngine.preferredPlayerRestBlocks, 2);
    expect(schedule.first.entry, same(restedEntry));
  });
  test(
    'starting a later match replans and prevents concurrent player/board use',
    () {
      final tournament = fixture();
      final original = controller.plan(tournament, 0);
      final pulled = original.planned.last.entry.match;
      expect(controller.start(tournament, 0, pulled, 1), isTrue);
      final updated = controller.plan(tournament, 0);
      expect(updated.running.single.match, same(pulled));
      final busy = updated.running.single.players;
      for (final next in updated.planned.where((e) => e.block == 0)) {
        expect(next.board, 2);
        expect(next.entry.players.intersection(busy), isEmpty);
      }
      expect(
        controller.start(tournament, 0, updated.planned.first.entry.match, 1),
        isFalse,
      );
      pulled.homeLegs = 2;
      pulled.awayLegs = 0;
      controller.resultRecorded(pulled);
      final after = controller.plan(tournament, 0);
      expect(after.running, isEmpty);
      expect(after.finished.single.match, same(pulled));
      expect(after.planned.length, 14);
      expect(after.planned.first.entry.players.intersection(busy), isEmpty);
    },
  );
  test(
    'future stages and unresolved pairings wait; metadata survives reload',
    () {
      final tournament = fixture();
      tournament.runStages.add(
        KnockoutTournamentRunStage(
          name: 'Finale',
          rounds: [
            [GroupMatch(round: 1)],
          ],
        ),
      );
      final match = controller.plan(tournament, 0).planned.first.entry.match;
      controller.start(tournament, 0, match, 2);
      final restored = CreatedTournament.fromJson(tournament.toJson());
      expect(restored.boardCount, 2);
      final schedule = controller.plan(restored, 0);
      expect(schedule.running.single.match.boardNumber, 2);
      expect(schedule.running.single.match.startedAt, isNotNull);
      expect(schedule.waiting.length, 1);
      final legacy = tournament.toJson()..remove('boardCount');
      expect(CreatedTournament.fromJson(legacy).boardCount, 1);
    },
  );
  test('resetting a running match frees its board without adding a result', () {
    final tournament = fixture();
    final match = controller.plan(tournament, 0).planned.first.entry.match;
    expect(controller.start(tournament, 0, match, 1), isTrue);
    match.homeLegs = 2;

    expect(controller.resetRunningMatch(tournament, 0, match), isTrue);
    expect(match.boardNumber, isNull);
    expect(match.startedAt, isNull);
    expect(match.startedPlayers, isNull);
    expect(match.finishedAt, isNull);
    expect(match.homeLegs, isNull);
    expect(match.hasResult, isFalse);
    expect(controller.plan(tournament, 0).running, isEmpty);
    expect(
      controller
          .plan(tournament, 0)
          .planned
          .any((assignment) => assignment.entry.match == match),
      isTrue,
    );
  });
  test('removing a result releases stale scheduling metadata', () {
    final match = GroupMatch(
      round: 1,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      boardNumber: 1,
    );
    controller.resultRecorded(match);
    expect(match.startedAt, isNull);
    expect(match.finishedAt, isNull);
    expect(match.boardNumber, isNull);
  });
  test('early manually entered result replans and survives reopening', () {
    final tournament = fixture();
    final pulled = controller.plan(tournament, 0).planned.last.entry;
    pulled.match.homeLegs = 2;
    pulled.match.awayLegs = 1;
    controller.resultRecorded(pulled.match);
    final restored = CreatedTournament.fromJson(tournament.toJson());
    final schedule = controller.plan(restored, 0);
    expect(schedule.finished.length, 1);
    expect(schedule.planned.length, 14);
    expect(
      schedule.planned.first.entry.players.intersection(pulled.players),
      isEmpty,
    );
    final finished = schedule.finished.single.match;
    finished.homeLegs = null;
    finished.awayLegs = null;
    controller.resultRecorded(finished);
    expect(controller.plan(restored, 0).planned.length, 15);
    expect(controller.plan(restored, 0).finished, isEmpty);
  });
}
