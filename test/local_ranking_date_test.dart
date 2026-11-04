import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';

void main() {
  test('ranking date bounds include their whole selected days', () {
    final ranking = LocalRanking(
      id: 'r',
      name: '2026',
      validFromDate: DateTime(2026, 3, 15),
      validToDate: DateTime(2026, 9, 2),
    );

    expect(
      ranking.includesTournamentDate(DateTime(2026, 3, 15, 23, 59)),
      isTrue,
    );
    expect(
      ranking.includesTournamentDate(DateTime(2026, 9, 2, 23, 59)),
      isTrue,
    );
    expect(
      ranking.includesTournamentDate(DateTime(2026, 3, 14, 23, 59)),
      isFalse,
    );
    expect(ranking.includesTournamentDate(DateTime(2026, 9, 3)), isFalse);
  });

  test('legacy year bounds remain inclusive after loading old data', () {
    final ranking = LocalRanking.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'validFromYear': 2025,
      'validToYear': 2026,
    });

    expect(ranking.includesTournamentDate(DateTime(2025, 1, 1)), isTrue);
    expect(
      ranking.includesTournamentDate(DateTime(2026, 12, 31, 23, 59)),
      isTrue,
    );
    expect(ranking.includesTournamentDate(DateTime(2027, 1, 1)), isFalse);
  });

  test('unassigned-player ranking setting persists and defaults off', () {
    final legacy = LocalRanking.fromJson({'id': 'legacy', 'name': 'Legacy'});
    final enabled = LocalRanking(
      id: 'guest-enabled',
      name: 'Gastwertung',
      countUnassignedPlayers: true,
    );

    expect(legacy.countUnassignedPlayers, isFalse);
    expect(
      LocalRanking.fromJson(enabled.toJson()).countUnassignedPlayers,
      isTrue,
    );
    expect(
      enabled.copyWith(countUnassignedPlayers: false).countUnassignedPlayers,
      isFalse,
    );
  });
}
