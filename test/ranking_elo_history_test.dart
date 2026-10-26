import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/widgets/elo_trajectory_chart.dart';
import 'package:flutter/gestures.dart';
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
              tournamentId: 'tournament-1',
              matchIndex: 0,
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
    expect(find.text('1000 → 1030 Elo'), findsNWidgets(2));
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Elo curve exposes the hovered tournament and rating delta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerEloHistoryPage(
          player: LocalEloPlayer(id: 'anna', name: 'Anna', rating: 1005),
          rankingName: 'Vereinsrangliste',
          history: [
            LocalEloHistoryItem(
              tournamentId: 'cup-a',
              matchIndex: 0,
              playedAt: DateTime(2025, 12, 20),
              tournamentName: 'Wintercup',
              opponentName: 'Ben',
              score: '1:0',
              delta: 12,
              ratingAfter: 1012,
              kFactor: 32,
              expectedScore: 0.5,
            ),
            LocalEloHistoryItem(
              tournamentId: 'cup-b',
              matchIndex: 0,
              playedAt: DateTime(2026, 1, 20),
              tournamentName: 'Frühjahrscup',
              opponentName: 'Caro',
              score: '0:1',
              delta: -7,
              ratingAfter: 1005,
              kFactor: 32,
              expectedScore: 0.5,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byType(EloTrajectoryChart);
    final rect = tester.getRect(chart);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.center);
    await mouse.moveTo(Offset(rect.right - 12, rect.center.dy));
    await tester.pump();

    expect(
      find.text('20.1.2026 · Frühjahrscup\n1005 Elo (-7)'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history and graph explain decay losses and attributed gains', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerEloHistoryPage(
          player: LocalEloPlayer(id: 'anna', name: 'Anna', rating: 1000),
          rankingName: 'Vereinsrangliste',
          history: [
            LocalEloHistoryItem(
              tournamentId: 'cup-a',
              matchIndex: -1,
              playedAt: DateTime(2026, 1, 20),
              tournamentName: 'Frühjahrscup',
              opponentName: 'Eigenes Versäumnis',
              score: '-6',
              delta: -6,
              ratingAfter: 994,
              kFactor: 0,
              expectedScore: 0,
              decayReason: LocalEloDecayReason.missedTournament,
            ),
            LocalEloHistoryItem(
              tournamentId: 'cup-a',
              matchIndex: -1,
              playedAt: DateTime(2026, 1, 20),
              tournamentName: 'Frühjahrscup',
              opponentName: 'Eigene Inaktivität',
              score: '-4',
              delta: -4,
              ratingAfter: 990,
              kFactor: 0,
              expectedScore: 0,
              decayReason: LocalEloDecayReason.extendedInactivity,
              missedTournamentCount: 3,
            ),
            LocalEloHistoryItem(
              tournamentId: 'cup-a',
              matchIndex: -1,
              playedAt: DateTime(2026, 1, 20),
              tournamentName: 'Frühjahrscup',
              opponentName: 'Chris',
              score: '+4',
              delta: 4,
              ratingAfter: 994,
              kFactor: 0,
              expectedScore: 0,
              decayReason: LocalEloDecayReason.missedTournament,
            ),
            LocalEloHistoryItem(
              tournamentId: 'cup-a',
              matchIndex: -1,
              playedAt: DateTime(2026, 1, 20),
              tournamentName: 'Frühjahrscup',
              opponentName: 'Chris',
              score: '+2',
              delta: 2,
              ratingAfter: 996,
              kFactor: 0,
              expectedScore: 0,
              decayReason: LocalEloDecayReason.extendedInactivity,
              missedTournamentCount: 3,
            ),
            LocalEloHistoryItem(
              tournamentId: 'cup-b',
              matchIndex: 0,
              playedAt: DateTime(2026, 2, 20),
              tournamentName: 'Vereinspokal',
              opponentName: 'Ben',
              score: '2:0',
              delta: 4,
              ratingAfter: 1000,
              kFactor: 32,
              expectedScore: 0.5,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verlust gesamt'), findsOneWidget);
    expect(find.text('10 Elo'), findsOneWidget);
    expect(
      find.text('+4 Elo, weil Chris ein Turnier verpasst hat'),
      findsOneWidget,
    );
    final chart = find.byType(EloTrajectoryChart);
    final rect = tester.getRect(chart);
    await tester.tapAt(Offset(rect.left + rect.width / 2, rect.center.dy));
    await tester.pump();

    expect(find.textContaining('Turnier verpasst: -6 Elo'), findsOneWidget);
    expect(
      find.textContaining(
        'Erhalten, weil Chris ein Turnier verpasst hat: +4 Elo',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tournament history cards start collapsed', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerEloHistoryPage(
          player: LocalEloPlayer(id: 'anna', name: 'Anna', rating: 1030),
          rankingName: 'Vereinsrangliste',
          history: [
            LocalEloHistoryItem(
              tournamentId: 'cup-a',
              matchIndex: 0,
              playedAt: DateTime(2026, 10, 20),
              tournamentName: 'Vereinspokal',
              opponentName: 'Ben',
              score: '1:0',
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

    expect(find.text('vs. Ben'), findsNothing);
    final tile = find.widgetWithText(ExpansionTile, 'Vereinspokal');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('vs. Ben'), findsOneWidget);
  });

  testWidgets('tournament cards and matches display rating before and after', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerEloHistoryPage(
          player: LocalEloPlayer(id: 'player-1', name: 'Spieler', rating: 1045),
          rankingName: 'Vereinsrangliste',
          history: [
            LocalEloHistoryItem(
              tournamentId: 'tournament-1',
              matchIndex: 0,
              playedAt: DateTime(2026, 10, 20),
              tournamentName: 'Turnier 1',
              opponentName: 'Gegner 1',
              score: '2:0',
              delta: 25,
              ratingAfter: 1025,
              kFactor: 32,
              expectedScore: 0.5,
            ),
            LocalEloHistoryItem(
              tournamentId: 'tournament-1',
              matchIndex: 1,
              playedAt: DateTime(2026, 10, 20),
              tournamentName: 'Turnier 1',
              opponentName: 'Gegner 2',
              score: '2:1',
              delta: 20,
              ratingAfter: 1045,
              kFactor: 32,
              expectedScore: 0.5,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Group total is +45, rating went from 1000 to 1045
    expect(find.text('+45 Elo'), findsOneWidget);
    expect(find.text('1000 → 1045 Elo'), findsNWidgets(2)); // in trajectory summary and in card trailing

    // Expand the card
    final tile = find.widgetWithText(ExpansionTile, 'Turnier 1');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // Matches show rating before -> after
    expect(find.text('1000 → 1025'), findsOneWidget);
    expect(find.text('1025 → 1045'), findsOneWidget);
    expect(find.textContaining('Elo: 1000 → 1025'), findsOneWidget);
    expect(find.textContaining('Elo: 1025 → 1045'), findsOneWidget);
  });

}
