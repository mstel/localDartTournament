import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _YearReviewDatabase extends LocalAppDatabase {
  _YearReviewDatabase({this.performance = const []});

  final List<PlayerMonthlyPerformance> performance;

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
  ];

  @override
  Future<List<String>> loadRankingPlayerIds(String rankingId) async => const [];

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformance(
    String playerId, {
    int? year,
  }) async => [
    for (final entry in performance)
      if (entry.playerId == playerId && (year == null || entry.year == year))
        entry,
  ];
}

class _YearReviewStorage extends TournamentStorage {
  @override
  Future<List<CreatedTournament>> loadTournaments() async => const [];
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

  testWidgets('player year review shows monthly performance highs', (
    tester,
  ) async {
    final database = _YearReviewDatabase(
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
    expect(find.text('91.3'), findsWidgets);
    expect(find.text('58.6'), findsWidgets);
    expect(find.text('42.8 %'), findsWidgets);

    await tester.tap(yearField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesamter Zeitraum').last);
    await tester.pumpAndSettle();
    expect(find.text('120.5'), findsWidgets);
    expect(find.text('99.9'), findsWidgets);
    expect(find.text('85.7 %'), findsWidgets);

    final playerField = find.byType(DropdownButtonFormField<PlayerProfile>);
    await tester.tap(playerField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spieler ohne Messwerte').last);
    await tester.pumpAndSettle();
    expect(find.text('–'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
