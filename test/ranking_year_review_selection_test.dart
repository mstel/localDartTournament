import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/statistics/domain/monthly_player_performance.dart';
import 'package:dart_tournament_manager/features/rankings/application/ranking_year_review_service.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/imported_tournament_archive.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _YearReviewDatabase extends LocalAppDatabase {
  _YearReviewDatabase({
    this.performance = const [],
    this.importedPerformance = const [],
  });

  final List<PlayerMonthlyPerformance> performance;
  final List<MonthlyPlayerPerformance> importedPerformance;

  @override
  Future<List<LocalRanking>> loadLocalRankings() async => const [
    LocalRanking(id: 'other', name: 'Club 2025'),
    LocalRanking(
      id: 'default',
      name: 'DC Unzenberg 2026',
      isDefaultForStatistics: true,
    ),
  ];

  @override
  Future<List<PlayerProfile>> loadPlayerProfiles() async => [
    PlayerProfile(
      id: 'player',
      displayName: 'Robin Spieler',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime(2020),
      isActive: true,
    ),
    PlayerProfile(
      id: 'empty-player',
      displayName: 'Spieler ohne Messwerte',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime(2020),
      isActive: true,
    ),
    PlayerProfile(
      id: 'monthly-player',
      displayName: 'Spieler mit Vereinswerten',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime(2020),
      isActive: true,
    ),
  ];

  @override
  Future<List<String>> loadRankingPlayerIds(String rankingId) async =>
      rankingId == 'default'
      ? const ['player', 'empty-player', 'monthly-player']
      : const [];

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformanceForPlayers(
    Set<String> playerIds, {
    int? year,
  }) async => [
    for (final entry in performance)
      if (playerIds.contains(entry.playerId) &&
          (year == null || entry.year == year))
        entry,
  ];

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformance(
    String playerId, {
    int? year,
  }) async => [
    for (final entry in performance)
      if (entry.playerId == playerId && (year == null || entry.year == year))
        entry,
  ];

  @override
  Future<List<MonthlyPlayerPerformance>> loadMonthlyPlayerPerformances(
    Set<String> playerProfileIds, {
    int? year,
  }) async => [
    for (final entry in importedPerformance)
      if (playerProfileIds.contains(entry.playerProfileId) &&
          (year == null || int.parse(entry.month.substring(0, 4)) == year))
        entry,
  ];
}

class _YearReviewStorage extends TournamentStorage {
  _YearReviewStorage({this.tournaments = const []});

  final List<CreatedTournament> tournaments;

  @override
  Future<List<CreatedTournament>> loadTournaments() async => tournaments;
}

CreatedTournament _convertedChallongeWithBestPerformance() {
  final player = TournamentPlayer(
    profileId: 'player',
    name: 'Robin Spieler',
    isGenerated: false,
  );
  final opponent = TournamentPlayer(
    profileId: 'empty-player',
    name: 'Spieler ohne Messwerte',
    isGenerated: false,
  );
  const performance = {
    'type': 'score180',
    'playerName': 'Robin Spieler',
    'playerProfileId': 'player',
    'value': 180,
  };
  final match = GroupMatch(
    homePlayer: player,
    awayPlayer: opponent,
    round: 1,
    homeLegs: 3,
    awayLegs: 1,
    finishedAt: DateTime(2026, 2),
    bestPerformances: const [
      BestPerformance(
        type: BestPerformanceType.score180,
        playerName: 'Robin Spieler',
        playerProfileId: 'player',
        value: 180,
      ),
    ],
  );
  return CreatedTournament(
    id: 'challonge-converted',
    name: 'Challonge converted',
    createdAt: DateTime(2026, 2),
    finishedAt: DateTime(2026, 2),
    players: [player, opponent],
    stages: const [],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppe',
        groupPlayType: 'round_robin',
        groups: [
          TournamentGroup(
            name: 'A',
            playType: 'round_robin',
            players: [player, opponent],
            matches: [match],
          ),
        ],
        qualificationPlan: null,
        tieBreakers: const [],
      ),
    ],
    rankingIds: const ['default'],
    importedArchive: ImportedTournamentArchive(
      sourceId: 'source',
      url: 'https://challonge.com/example',
      mode: 'round robin',
      participants: const [
        {'id': '1', 'name': 'Robin Spieler', 'profileId': 'player'},
        {
          'id': '2',
          'name': 'Spieler ohne Messwerte',
          'profileId': 'empty-player',
        },
      ],
      matches: const [
        {
          'player1_id': '1',
          'player2_id': '2',
          'bestPerformances': [performance],
        },
      ],
      nativeValidation: const {'status': 'valid'},
    ),
  );
}

