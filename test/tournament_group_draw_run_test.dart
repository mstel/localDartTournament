import 'dart:convert';
import 'dart:io';

import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/engines/group_draw_assignment.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'accepted group draw survives the production storage roundtrip',
    () async {
      final tournament = _tournament()..plannedMinutes = 60;
      final directory = await Directory.systemTemp.createTemp(
        'group-draw-storage-test-',
      );
      try {
        final storage = TournamentStorage(
          file: File('${directory.path}/tournaments.json'),
        );
        await storage.saveTournament(tournament);

        const drawnSeeds = [2, 4, 1, 8, 3, 5, 7, 6];
        final stage = tournament.stages.single.copyWith(
          groupSlotOrder: drawnSeeds,
          groupDrawCompleted: true,
        );
        tournament.stages[0] = stage;
        final assignments = GroupDrawAssignment.partitionDraw(
          items: tournament.players,
          slotOrder: stage.groupSlotOrder,
          groupSizes: stage.groupSizes,
        );
        tournament.runStages[0] = GroupTournamentRunStage(
          name: stage.name,
          groupPlayType: stage.groupPlayType,
          qualificationPlan: null,
          tieBreakers: stage.groupTieBreakers,
          groups: [
            for (
              var groupIndex = 0;
              groupIndex < assignments.length;
              groupIndex++
            )
              TournamentGroup(
                name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
                playType: stage.groupPlayType,
                players: assignments[groupIndex],
                matches: const [],
              ),
          ],
        );

        await TournamentRunController(storage: storage).saveProgress(
          tournament: tournament,
          activeStageIndex: 0,
          completedStageIndexes: const {},
        );

        final restored = (await storage.loadTournaments()).single;
        expect(restored.stages.single.groupDrawCompleted, isTrue);
        expect(restored.stages.single.groupSlotOrder, drawnSeeds);
        expect(
          (restored.runStages.single as GroupTournamentRunStage).groups
              .map(
                (group) => group.players.map((player) => player.name).toList(),
              )
              .toList(),
          [
            ['Spieler 2', 'Spieler 4', 'Spieler 1', 'Spieler 8'],
            ['Spieler 3', 'Spieler 5', 'Spieler 7', 'Spieler 6'],
          ],
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'accepted wheel draw controls group settings and is not shown again',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _tournament()..plannedMinutes = 60;
      final storage = _MemoryTournamentStorage();
      final controller = _RecordingRunController(storage);

      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: tournament,
            runController: controller,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Auslosung: Gruppenphase'), findsOneWidget);

      for (
        var drawIndex = 0;
        drawIndex < tournament.players.length;
        drawIndex++
      ) {
        final buttonLabel = drawIndex == 0 ? 'Rad drehen' : 'Nächsten ziehen';
        await tester.tap(find.text(buttonLabel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 3600));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('${drawIndex + 1} von 8 gezogen'), findsOneWidget);
      }

      final drawnNames = tester
          .widgetList<Chip>(find.byType(Chip))
          .map((chip) => (chip.label as Text).data!)
          .toList();
      expect(drawnNames, hasLength(8));
      await tester.tap(find.text('Auslosung übernehmen'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

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

      expect(storage.savedTournament, isNotNull);
      final restored = CreatedTournament.fromJson(storage.savedTournament!);
      expect(restored.stages.single.groupDrawCompleted, isTrue);
      expect(
        (restored.runStages.single as GroupTournamentRunStage).groups
            .map((group) => group.players.map((player) => player.name).toList())
            .toList(),
        [drawnNames.take(4).toList(), drawnNames.skip(4).toList()],
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: restored,
            runController: controller,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Auslosung: Gruppenphase'), findsNothing);
      expect(
        (restored.runStages.single as GroupTournamentRunStage).groups
            .map((group) => group.players.map((player) => player.name).toList())
            .toList(),
        [drawnNames.take(4).toList(), drawnNames.skip(4).toList()],
      );

      await tester.tap(find.text('Einstellungen'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Gruppen verwalten'));
      await tester.tap(find.text('Bearbeiten'));
      await tester.pump(const Duration(milliseconds: 300));
      final groupPlayers = tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ListTile),
            ),
          )
          .map((tile) => (tile.title as Text).data!)
          .toList();
      expect(groupPlayers, drawnNames);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'saved slot order repairs a stale draw flag without reopening the wheel',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _tournament()..plannedMinutes = 60;
      const drawnSeeds = [2, 4, 1, 8, 3, 5, 7, 6];
      tournament.stages[0] = tournament.stages.single.copyWith(
        groupSlotOrder: drawnSeeds,
        groupDrawCompleted: false,
      );
      final storage = _MemoryTournamentStorage();
      final controller = _RecordingRunController(storage);

      Future<void> openTournament(CreatedTournament value) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TournamentRunPage(
              tournament: value,
              runController: controller,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await openTournament(tournament);

      expect(find.text('Auslosung: Gruppenphase'), findsNothing);
      expect(tournament.stages.single.groupDrawCompleted, isTrue);
      final expectedGroups = [
        ['Spieler 2', 'Spieler 4', 'Spieler 1', 'Spieler 8'],
        ['Spieler 3', 'Spieler 5', 'Spieler 7', 'Spieler 6'],
      ];
      List<List<String>> groupNames(CreatedTournament value) =>
          (value.runStages.single as GroupTournamentRunStage).groups
              .map(
                (group) => group.players.map((player) => player.name).toList(),
              )
              .toList();
      expect(groupNames(tournament), expectedGroups);
      expect(storage.savedTournament, isNotNull);

      final restored = CreatedTournament.fromJson(storage.savedTournament!);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await openTournament(restored);

      expect(find.text('Auslosung: Gruppenphase'), findsNothing);
      expect(groupNames(restored), expectedGroups);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
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
  Map<String, dynamic>? savedTournament;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    savedTournament = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(tournament.toJson())) as Map,
    );
  }
}

class _RecordingRunController extends TournamentRunController {
  _RecordingRunController(this.storage);

  final _MemoryTournamentStorage storage;

  @override
  Future<void> saveProgress({
    required CreatedTournament tournament,
    required int activeStageIndex,
    required Set<int> completedStageIndexes,
  }) async {
    tournament.activeStageIndex = activeStageIndex;
    tournament.completedStageIndexes
      ..clear()
      ..addAll(completedStageIndexes);
    await storage.saveTournament(tournament);
  }
}
