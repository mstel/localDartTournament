import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Elo trajectory shows its initial 1000 rating', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerEloHistoryPage(
          player: LocalEloPlayer(id: 'player-1', name: 'Spieler', rating: 1030),
          rankingName: 'Vereinsrangliste',
          history: [
            LocalEloHistoryItem(
              playedAt: DateTime(2026, 10, 20),
              tournamentName: 'Turnier 1',
              opponentName: 'Gegner',
              score: '2:0',
              delta: 30,
              ratingAfter: 1030,
              kFactor: 32,
              expectedScore: 0.5,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('1000 → 1030 Elo'), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });
}
