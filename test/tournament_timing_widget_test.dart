import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_timing_panel.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_timing.dart';

void main() {
  testWidgets('running clock can be reset and start time edited', (
    tester,
  ) async {
    final start = DateTime(2026, 10, 3, 12);
    final tournament =
        CreatedTournament(name: 'Test', players: [], stages: [], runStages: [])
          ..startedAt = start
          ..pausedAt = start.add(const Duration(minutes: 5))
          ..totalPausedSeconds = 300;
    DateTime? savedStart;
    final resetAt = DateTime.now();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TournamentTimingPanel(
              tournament: tournament,
              onStart: () async {},
              onEditTimes: (newStart, _) async {
                savedStart = newStart;
                tournament
                  ..startedAt = newStart
                  ..pausedAt = null
                  ..totalPausedSeconds = 0;
              },
              onResetClock: () async {
                TournamentTiming.resetClock(tournament, resetAt);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Startzeitpunkt neu festlegen'), findsOneWidget);
    await tester.tap(find.text('Startzeitpunkt neu festlegen'));
    await tester.pumpAndSettle();
    expect(find.text('Datum auswählen'), findsOneWidget);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    expect(find.text('Uhrzeit auswählen'), findsOneWidget);
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    expect(savedStart, isNotNull);
    expect(tournament.pausedAt, isNull);
    expect(tournament.totalPausedSeconds, 0);

    await tester.tap(find.text('Turnieruhr zurücksetzen'));
    await tester.pumpAndSettle();
    expect(find.text('Turnieruhr zurücksetzen?'), findsOneWidget);
    await tester.tap(find.text('Uhr zurücksetzen'));
    await tester.pumpAndSettle();

    expect(tournament.startedAt, resetAt);
    expect(tournament.pausedAt, isNull);
    expect(tournament.totalPausedSeconds, 0);
    expect(find.text('Laufzeit 0 h 0 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('timing panel wraps at $size and large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = CreatedTournament(
        name: 'Test',
        players: [],
        stages: [],
        runStages: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: TournamentTimingPanel(
                  tournament: t,
                  onStart: () async {
                    t.startedAt = DateTime.now();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Turnieruhr starten'));
      await tester.pump();
      expect(find.text('Turnieruhr'), findsOneWidget);
      expect(find.text('Läuft'), findsOneWidget);
      expect(find.text('Laufzeit 0 h 0 min'), findsOneWidget);
      expect(find.textContaining('Start: '), findsOneWidget);
      await tester.pump(const Duration(seconds: 75));
      expect(tester.takeException(), isNull);
      t.startedAt = DateTime.now().subtract(const Duration(minutes: 10));
      t.plannedMinutes = 60;
      t.plannedMatches = 6;
      t.plannedMatchEndSeconds = [600, 600, 1800, 1800, 3600, 3600];
      t.runStages.add(
        KnockoutTournamentRunStage(
          name: 'Finale',
          rounds: [
            [
              GroupMatch(
                  homePlayer: TournamentPlayer.generated(1),
                  awayPlayer: TournamentPlayer.generated(2),
                  round: 1,
                )
                ..homeLegs = 2
                ..awayLegs = 0,
            ],
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 15));
      expect(find.text('1 Spiele fertig · 2 laut Zeitplan'), findsOneWidget);
      expect(find.textContaining('Voraussichtliches Ende:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Zeitstatistik'));
      await tester.pumpAndSettle();
      expect(find.text('Zeitplan und Matchdauer'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
