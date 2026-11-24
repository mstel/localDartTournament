import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_phase_results_page.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/standings_table.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show KnockoutBracketView;

void main() {
  testWidgets('results menu opens the per-phase detail view', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tournament = _phaseFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: TournamentResultsPage(
          tournament: tournament,
          database: _EmptyRankingDatabase(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menuAction = find.text('Einzelne Turnierphasen anzeigen');
    await tester.ensureVisible(menuAction);
    expect(menuAction, findsOneWidget);

    await tester.tap(menuAction);
    await tester.pumpAndSettle();

    expect(find.byType(TournamentPhaseResultsPage), findsOneWidget);
    expect(find.text('Vorrunde'), findsWidgets);
    expect(find.text('Endrunde'), findsWidgets);

    final standings = find.byType(StandingsTable);
    expect(standings, findsOneWidget);
    expect(
      find.descendant(of: standings, matching: find.text('Gruppen Spieler 1')),
      findsOneWidget,
    );
    expect(find.text('3:1'), findsAtLeastNWidgets(2));

    final koTab = find.widgetWithText(Tab, 'Endrunde');
    await tester.ensureVisible(koTab);
    await tester.tap(koTab);
    await tester.pumpAndSettle();

    expect(find.byType(KnockoutBracketView), findsOneWidget);
    expect(find.text('KO Sieger'), findsWidgets);
    expect(find.text('2:0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial phase index opens the requested phase', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TournamentPhaseResultsPage(
          tournament: _phaseFixture(),
          initialPhaseIndex: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(KnockoutBracketView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('phase details stay responsive at $size with 200% text', (
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
          home: TournamentPhaseResultsPage(tournament: _phaseFixture()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size group phase');

      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$size group phase scroll',
      );

      final koTab = find.widgetWithText(Tab, 'Endrunde');
      await tester.ensureVisible(koTab);
      await tester.tap(koTab);
      await tester.pumpAndSettle();
      expect(find.byType(KnockoutBracketView), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size knockout phase');
    });
  }
}

CreatedTournament _phaseFixture() {
  final groupPlayers = [
    for (var index = 1; index <= 4; index++)
      TournamentPlayer.generated(
        index,
      ).copyWith(name: 'Gruppen Spieler $index'),
  ];
  final groupStage = GroupTournamentRunStage(
    name: 'Vorrunde',
    groupPlayType: 'round_robin',
    qualificationPlan: null,
    tieBreakers: defaultGroupTieBreakers,
    groups: [
      TournamentGroup(
        name: 'Gruppe A',
        playType: 'round_robin',
        players: groupPlayers,
        matches: [
          GroupMatch(
            homePlayer: groupPlayers[0],
            awayPlayer: groupPlayers[1],
            round: 1,
            homeLegs: 3,
            awayLegs: 1,
          ),
          GroupMatch(
            homePlayer: groupPlayers[2],
            awayPlayer: groupPlayers[3],
            round: 1,
            homeLegs: 3,
            awayLegs: 0,
          ),
        ],
      ),
    ],
  );

  final knockoutPlayers = [
    TournamentPlayer.generated(5).copyWith(name: 'KO Sieger'),
    TournamentPlayer.generated(6).copyWith(name: 'KO Zweiter'),
    TournamentPlayer.generated(7).copyWith(name: 'KO Dritter'),
    TournamentPlayer.generated(8).copyWith(name: 'KO Vierter'),
  ];
  final koStage = KnockoutTournamentRunStage(
    name: 'Endrunde',
    rounds: [
      [
        GroupMatch(
          homePlayer: knockoutPlayers[0],
          awayPlayer: knockoutPlayers[1],
          round: 1,
          homeLegs: 2,
          awayLegs: 0,
          label: 'Finale',
        ),
      ],
    ],
    placementMatches: [
      GroupMatch(
        homePlayer: knockoutPlayers[2],
        awayPlayer: knockoutPlayers[3],
        round: 2,
        homeLegs: 2,
        awayLegs: 1,
        label: 'Spiel um Platz 3',
      ),
    ],
    finalEndsTournament: true,
  );

  return CreatedTournament(
    name: 'Phasen Turnier',
    players: [...groupPlayers, ...knockoutPlayers],
    stages: [
      const TournamentStage(name: 'Vorrunde', type: 'groups', groupSizes: [4]),
      const TournamentStage(
        name: 'Endrunde',
        type: 'single_knockout',
        knockoutParticipantCount: 4,
        knockoutSeedingMode: 'random',
      ),
    ],
    runStages: [groupStage, koStage],
    countsForRanking: false,
    startedAt: DateTime(2026, 11, 24, 10),
    finishedAt: DateTime(2026, 11, 24, 12),
    completedStageIndexes: const {0, 1},
  );
}

class _EmptyRankingDatabase extends LocalAppDatabase {
  @override
  Future<List<LocalRanking>> loadLocalRankings() async => const [];
}
