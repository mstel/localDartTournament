import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/group_positions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('supports selecting players and fits large groups responsively', (
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
    Object? result;

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
                result = await showDialog<List<TournamentPlayer>>(
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

    expect(result, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
