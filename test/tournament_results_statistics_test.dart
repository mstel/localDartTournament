import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/results/tournament_results_statistics.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'support/recorded_match.dart';

CreatedTournament resultsFixture({bool recorded = true}) {
  final match = recordedMatch();
  return CreatedTournament(
    name: 'Vereinsmeisterschaft',
    players: [match.homePlayer!, match.awayPlayer!],
    stages: [],
    runStages: [
      KnockoutTournamentRunStage(
        name: 'Finale',
        rounds: [
          [match],
        ],
      ),
    ],
  );
}

class ResultsStatisticsPreview extends StatelessWidget {
  const ResultsStatisticsPreview({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: AdaptiveContentList(
      children: [TournamentResultsStatistics(tournament: resultsFixture())],
    ),
  );
}

void main() {
  testWidgets('results statistics show zero and recorded best performances', (
    tester,
  ) async {
    final tournament = resultsFixture();
    final stage = tournament.runStages.single as KnockoutTournamentRunStage;
    stage.matches.single.bestPerformances = const [
      BestPerformance(
        type: BestPerformanceType.score170,
        playerName: 'Anna Musterfrau',
        value: 170,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveContentList(
            children: [TournamentResultsStatistics(tournament: tournament)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bestleistungen'), findsOneWidget);
    expect(find.text('170+'), findsOneWidget);
    expect(find.text('180+'), findsOneWidget);
    expect(find.text('High Finishes'), findsOneWidget);
    expect(find.text('Shortlegs'), findsOneWidget);
    final score170Card = find
        .ancestor(of: find.text('170+'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: score170Card, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('Anna Musterfrau · 170+'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results hide inline player stats and total ranking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: TournamentResultsPage(tournament: resultsFixture())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spielerstatistiken'), findsNothing);
    expect(find.text('Gesamtwertung'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Bestleistungen'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bestleistungen'), findsOneWidget);
    expect(find.byType(TournamentResultsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'manual results show zero best performances without inventing records',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveContentList(
              children: [
                TournamentResultsStatistics(
                  tournament: resultsFixture(recorded: false),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Spielerstatistiken'), findsNothing);
      expect(find.text('0'), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('results statistics at $size with 200 percent text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: TournamentResultsPage(tournament: resultsFixture()),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 14; i++) {
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
