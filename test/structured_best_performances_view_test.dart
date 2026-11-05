import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/widgets/structured_best_performances_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('best performance expands to a tournament link', (tester) async {
    String? openedTournament;
    const performance = BestPerformance(
      type: BestPerformanceType.score180,
      playerName: 'Ada Dart',
      value: 180,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StructuredBestPerformancesView(
            bestPerformances: const [performance],
            occurrences: const [
              BestPerformanceOccurrence(
                performance: performance,
                tournamentId: 'tournament-1',
                tournamentName: 'Vereinsturnier September',
              ),
            ],
            onTournamentTap: (id) => openedTournament = id,
          ),
        ),
      ),
    );

    expect(find.text('180+ Aufnahmen (1)'), findsOneWidget);
    expect(find.text('Vereinsturnier September'), findsNothing);
    await tester.tap(find.text('180+ Aufnahmen (1)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('180 ·'), findsOneWidget);
    expect(find.text('Vereinsturnier September'), findsOneWidget);
    await tester.tap(find.text('Vereinsturnier September'));
    expect(openedTournament, 'tournament-1');
  });
}
