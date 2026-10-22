import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _YearReviewDatabase extends LocalAppDatabase {
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
  Future<List<PlayerProfile>> loadPlayerProfiles() async => const [];

  @override
  Future<List<String>> loadRankingPlayerIds(String rankingId) async => const [];
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
}
