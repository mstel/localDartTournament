import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

({LocalRanking ranking, LocalEloSnapshot snapshot}) _fixture() {
  const ranking = LocalRanking(id: 'club-ranking', name: 'Club Elo');
  const homePlayer = TournamentPlayer(
    profileId: 'anna',
    name: 'Anna Darts',
    isGenerated: false,
  );
  const awayPlayer = TournamentPlayer(
    profileId: 'ben',
    name: 'Ben Darts',
    isGenerated: false,
  );
  final match =
      GroupMatch(homePlayer: homePlayer, awayPlayer: awayPlayer, round: 1)
        ..homeLegs = 1
        ..awayLegs = 0
        ..finishedAt = DateTime(2026, 5, 4);
  final tournament = CreatedTournament(
    id: 'club-cup',
    name: 'Vereinspokal',
    createdAt: DateTime(2026, 5, 4),
    finishedAt: DateTime(2026, 5, 4),
    players: const [homePlayer, awayPlayer],
    stages: const [],
    runStages: [
      KnockoutTournamentRunStage(
        name: 'Finale',
        rounds: [
          [match],
        ],
      ),
    ],
    rankingIds: [ranking.id],
  );
  final snapshot = const LocalEloCalculator().calculate(
    players: const {'anna': 'Anna Darts', 'ben': 'Ben Darts'},
    tournaments: [tournament],
    rankingId: ranking.id,
  );
  return (ranking: ranking, snapshot: snapshot);
}

void main() {
  testWidgets('ranking history expands to matches and returns to standings', (
    tester,
  ) async {
    final fixture = _fixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              LocalRankingEloViews(
                snapshot: fixture.snapshot,
                ranking: fixture.ranking,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aktueller Stand'), findsOneWidget);
    expect(find.text('Anna Darts'), findsOneWidget);
    await tester.tap(find.text('Nach Turnieren'));
    await tester.pumpAndSettle();
    expect(find.text('Vereinspokal'), findsOneWidget);

    await tester.tap(find.text('Vereinspokal'));
    await tester.pumpAndSettle();
    expect(find.text('Anna Darts'), findsOneWidget);
    expect(find.text('Ben Darts'), findsOneWidget);
    await tester.tap(find.text('Anna Darts'));
    await tester.pumpAndSettle();
    expect(find.text('Ben Darts · 1:0'), findsOneWidget);

    await tester.tap(find.text('Aktueller Stand'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Elo wird chronologisch aus abgeschlossenen'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('ranking history fits $size with 200 percent text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = _fixture();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                LocalRankingEloViews(
                  snapshot: fixture.snapshot,
                  ranking: fixture.ranking,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nach Turnieren'));
      await tester.pumpAndSettle();
      expect(find.text('Vereinspokal'), findsOneWidget);
      await tester.tap(find.text('Vereinspokal'));
      await tester.pumpAndSettle();
      expect(find.text('Anna Darts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
