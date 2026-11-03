import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/group_positions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps edits open until confirmation at large text sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final stage = GroupTournamentRunStage(
      name: 'Gruppen',
      groupPlayType: 'round_robin',
      qualificationPlan: null,
      tieBreakers: const [],
      groups: [
        for (var groupIndex = 0; groupIndex < 2; groupIndex++)
          TournamentGroup(
            name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
            playType: 'round_robin',
            players: [
              for (var index = 0; index < 16; index++)
                TournamentPlayer(
                  name: 'Spieler ${groupIndex * 16 + index + 1}',
                  isGenerated: false,
                ),
            ],
            matches: const [],
          ),
      ],
    );
    List<List<TournamentPlayer>>? result;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<List<List<TournamentPlayer>>>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(stage: stage),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppe A'), findsOneWidget);
    expect(find.text('Gruppe B'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Spieler 1'));
    await tester.tap(find.text('Spieler 17'));
    await tester.pumpAndSettle();

    expect(find.text('Gruppen neu einteilen'), findsOneWidget);
    expect(result, isNull);
    expect(find.text('Spieler 17'), findsOneWidget);
    expect(find.text('Spieler 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    expect(result, hasLength(2));
    expect(result![0].first.name, 'Spieler 17');
    expect(result![1].first.name, 'Spieler 1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports drag-and-drop between groups', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final stage = GroupTournamentRunStage(
      name: 'Gruppen',
      groupPlayType: 'round_robin',
      qualificationPlan: null,
      tieBreakers: const [],
      groups: [
        for (var groupIndex = 0; groupIndex < 2; groupIndex++)
          TournamentGroup(
            name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
            playType: 'round_robin',
            players: [
              for (var index = 0; index < 4; index++)
                TournamentPlayer(
                  name: 'Spieler ${groupIndex * 4 + index + 1}',
                  isGenerated: false,
                ),
            ],
            matches: const [],
          ),
      ],
    );
    List<List<TournamentPlayer>>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<List<List<TournamentPlayer>>>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(stage: stage),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    final source = tester.getCenter(find.text('Spieler 1'));
    final target = tester.getCenter(find.text('Spieler 5'));
    final gesture = await tester.startGesture(source);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('Gruppen neu einteilen'), findsOneWidget);
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(result![0].first.name, 'Spieler 5');
    expect(result![1].first.name, 'Spieler 1');
    expect(tester.takeException(), isNull);
  });
}
