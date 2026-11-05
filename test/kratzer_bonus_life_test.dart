import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/models/match_result.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/result_entry.dart';

void main() {
  testWidgets('Kratzer result dialog records bonus life recipients', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final players = [
      TournamentPlayer.generated(1),
      TournamentPlayer.generated(2),
      TournamentPlayer.generated(3),
    ];
    final match = GroupMatch(
      isKratzer: true,
      players: players,
      scratchEligiblePlayers: players,
      round: 1,
    );
    MatchResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<MatchResult>(
                  context: context,
                  builder: (_) => KratzerResultDialog(
                    match: match,
                    enabledBonusTypes: const [
                      KratzerBonusLifeType.score180,
                      KratzerBonusLifeType.highFinish,
                    ],
                  ),
                );
              },
              child: const Text('Ergebnis öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ergebnis öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spieler 3'));
    await tester.tap(find.text('Bonusleben hinzufügen'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('kratzer-bonus-type-0-score180')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('High Finish').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('kratzer-bonus-player-0-Spieler 1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spieler 2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kratzer speichern'));
    await tester.pumpAndSettle();

    expect(result?.scratchedPlayer, players[2]);
    expect(result?.kratzerBonusLives, hasLength(1));
    expect(result?.kratzerBonusLives.single.player, players[1]);
    expect(
      result?.kratzerBonusLives.single.type,
      KratzerBonusLifeType.highFinish,
    );
    expect(tester.takeException(), isNull);
  });
}
