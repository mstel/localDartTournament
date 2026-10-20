import 'package:dart_tournament_manager/features/rankings/application/ranking_order.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rankings = [
    LocalRanking(id: 'old', name: 'Beta', validFromYear: 2024, customOrder: 0),
    LocalRanking(id: 'new', name: 'Alpha', validFromYear: 2026, customOrder: 1),
    LocalRanking(id: 'undated', name: 'Gamma', customOrder: 2),
  ];

  test('sorts by start year descending with undated rankings last', () {
    expect(
      sortRankings(
        rankings,
        RankingSortMode.startYearDescending,
      ).map((ranking) => ranking.id),
      ['new', 'old', 'undated'],
    );
  });

  test('sorts alphabetically without regard to case', () {
    expect(
      sortRankings(
        rankings,
        RankingSortMode.alphabetical,
      ).map((ranking) => ranking.name),
      ['Alpha', 'Beta', 'Gamma'],
    );
  });

  test('uses custom order and stable name tie breaks', () {
    final tied = [
      rankings[1].copyWith(customOrder: 0),
      rankings[0],
      rankings[2],
    ];

    expect(
      sortRankings(tied, RankingSortMode.custom).map((ranking) => ranking.id),
      ['new', 'old', 'undated'],
    );
  });
}
