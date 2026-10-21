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
    expect(tester.takeException(), isNull);
  });
}
