import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/play_queue_block.dart';
import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/order_of_play_section.dart';

void main() {
  testWidgets('third tab and start action work on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final players = [
      TournamentPlayer.generated(1),
      TournamentPlayer.generated(2),
    ];
    final match = GroupMatch(
      homePlayer: players[0],
      awayPlayer: players[1],
      round: 1,
    );
    final tournament = CreatedTournament(
      name: 'Test',
      players: players,
      stages: [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppe',
          groupPlayType: 'round_robin',
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
          groups: [
            TournamentGroup(
              name: 'A',
              playType: 'round_robin',
              players: players,
              matches: [match],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                child: OrderOfPlaySection(
                  tournament: tournament,
                  activeStage: 0,
                  onChange: () async => setState(() {}),
                  onResult: (_) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verfügbare Boards'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Starten / vorziehen'));
    await tester.tap(find.byTooltip('Starten / vorziehen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auf Board 1 starten'));
    await tester.pumpAndSettle();
    expect(match.boardNumber, 1);
    expect(match.startedAt, isNotNull);
    expect(find.byTooltip('Match verwalten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Parallel blocks show engine order and update after starting both boards',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final players = List.generate(
        6,
        (i) => TournamentPlayer.generated(i + 1),
      );
      final matches = [
        for (var round = 1; round <= 2; round++)
          for (var pair = 0; pair < 3; pair++)
            GroupMatch(
              homePlayer: players[pair * 2],
              awayPlayer: players[pair * 2 + 1],
              round: round,
            ),
      ];
      final tournament = CreatedTournament(
        name: 'Zwei Boards',
        boardCount: 2,
        players: players,
        stages: [],
        runStages: [
          GroupTournamentRunStage(
            name: 'Gruppenphase',
            groupPlayType: 'round_robin',
            qualificationPlan: null,
            tieBreakers: defaultGroupTieBreakers,
            groups: [
              TournamentGroup(
                name: 'Gruppe A',
                playType: 'round_robin',
                players: players,
                matches: matches,
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: OrderOfPlaySection(
                  tournament: tournament,
                  activeStage: 0,
                  onChange: () async => setState(() {}),
                  onResult: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final planned = const OrderOfPlayController().plan(tournament, 0).planned;
      final shown = tester
          .widgetList<PlayQueueMatch>(find.byType(PlayQueueMatch))
          .toList();
      expect(
        shown.map((w) => (w.key! as ObjectKey).value),
        orderedEquals(planned.map((a) => a.entry.match)),
      );
      expect(
        shown.map((w) => w.board),
        orderedEquals(planned.map((a) => a.board)),
      );
      final first = tester
          .widgetList<PlayQueueBlock>(find.byType(PlayQueueBlock))
          .first;
      expect(first.next, isTrue);
      expect(first.number, 1);
      expect(first.parallelCount, 2);
      expect(first.children.length, 2);
      expect(
        find.text('2 Spiele parallel auf verschiedenen Boards'),
        findsWidgets,
      );
      for (final board in [1, 2]) {
        final start = find.byTooltip('Starten / vorziehen').first;
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Auf Board $board starten'));
        await tester.pumpAndSettle();
      }
      final next = tester
          .widgetList<PlayQueueBlock>(find.byType(PlayQueueBlock))
          .first;
      expect(next.next, isTrue);
      expect(next.number, 2);
      expect(next.waitingForBoards, isTrue);
      expect(
        const OrderOfPlayController().plan(tournament, 0).running.length,
        2,
      );
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<PlayQueueBlock>(find.byType(PlayQueueBlock))
            .first
            .number,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
