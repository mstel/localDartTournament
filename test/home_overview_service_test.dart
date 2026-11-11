import 'package:dart_tournament_manager/features/home/application/home_overview_service.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/home/presentation/widgets/home_activity_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHomeOverviewSource implements HomeOverviewDataSource {
  _FakeHomeOverviewSource({
    required this.tournaments,
    this.rankings = const [],
  });

  final List<CreatedTournament> tournaments;
  final List<LocalRanking> rankings;
  int tournamentLoads = 0;
  int rankingLoads = 0;
  int eloLoads = 0;

  @override
  Future<List<CreatedTournament>> loadTournaments() async {
    tournamentLoads++;
    return tournaments;
  }

  @override
  Future<List<LocalRanking>> loadRankings() async {
    rankingLoads++;
    return rankings;
  }

  @override
  Future<LocalEloSnapshot?> loadEloSnapshot(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
  ) async {
    eloLoads++;
    return null;
  }
}

void main() {
  final playerA = TournamentPlayer(
    profileId: 'player-a',
    name: 'Marvin',
    isGenerated: false,
  );
  final playerB = TournamentPlayer(
    profileId: 'player-b',
    name: 'Daniel',
    isGenerated: false,
  );

  CreatedTournament tournament({
    required String id,
    required String name,
    required GroupMatch match,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) => CreatedTournament(
    id: id,
    name: name,
    players: [playerA, playerB],
    stages: const [],
    runStages: [
      KnockoutTournamentRunStage(
        name: 'Finale',
        rounds: [
          [match],
        ],
      ),
    ],
    startedAt: startedAt,
    finishedAt: finishedAt,
    rankingIds: const ['ranking'],
    countsForRanking: true,
  );

  GroupMatch resultMatch(DateTime finishedAt) => GroupMatch(
    homePlayer: playerA,
    awayPlayer: playerB,
    round: 1,
    homeLegs: 3,
    awayLegs: 1,
    finishedAt: finishedAt,
    bestPerformances: [
      const BestPerformance(
        type: BestPerformanceType.score180,
        playerName: 'Marvin',
        playerProfileId: 'player-a',
        value: 180,
      ),
      const BestPerformance(
        type: BestPerformanceType.shortLeg,
        playerName: 'Daniel',
        playerProfileId: 'player-b',
        value: 15,
      ),
    ],
    achievementNotifications: const [
      TournamentAchievementNotice(
        playerProfileId: 'player-a',
        playerName: 'Marvin',
        achievementName: 'Erster Sieg',
        explanation: 'Gewonnen',
        rankingName: 'Rangliste',
      ),
    ],
  );

  test('active tournaments skip ranking and statistics calculations', () async {
    final active = tournament(
      id: 'active',
      name: 'Vereinsabend',
      match: GroupMatch(homePlayer: playerA, awayPlayer: playerB, round: 1),
      startedAt: DateTime(2026, 8, 1, 18),
    );
    final source = _FakeHomeOverviewSource(
      tournaments: [active],
      rankings: const [
        LocalRanking(
          id: 'ranking',
          name: 'Standard',
          isDefaultForStatistics: true,
        ),
      ],
    );

    final snapshot = await HomeOverviewService(source).load();

    expect(snapshot.activeTournament?.name, 'Vereinsabend');
    expect(snapshot.activeTournament?.participantCount, 2);
    expect(snapshot.activeTournament?.totalMatches, 1);
    expect(snapshot.activeTournament?.openMatches, 1);
    expect(snapshot.cards, hasLength(7));
    expect(snapshot.latestTournament?.title, startsWith('Letztes Turnier'));
    expect(source.tournamentLoads, 1);
    expect(source.rankingLoads, 0);
    expect(source.eloLoads, 0);
  });

  test('overview exposes recent results, ranking stats and unlocks', () async {
    final past = tournament(
      id: 'past',
      name: 'Sommerpokal',
      match: resultMatch(DateTime(2026, 7, 1, 19)),
      finishedAt: DateTime(2026, 7, 1, 19),
    );
    final source = _FakeHomeOverviewSource(
      tournaments: [past],
      rankings: const [
        LocalRanking(
          id: 'ranking',
          name: 'Vereinsrangliste',
          isDefaultForStatistics: true,
        ),
      ],
    );

    final snapshot = await HomeOverviewService(source).load();

    expect(snapshot.activeTournament, isNull);
    expect(snapshot.latestTournament?.title, contains('Sommerpokal'));
    expect(snapshot.latestTournament?.lines.join(' '), contains('Datum:'));
    expect(snapshot.cards, hasLength(7));
    expect(
      snapshot.cards.first.lines.single,
      contains('Marvin besiegte Daniel'),
    );
    expect(snapshot.cards[1].lines.first, contains('Marvin'));
    expect(snapshot.cards[2].lines.join(' '), contains('1 geworfene 180er'));
    expect(snapshot.cards[4].lines.join(' '), contains('Ø 100.2'));
    expect(snapshot.cards[6].lines.single, 'Marvin: Erster Sieg');
    expect(source.tournamentLoads, 1);
    expect(source.rankingLoads, 1);
    expect(source.eloLoads, 1);
  });

  test('a 16-player two-group event reports all round-robin matches', () async {
    final players = [
      for (var index = 0; index < 16; index++)
        TournamentPlayer(
          profileId: 'player-$index',
          name: 'Spieler $index',
          isGenerated: false,
        ),
    ];
    final groups = [
      for (var groupIndex = 0; groupIndex < 2; groupIndex++)
        () {
          final members = players.skip(groupIndex * 8).take(8).toList();
          final matches = [
            for (var home = 0; home < members.length; home++)
              for (var away = home + 1; away < members.length; away++)
                GroupMatch(
                  homePlayer: members[home],
                  awayPlayer: members[away],
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 1,
                  finishedAt: DateTime(2026, 7, 1, 18 + home),
                ),
          ];
          return TournamentGroup(
            name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
            playType: 'round_robin',
            players: members,
            matches: matches,
          );
        }(),
    ];
    final event = CreatedTournament(
      id: 'group-event',
      name: 'Zwei Gruppen',
      players: players,
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: groups,
          qualificationPlan: null,
          tieBreakers: const ['points', 'legDifference', 'legsFor'],
        ),
      ],
      rankingIds: const ['ranking'],
      finishedAt: DateTime(2026, 7, 2),
    );
    final source = _FakeHomeOverviewSource(
      tournaments: [event],
      rankings: const [
        LocalRanking(
          id: 'ranking',
          name: 'Standard',
          isDefaultForStatistics: true,
        ),
      ],
    );

    final snapshot = await HomeOverviewService(source).load();

    expect(snapshot.cards[2].lines.first, '1 Turniere · 56 Begegnungen');
    expect(snapshot.cards[2].lines[1], '224 Legs · 0 geworfene 180er');
    expect(source.tournamentLoads, 1);
    expect(source.rankingLoads, 1);
  });

  testWidgets('active overview stays readable and opens the tournament', (
    tester,
  ) async {
    final active = tournament(
      id: 'active',
      name: 'Vereinsmeisterschaft',
      match: GroupMatch(homePlayer: playerA, awayPlayer: playerB, round: 1),
      startedAt: DateTime(2026, 8, 1),
    );
    final service = HomeOverviewService(
      _FakeHomeOverviewSource(tournaments: [active]),
    );
    final opened = <String>[];
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: HomeActivityPanel(
                  service: service,
                  onOpenTournament: opened.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AKTUELLES TURNIER'), findsOneWidget);
      expect(find.text('LETZTE 3 BEGEGNUNGEN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('Vereinsmeisterschaft'));
    expect(opened, ['active']);
  });

  testWidgets('rotating cards do not reload the snapshot', (tester) async {
    final past = tournament(
      id: 'past',
      name: 'Sommerpokal',
      match: resultMatch(DateTime(2026, 7, 1, 19)),
      finishedAt: DateTime(2026, 7, 1, 19),
    );
    final source = _FakeHomeOverviewSource(
      tournaments: [past],
      rankings: const [
        LocalRanking(
          id: 'ranking',
          name: 'Standard',
          isDefaultForStatistics: true,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeActivityPanel(
            service: HomeOverviewService(source),
            onOpenTournament: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LETZTE 3 BEGEGNUNGEN'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('LETZTES TURNIER · SOMMERPOKAL'), findsOneWidget);
    expect(source.tournamentLoads, 1);
    expect(source.rankingLoads, 1);
    expect(source.eloLoads, 1);
  });
}
