import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/team_participant_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catalog assignment is offered for planner entrants', (
    tester,
  ) async {
    var assignedIndex = -1;
    var renamedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamParticipantList(
            players: [TournamentPlayer.generated(1)],
            onRename: (index) => renamedIndex = index,
            onAssignProfile: (index) => assignedIndex = index,
            useCatalogAssignment: true,
            onRemove: (_) {},
            onMerge: (_, _) {},
            onSplit: (_) {},
          ),
        ),
      ),
    );

    final assignment = find.byTooltip('Spieler aus Katalog zuweisen');
    expect(assignment, findsOneWidget);
    await tester.tap(assignment);
    expect(assignedIndex, 0);
    expect(renamedIndex, -1);
  });

  testWidgets('custom-player action remains a rename when not planner-created', (
    tester,
  ) async {
    var assignedIndex = -1;
    var renamedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamParticipantList(
            players: [TournamentPlayer.generated(1)],
            onRename: (index) => renamedIndex = index,
            onAssignProfile: (index) => assignedIndex = index,
            onRemove: (_) {},
            onMerge: (_, _) {},
            onSplit: (_) {},
          ),
        ),
      ),
    );

    final rename = find.byTooltip('Umbenennen');
    expect(rename, findsOneWidget);
    await tester.tap(rename);
    expect(renamedIndex, 0);
    expect(assignedIndex, -1);
  });
}
