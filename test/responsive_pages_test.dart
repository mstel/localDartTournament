import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/home/application/home_overview_service.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show HomePage;

class _HomeOverviewSource implements HomeOverviewDataSource {
  @override
  Future<List<CreatedTournament>> loadTournaments() async {
    final home = TournamentPlayer(name: 'Spieler A', isGenerated: false);
    final away = TournamentPlayer(name: 'Spieler B', isGenerated: false);
    return [
      CreatedTournament(
        id: 'active',
        name: 'Laufendes Turnier',
        players: [home, away],
        stages: const [],
        runStages: [
          GroupTournamentRunStage(
            name: 'Gruppe A',
            groupPlayType: 'round_robin',
            qualificationPlan: null,
            tieBreakers: defaultGroupTieBreakers,
            groups: [
              TournamentGroup(
                name: 'Gruppe A',
                playType: 'round_robin',
                players: [home, away],
                matches: [
                  GroupMatch(homePlayer: home, awayPlayer: away, round: 1),
                ],
              ),
            ],
          ),
        ],
        startedAt: DateTime(2026, 8, 1),
      ),
    ];
  }

  @override
  Future<List<LocalRanking>> loadRankings() async => const [];

  @override
  Future<LocalEloSnapshot?> loadEloSnapshot(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
  ) async => null;
}

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('Hauptmenü bleibt bei $size und großer Schrift bedienbar', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: HomePage(
            homeOverviewService: HomeOverviewService(_HomeOverviewSource()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BEREIT FÜR DEN NÄCHSTEN WURF?'), findsOneWidget);
      expect(find.text('Deine Spielzentrale.'), findsOneWidget);
      if (size.width < 1100) {
        await tester.tap(find.byTooltip('Bereich wechseln'));
        await tester.pumpAndSettle();
        for (final label in [
          'Turniere',
          'Freundschafts- & Ligaspiele',
          'Spieler',
          'Statistiken',
          'Ranglisten',
        ]) {
          expect(find.text(label), findsWidgets);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
