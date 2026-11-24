import 'package:dart_tournament_manager/features/home/application/home_overview_service.dart';
import 'package:dart_tournament_manager/features/home/presentation/widgets/home_activity_panel.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ChartFakeSource implements HomeOverviewDataSource {
  const _ChartFakeSource();

  @override
  Future<List<CreatedTournament>> loadTournaments() async {
    final player = TournamentPlayer(
      profileId: 'player-a',
      name: 'Marvin',
      isGenerated: false,
    );
    final opponent = TournamentPlayer(
      profileId: 'player-b',
      name: 'Daniel',
      isGenerated: false,
    );
    return [
      CreatedTournament(
        id: 'completed',
        name: 'Sommerpokal',
        players: [player, opponent],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [
                GroupMatch(
                  homePlayer: player,
                  awayPlayer: opponent,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 1,
                  finishedAt: DateTime(2026, 7, 1, 19),
                ),
              ],
            ],
          ),
        ],
        finishedAt: DateTime(2026, 7, 1, 19),
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget buildPanel() => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: HomeActivityPanel(
            service: HomeOverviewService(const _ChartFakeSource()),
            onOpenTournament: (_) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('homepage does not render win-rate statistics', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(buildPanel());
      await tester.pumpAndSettle();

      expect(find.textContaining('Siegesrate'), findsNothing);
      expect(find.text('Sieger: Marvin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('win-rate statistics stay hidden without monthly data', (
    tester,
  ) async {
    await tester.pumpWidget(buildPanel());
    await tester.pumpAndSettle();

    expect(find.textContaining('Siegesrate'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
