import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_draw_assignment.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves every drawn slot when splitting the draw into groups', () {
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index).copyWith(name: 'Spieler $index'),
    ];
    const drawnSeeds = [2, 4, 1, 8, 3, 5, 7, 6];

    final groups = GroupDrawAssignment.partitionDraw(
      items: players,
      slotOrder: drawnSeeds,
      groupSizes: const [4, 4],
    );

    expect(groups.map((group) => group.map((player) => player.name).toList()), [
      ['Spieler 2', 'Spieler 4', 'Spieler 1', 'Spieler 8'],
      ['Spieler 3', 'Spieler 5', 'Spieler 7', 'Spieler 6'],
    ]);
  });

  test('rejects a stale draw instead of silently restoring default groups', () {
    final players = [
      for (var index = 1; index <= 8; index++)
        TournamentPlayer.generated(index),
    ];

    expect(
      () => GroupDrawAssignment.partitionDraw(
        items: players,
        slotOrder: const [2, 3, 5, 7],
        groupSizes: const [4, 4],
      ),
      throwsFormatException,
    );
  });

  test('draw completion survives tournament stage serialization', () {
    final stage = TournamentStage(
      name: 'Gruppen',
      type: 'groups',
      groupDrawOnStart: true,
      groupSlotOrder: const [2, 3, 5, 7, 1, 4, 6, 8],
      groupDrawCompleted: true,
    );

    final restored = TournamentStage.fromJson(stage.toJson());

    expect(restored.groupDrawCompleted, isTrue);
    expect(restored.groupSlotOrder, [2, 3, 5, 7, 1, 4, 6, 8]);
  });

  test(
    'persisted draw order partitions players using configured group sizes',
    () {
      final players = [
        for (var index = 1; index <= 5; index++)
          TournamentPlayer.generated(index).copyWith(name: 'Player $index'),
      ];
      final stage = TournamentStage(
        name: 'Gruppenphase',
        type: 'groups',
        groupSizes: const [3, 2],
        groupSlotOrder: const [4, 1, 5, 2, 3],
      );
      final restoredStage = TournamentStage.fromJson(stage.toJson());

      final groups = GroupDrawAssignment.partitionDraw(
        items: players,
        slotOrder: restoredStage.groupSlotOrder,
        groupSizes: restoredStage.groupSizes,
      );
      final wheelPreviewGroups = GroupDrawAssignment.partition([
        for (final seed in restoredStage.groupSlotOrder) players[seed! - 1],
      ], restoredStage.groupSizes);

      expect(groups.map((group) => group.length), [3, 2]);
      expect(wheelPreviewGroups, groups);
      expect(
        groups.map((group) => group.map((player) => player.name).toList()),
        [
          ['Player 4', 'Player 1', 'Player 5'],
          ['Player 2', 'Player 3'],
        ],
      );
    },
  );

  test('draw preview reveals only players already drawn', () {
    final players = [
      'Bernd',
      'Burkhard',
      'Christian',
      'Daniel',
      'Dietmar',
      'Friedel',
      'Jan',
      'Johannes',
    ];

    expect(
      GroupDrawAssignment.previewPartitionDraw(
        items: players,
        drawnSeeds: const [],
        groupSizes: const [4, 4],
      ),
      [
        [null, null, null, null],
        [null, null, null, null],
      ],
    );
    expect(
      GroupDrawAssignment.previewPartitionDraw(
        items: players,
        drawnSeeds: const [8, 1, 7, 5],
        groupSizes: const [4, 4],
      ),
      [
        ['Johannes', 'Bernd', 'Jan', 'Dietmar'],
        [null, null, null, null],
      ],
    );
    expect(
      GroupDrawAssignment.partitionDraw(
        items: players,
        slotOrder: const [8, 1, 7, 5, 6, 4, 2, 3],
        groupSizes: const [4, 4],
      ),
      [
        ['Johannes', 'Bernd', 'Jan', 'Dietmar'],
        ['Friedel', 'Daniel', 'Burkhard', 'Christian'],
      ],
    );
  });
}
