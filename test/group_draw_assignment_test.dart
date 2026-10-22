import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_draw_assignment.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

      final ordered = GroupDrawAssignment.orderPlayers(
        players: players,
        slotOrder: restoredStage.groupSlotOrder,
        participantCount: restoredStage.groupSizes.fold(
          0,
          (total, size) => total + size,
        ),
      );
      final groups = GroupDrawAssignment.partition(
        ordered,
        restoredStage.groupSizes,
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
}
