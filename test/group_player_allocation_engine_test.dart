import 'dart:math';

import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_player_allocation_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final players = [
    for (var index = 0; index < 10; index++)
      TournamentPlayer(
        name: 'Spieler $index',
        profileId: 'player-$index',
        isGenerated: false,
      ),
  ];
  final ratings = {
    for (var index = 0; index < 10; index++)
      'player-$index': 1500 - index * 100,
  };
  const engine = GroupPlayerAllocationEngine();

  test('strength levels put the strongest entrants in the first group', () {
    final allocated = engine.allocate(
      players: players,
      groupSizes: const [5, 5],
      mode: GroupPlayerAllocationMode.strengthLevels,
      ratings: ratings,
    );

    expect(allocated.take(5).map((player) => player.profileId), [
      'player-0',
      'player-1',
      'player-2',
      'player-3',
      'player-4',
    ]);
    expect(allocated.skip(5).map((player) => player.profileId), [
      'player-5',
      'player-6',
      'player-7',
      'player-8',
      'player-9',
    ]);
  });

  test('balanced allocation cycles strongest players across groups', () {
    final allocated = engine.allocate(
      players: players.take(6).toList(),
      groupSizes: const [2, 2, 2],
      mode: GroupPlayerAllocationMode.balanced,
      ratings: ratings,
    );

    expect(allocated.take(2).map((player) => player.profileId), [
      'player-0',
      'player-3',
    ]);
    expect(allocated.skip(2).take(2).map((player) => player.profileId), [
      'player-1',
      'player-4',
    ]);
    expect(allocated.skip(4).map((player) => player.profileId), [
      'player-2',
      'player-5',
    ]);
  });

  test('random allocation preserves entrants and enforces group sizes', () {
    final allocated = engine.allocate(
      players: players,
      groupSizes: const [3, 3, 4],
      mode: GroupPlayerAllocationMode.random,
      random: Random(17),
    );

    expect(allocated, hasLength(10));
    expect(allocated.map((player) => player.profileId).toSet(), {
      for (var index = 0; index < 10; index++) 'player-$index',
    });
  });

  test('rejects group sizes that do not cover every entrant', () {
    expect(
      () => engine.allocate(
        players: players,
        groupSizes: const [4, 4],
        mode: GroupPlayerAllocationMode.balanced,
      ),
      throwsArgumentError,
    );
  });
}
