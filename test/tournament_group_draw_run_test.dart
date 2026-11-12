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
  testWidgets(
    'reopening and resetting a late stage stays responsive in a large copied tournament',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final players = [
        for (var index = 1; index <= 8; index++)
          TournamentPlayer.generated(index).copyWith(name: 'Teilnehmer $index'),
      ];
      const historyStageCount = 40;
      final tournament = CreatedTournament(
        name: 'Kopiertes Turnier',
        players: players,
        stages: [
          for (var stageIndex = 0; stageIndex < historyStageCount; stageIndex++)
            TournamentStage(
              name: 'Phase ${stageIndex + 1}',
              type: 'groups',
              groupSizes: const [8],
            ),
        ],
        runStages: [
          for (var stageIndex = 0; stageIndex < historyStageCount; stageIndex++)
            GroupTournamentRunStage(
              name: 'Phase ${stageIndex + 1}',
              groupPlayType: 'round_robin',
              qualificationPlan: null,
              tieBreakers: defaultGroupTieBreakers,
              groups: [
                TournamentGroup(
                  name: 'Gruppe A',
                  playType: 'round_robin',
                  players: players,
                  matches: [
                    for (
                      var homeIndex = 0;
                      homeIndex < players.length;
                      homeIndex++
                    )
                      for (
                        var awayIndex = homeIndex + 1;
                        awayIndex < players.length;
                        awayIndex++
                      )
                        GroupMatch(
                          homePlayer: players[homeIndex],
                          awayPlayer: players[awayIndex],
                          round: homeIndex + 1,
                          homeLegs: stageIndex == historyStageCount - 1
                              ? null
                              : 3,
                          awayLegs: stageIndex == historyStageCount - 1
                              ? null
                              : 0,
                        ),
                  ],
                ),
              ],
            ),
        ],
        directorModeEnabled: true,
        boardCount: 4,
        activeStageIndex: historyStageCount - 1,
        completedStageIndexes: {
          for (var index = 0; index < historyStageCount - 1; index++) index,
        },
      );
      final originalEarlierStageResults = [
        for (final match
            in (tournament.runStages.first as GroupTournamentRunStage)
                .groups
                .single
                .matches)
          (match.homeLegs, match.awayLegs),
      ];
      final storage = _MemoryTournamentStorage();

      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: tournament,
            runController: _RecordingRunController(storage),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vorherige Phase wieder öffnen'), findsOneWidget);

      final reopenTimer = Stopwatch()..start();
      final reopen = find.text('Vorherige Phase wieder öffnen');
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(reopen);
      await tester.pumpAndSettle();
      reopenTimer.stop();
      expect(tournament.activeStageIndex, historyStageCount - 2);
      expect(
        reopenTimer.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'Opening a previous stage should complete promptly.',
      );

      await tester.ensureVisible(find.text('Phase zurücksetzen'));
      await tester.tap(find.text('Phase zurücksetzen'));
      await tester.pumpAndSettle();
      final resetTimer = Stopwatch()..start();
      await tester.tap(find.text('Zurücksetzen'));
      await tester.pumpAndSettle();
      resetTimer.stop();
      final resetMatches =
          (tournament.runStages[historyStageCount - 2]
                  as GroupTournamentRunStage)
              .groups
              .single
              .matches;
      expect(resetMatches.every((match) => !match.hasResult), isTrue);
      expect(
        resetTimer.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: 'Resetting a stage should complete promptly.',
      );
      expect([
        for (final match
            in (tournament.runStages.first as GroupTournamentRunStage)
                .groups
                .single
                .matches)
          (match.homeLegs, match.awayLegs),
      ], originalEarlierStageResults);
      expect(tester.takeException(), isNull);
      debugPrint(
        '40-stage copy: reopen ${reopenTimer.elapsed.inMilliseconds} ms, '
        'reset ${resetTimer.elapsed.inMilliseconds} ms.',
      );
    },
  );

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
            ['Teilnehmer 2', 'Teilnehmer 4', 'Teilnehmer 1', 'Teilnehmer 8'],
            ['Teilnehmer 3', 'Teilnehmer 5', 'Teilnehmer 7', 'Teilnehmer 6'],
          ],
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'participant adjustment opens the planner without changing the saved draft',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = _tournament()
        ..plannedMinutes = 180
        ..boardCount = 4;
      tournament.stages[0] = TournamentStage.fromJson({
        ...tournament.stages.single.toJson(),
        'groupDrawOnStart': false,
      });
      final storage = _MemoryTournamentStorage();

      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: tournament,
            runController: _RecordingRunController(storage),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final savedBefore = storage.savedTournament;
      expect(savedBefore, isNotNull);

      await tester.tap(find.text('Einstellungen'));
      await tester.pumpAndSettle();
      await _scrollToText(tester, 'Teilnehmer (8)');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teilnehmer (8)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Teilnehmer hinzufügen'));
      await tester.tap(find.text('Teilnehmer hinzufügen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neuen Namen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.byType(TextField),
        ),
        'Neue Person',
      );
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turnierformat anpassen'));
      await tester.pumpAndSettle();

      expect(find.text('Passende Turnierform finden'), findsOneWidget);
      final fieldValues = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller?.text)
          .toList();
      expect(fieldValues, containsAll(['9', '4', '3']));
      await tester.ensureVisible(find.text('Turnierformen'));
      await tester.tap(find.text('Turnierformen'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('planner-mode-groups:round_robin')),
            )
            .value,
        isTrue,
      );
      expect(tournament.players, hasLength(8));
      expect(tournament.stages.single.groupSizes, [4, 4]);
      expect(storage.savedTournament, equals(savedBefore));

      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('start draw assigns groups immediately without showing a wheel', (
    tester,
  ) async {
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
    await tester.pumpAndSettle();
    expect(find.text('Auslosung: Gruppenphase'), findsNothing);
    expect(find.text('Rad drehen'), findsNothing);
    expect(find.text('Auslosung übernehmen'), findsNothing);
    expect(tournament.stages.single.groupDrawCompleted, isTrue);
    final assignedPlayers =
        (tournament.runStages.single as GroupTournamentRunStage).groups
            .expand((group) => group.players)
            .map((player) => player.name)
            .toList();
    expect(
      assignedPlayers.toSet(),
      tournament.players.map((player) => player.name).toSet(),
    );
    expect(assignedPlayers, hasLength(tournament.players.length));
    final groups =
        (tournament.runStages.single as GroupTournamentRunStage).groups;

    expect(storage.savedTournament, isNotNull);
    final restored = CreatedTournament.fromJson(storage.savedTournament!);
    expect(restored.stages.single.groupDrawCompleted, isTrue);
    expect(
      (restored.runStages.single as GroupTournamentRunStage).groups
          .map((group) => group.players.map((player) => player.name).toList())
          .toList(),
      groups
          .map((group) => group.players.map((player) => player.name).toList())
          .toList(),
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
    await tester.pumpAndSettle();
    expect(find.text('Auslosung: Gruppenphase'), findsNothing);
    expect(
      (restored.runStages.single as GroupTournamentRunStage).groups
          .map((group) => group.players.map((player) => player.name).toList())
          .toList(),
      groups
          .map((group) => group.players.map((player) => player.name).toList())
          .toList(),
    );

    await tester.tap(find.text('Einstellungen'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearbeiten'));
    await tester.pump(const Duration(milliseconds: 300));
    final groupDialog = find.byType(Dialog);
    for (final player in tournament.players) {
      expect(
        find.descendant(of: groupDialog, matching: find.text(player.name)),
        findsWidgets,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

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
        ['Teilnehmer 2', 'Teilnehmer 4', 'Teilnehmer 1', 'Teilnehmer 8'],
        ['Teilnehmer 3', 'Teilnehmer 5', 'Teilnehmer 7', 'Teilnehmer 6'],
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

  testWidgets('players can be reseeded before a knockout starts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = _knockoutTournament();
    final storage = _MemoryTournamentStorage();

    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          tournament: tournament,
          runController: _RecordingRunController(storage),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await _scrollToText(tester, 'Teilnehmer (4)');
    await tester.tap(find.text('Teilnehmer (4)'));
    await tester.pumpAndSettle();

    final reorderableList = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderableList.onReorderItem!(0, 1);
    await tester.pumpAndSettle();

    expect(tournament.players.map((player) => player.name), [
      'Teilnehmer 2',
      'Teilnehmer 1',
      'Teilnehmer 3',
      'Teilnehmer 4',
    ]);
    final runStage = tournament.runStages.single as KnockoutTournamentRunStage;
    expect(runStage.rounds.first.map((match) => match.homePlayer?.name), [
      'Teilnehmer 2',
      'Teilnehmer 1',
    ]);
    expect(storage.savedTournament, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('player reseeding is hidden after a knockout result exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          tournament: _knockoutTournament(withResult: true),
          runController: _RecordingRunController(_MemoryTournamentStorage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await _scrollToText(tester, 'Teilnehmer (4)');
    await tester.tap(find.text('Teilnehmer (4)'));
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableListView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('supports reseeding all group-free knockout modes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final type in [
      'single_knockout',
      'double_knockout',
      'triple_knockout',
      'kratzer',
    ]) {
      final tournament = _knockoutTournament(type: type, stageCount: 2);
      await tester.pumpWidget(
        MaterialApp(
          home: TournamentRunPage(
            tournament: tournament,
            runController: _RecordingRunController(_MemoryTournamentStorage()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Einstellungen'));
      await tester.pumpAndSettle();
      await _scrollToText(tester, 'Teilnehmer (4)');
      await tester.tap(find.text('Teilnehmer (4)'));
      await tester.pumpAndSettle();

      expect(find.byType(ReorderableListView), findsOneWidget, reason: type);
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 1);
      await tester.pumpAndSettle();

      expect(tournament.players.first.name, 'Teilnehmer 2', reason: type);
      expect(
        (tournament.runStages.first as KnockoutTournamentRunStage).isKratzer,
        type == 'kratzer',
        reason: type,
      );
      expect(tester.takeException(), isNull, reason: type);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

CreatedTournament _knockoutTournament({
  bool withResult = false,
  String type = 'single_knockout',
  int stageCount = 1,
}) {
  final players = [
    for (var index = 1; index <= 4; index++) TournamentPlayer.generated(index),
  ];
  final firstMatch = GroupMatch(
    homePlayer: players[0],
    awayPlayer: players[3],
    round: 1,
    homeLegs: withResult ? 3 : null,
    awayLegs: withResult ? 1 : null,
  );
  final stages = [
    for (var index = 0; index < stageCount; index++)
      TournamentStage(
        name: 'K.-o.-Phase ${index + 1}',
        type: type,
        finalEndsTournament: true,
        knockoutParticipantCount: 4,
        knockoutBracketSize: 4,
      ),
  ];
  return CreatedTournament(
    name: 'Setzungstest',
    players: players,
    stages: stages,
    runStages: [
      for (final stage in stages)
        KnockoutTournamentRunStage(
          name: stage.name,
          rounds: [
            [
              firstMatch,
              GroupMatch(
                homePlayer: players[1],
                awayPlayer: players[2],
                round: 1,
              ),
            ],
            [GroupMatch(round: 2)],
          ],
          participants: players,
        ),
    ],
  );
}

Future<void> _scrollToText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  for (var attempt = 0; attempt < 8 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
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