void main() {
  testWidgets('year review selects default ranking and year from its name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RankingYearReviewPage(
          database: _YearReviewDatabase(),
          tournamentStorage: _YearReviewStorage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rankingField = tester.widget<DropdownButtonFormField<LocalRanking>>(
      find.byType(DropdownButtonFormField<LocalRanking>),
    );
    final yearField = tester.widget<DropdownButtonFormField<int?>>(
      find.byType(DropdownButtonFormField<int?>),
    );

    expect(rankingField.initialValue?.id, 'default');
    expect(yearField.initialValue, 2026);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ranking year review lists monthly performance highs', (
    tester,
  ) async {
    final database = _YearReviewDatabase(
      importedPerformance: const [
        MonthlyPlayerPerformance(
          playerProfileId: 'monthly-player',
          sourcePlayerName: 'Spieler mit Vereinswerten',
          month: '2026-01',
          threeDartAverage: 100,
          firstNineAverage: 60,
          legs: 20,
          matches: 7,
        ),
      ],
      performance: const [
        PlayerMonthlyPerformance(
          playerId: 'player',
          year: 2026,
          month: 1,
          weightedLegs: 10,
          scoring: 57.8,
          average: 94.2,
          checkoutRate: 66.7,
        ),
        PlayerMonthlyPerformance(
          playerId: 'monthly-player',
          year: 2026,
          month: 1,
          weightedLegs: 30,
          scoring: 40.2,
          average: 80,
          checkoutRate: 20.1,
        ),
        PlayerMonthlyPerformance(
          playerId: 'player',
          year: 2025,
          month: 12,
          weightedLegs: 10,
          scoring: 71.4,
          average: 102.6,
          checkoutRate: 88.8,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RankingYearReviewPage(
          database: database,
          tournamentStorage: _YearReviewStorage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Höchster Average'), findsOneWidget);
    expect(find.text('Höchstes Scoring'), findsOneWidget);
    expect(find.text('Höchste Checkout-Quote'), findsOneWidget);
    expect(
      find.textContaining('Spieler mit Vereinswerten (100.0)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Spieler mit Vereinswerten (60.0)'),
      findsOneWidget,
    );
    expect(find.textContaining('Robin Spieler (66.7 %)'), findsOneWidget);
    expect(find.text('Gesamt-Performance pro Monat'), findsOneWidget);
    expect(find.text('59.3'), findsOneWidget);
    expect(find.text('98.1'), findsOneWidget);
    expect(find.text('66.7 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player year review shows monthly performance highs', (
    tester,
  ) async {
    final database = _YearReviewDatabase(
      importedPerformance: const [
        MonthlyPlayerPerformance(
          playerProfileId: 'player',
          sourcePlayerName: 'Robin Spieler',
          month: '2025-03',
          threeDartAverage: 100,
          firstNineAverage: 63.5,
          legs: 30,
          matches: 8,
        ),
        MonthlyPlayerPerformance(
          playerProfileId: 'player',
          sourcePlayerName: 'Robin Spieler',
          month: '2024-11',
          threeDartAverage: 130,
          firstNineAverage: 105,
          legs: 20,
          matches: 6,
        ),
      ],
      performance: const [
        PlayerMonthlyPerformance(
          playerId: 'player',
          year: 2025,
          month: 1,
          weightedLegs: 10,
          scoring: 41.2,
          average: 75.4,
        ),
        PlayerMonthlyPerformance(
          playerId: 'player',
          year: 2025,
          month: 2,
          weightedLegs: 10,
          scoring: 58.6,
          average: 91.3,
          checkoutRate: 42.8,
        ),
        PlayerMonthlyPerformance(
          playerId: 'player',
          year: 2024,
          month: 12,
          weightedLegs: 10,
          scoring: 99.9,
          average: 120.5,
          checkoutRate: 85.7,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RankingYearReviewPage(
          database: database,
          tournamentStorage: _YearReviewStorage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nach Spieler'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<PlayerProfile>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robin Spieler').last);
    await tester.pumpAndSettle();

    final yearField = find.byType(DropdownButtonFormField<int?>);
    await tester.tap(yearField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();

    expect(find.text('Höchster Average'), findsOneWidget);
    expect(find.text('Höchstes Scoring'), findsOneWidget);
    expect(find.text('Höchste Checkout-Quote'), findsOneWidget);
    expect(find.text('100.0'), findsWidgets);
    expect(find.text('63.5'), findsWidgets);
    expect(find.text('42.8 %'), findsWidgets);

    await tester.tap(yearField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesamter Zeitraum').last);
    await tester.pumpAndSettle();
    expect(find.text('130.0'), findsWidgets);
    expect(find.text('105.0'), findsWidgets);
    expect(find.text('85.7 %'), findsWidgets);

    final playerField = find.byType(DropdownButtonFormField<PlayerProfile>);
    await tester.tap(playerField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spieler ohne Messwerte').last);
    await tester.pumpAndSettle();
    expect(find.text('–'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  test(
    'native Challonge and retained archive count best performances once',
    () async {
      final review =
          await RankingYearReviewService(
            database: _YearReviewDatabase(),
            tournamentStorage: _YearReviewStorage(
              tournaments: [_convertedChallongeWithBestPerformance()],
            ),
          ).calculate(
            const LocalRanking(id: 'default', name: 'DC Unzenberg 2026'),
            2026,
          );

      final player = review.players['Robin Spieler']!;
      expect(player.bestPerformances, 1);
      expect(player.scores180, 1);
      expect(review.totalBestPerformances, 1);
      expect(review.total180, 1);
    },
  );
}
