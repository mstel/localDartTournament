import 'package:dart_tournament_manager/features/tournaments/application/group_assignment_preservation.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

List<TournamentPlayer> _players() => [
  TournamentPlayer.generated(1),
  TournamentPlayer.generated(2),
  TournamentPlayer.generated(3),
  TournamentPlayer.generated(4),
];

TournamentStage _stage(String mode, List<int?> slotOrder) => TournamentStage(
  name: 'Gruppenphase',
  type: 'groups',
  groupSizes: const [2, 2],
  groupAssignmentMode: mode,
  groupSlotOrder: slotOrder,
);

CreatedTournament _existingTournament({
  required String mode,
  required List<int?> slotOrder,
}) {
  final players = _players();
  final assigned = mode == 'manual' && slotOrder.isNotEmpty;
  final ordered = assigned
      ? [players[1], players[0], players[3], players[2]]
      : players;
  return CreatedTournament(
    name: 'Zuweisungstest',
    players: players,
    stages: [_stage(mode, slotOrder)],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          for (var index = 0; index < 2; index++)
            TournamentGroup(
              name: 'Gruppe ${index + 1}',
              playType: 'round_robin',
              players: ordered.sublist(index * 2, index * 2 + 2),
              matches: const [],
            ),
        ],
      ),
    ],
  );
}

void main() {
  test('pending manual assignment is not reconstructed from run groups', () {
    final players = _players();
    final result = preserveExistingGroupAssignment(
      existing: _existingTournament(mode: 'manual', slotOrder: const []),
      stages: [_stage('manual', const [])],
      players: players,
    );

    expect(result.single.groupAssignmentMode, 'manual');
    expect(result.single.groupSlotOrder, isEmpty);
    expect(result.single.hasPendingManualGroupAssignment, isTrue);
  });

  test('an already completed manual assignment is preserved', () {
    final result = preserveExistingGroupAssignment(
      existing: _existingTournament(mode: 'manual', slotOrder: [2, 1, 4, 3]),
      stages: [_stage('manual', const [])],
      players: _players(),
    );

    expect(result.single.groupSlotOrder, [2, 1, 4, 3]);
    expect(result.single.hasPendingManualGroupAssignment, isFalse);
  });

  test('changing the assignment method drops the old slot order', () {
    final result = preserveExistingGroupAssignment(
      existing: _existingTournament(mode: 'manual', slotOrder: [2, 1, 4, 3]),
      stages: [_stage('strengthLevels', const [])],
      players: _players(),
    );

    expect(result.single.groupAssignmentMode, 'strengthLevels');
    expect(result.single.groupSlotOrder, isEmpty);
  });

  test('a newly edited manual assignment is not overwritten', () {
    final result = preserveExistingGroupAssignment(
      existing: _existingTournament(mode: 'manual', slotOrder: const []),
      stages: [
        _stage('manual', [3, 4, 1, 2]),
      ],
      players: _players(),
    );

    expect(result.single.groupSlotOrder, [3, 4, 1, 2]);
  });
}
