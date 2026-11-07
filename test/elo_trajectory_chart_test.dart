import 'package:dart_tournament_manager/features/rankings/presentation/widgets/elo_trajectory_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selecting an Elo point shows its tournament tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: EloTrajectoryChart(
              points: [
                EloTrajectoryPoint(
                  playedAt: DateTime(2026, 3, 4),
                  tournamentName: 'Frühjahrsturnier',
                  rating: 1210,
                  delta: 10,
                ),
                EloTrajectoryPoint(
                  playedAt: DateTime(2026, 4, 5),
                  tournamentName: 'Vereinspokal',
                  rating: 1234,
                  delta: 24,
                ),
              ],
              color: Colors.blue,
              gridColor: Colors.grey,
            ),
          ),
        ),
      ),
    );

    final chart = find.byType(EloTrajectoryChart);
    await tester.tapAt(tester.getTopLeft(chart) + const Offset(308, 90));
    await tester.pump();

    expect(find.textContaining('Vereinspokal'), findsOneWidget);
    expect(find.textContaining('1234 Elo (+24)'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Interaktive Elo-Entwicklung mit Monatsachse Januar bis Dezember',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Elo chart uses a calendar axis without a tournament name list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EloTrajectoryChart(
            points: [
              EloTrajectoryPoint(
                playedAt: DateTime(2026, 1, 10),
                tournamentName: 'Jahresauftakt',
                rating: 1010,
                delta: 10,
              ),
              EloTrajectoryPoint(
                playedAt: DateTime(2026, 12, 10),
                tournamentName: 'Jahresfinale',
                rating: 1080,
                delta: 70,
              ),
            ],
            color: Colors.blue,
            gridColor: Colors.grey,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Interaktive Elo-Entwicklung mit Monatsachse Januar bis Dezember',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Jahresauftakt'), findsNothing);
    expect(find.textContaining('Jahresfinale'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Elo calendar axis stays usable across responsive sizes', (
    tester,
  ) async {
    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: EloTrajectoryChart(
                points: [
                  EloTrajectoryPoint(
                    playedAt: DateTime(2026, 1, 10),
                    tournamentName: 'Start',
                    rating: 1000,
                    delta: 0,
                  ),
                  EloTrajectoryPoint(
                    playedAt: DateTime(2026, 12, 10),
                    tournamentName: 'Ende',
                    rating: 1100,
                    delta: 100,
                  ),
                ],
                color: Colors.blue,
                gridColor: Colors.grey,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        size.width < 768,
      );
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.reset);
  });
}
