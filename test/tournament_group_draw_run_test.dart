import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'accepted wheel draw controls group settings and is not shown again',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _tournament();
      final storage = _MemoryTournamentStorage();
      final controller = TournamentRunController(storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: tournament,
            runController: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Auslosung: Gruppenphase'), findsOneWidget);

      for (
        var drawIndex = 0;
        drawIndex < tournament.players.length;
        drawIndex++
      ) {
        final buttonLabel = drawIndex == 0 ? 'Rad drehen' : 'Nächsten ziehen';
        await tester.tap(find.text(buttonLabel));
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }

      final drawnNames = tester
          .widgetList<Chip>(find.byType(Chip))
          .map((chip) => (chip.label as Text).data!)
          .toList();
      expect(drawnNames, hasLength(8));
      await tester.tap(find.text('Auslosung übernehmen'));
      await tester.pumpAndSettle();

      final groups =
          (tournament.runStages.single as GroupTournamentRunStage).groups;
      expect(
        groups[0].players.map((player) => player.name),
        drawnNames.take(4),
      );
      expect(
        groups[1].players.map((player) => player.name),
        drawnNames.skip(4),
      );
      expect(tournament.stages.single.groupDrawCompleted, isTrue);

      final restored = CreatedTournament.fromJson(
        Map<String, dynamic>.from(tournament.toJson()),
      );
      expect(restored.stages.single.groupDrawCompleted, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: restored,
            runController: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Auslosung: Gruppenphase'), findsNothing);

      await tester.tap(find.text('Einstellungen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gruppen verwalten'));
      await tester.tap(find.text('Bearbeiten'));
      await tester.pumpAndSettle();
      for (final name in drawnNames) {
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

CreatedTournament _tournament() {
  final players = [
    for (var index = 1; index <= 8; index++) TournamentPlayer.generated(index),
  ];
  List<GroupMatch> matchesFor(List<TournamentPlayer> members) => [
    for (var home = 0; home < members.length; home++)
      for (var away = home + 1; away < members.length; away++)
        GroupMatch(
          homePlayer: members[home],
          awayPlayer: members[away],
          round: 1,
        ),
  ];
  final stage = TournamentStage(
    name: 'Gruppenphase',
    type: 'groups',
    groupSizes: const [4, 4],
    groupDrawOnStart: true,
  );
  return CreatedTournament(
    name: 'Auslosungstest',
    players: players,
    stages: [stage],
    runStages: [
      GroupTournamentRunStage(
        name: stage.name,
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          for (var groupIndex = 0; groupIndex < 2; groupIndex++)
            TournamentGroup(
              name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
              playType: 'round_robin',
              players: players.sublist(groupIndex * 4, groupIndex * 4 + 4),
              matches: matchesFor(
                players.sublist(groupIndex * 4, groupIndex * 4 + 4),
              ),
            ),
        ],
      ),
    ],
  );
}

class _MemoryTournamentStorage extends TournamentStorage {
  @override
  Future<void> saveTournament(CreatedTournament tournament) async {}
}
