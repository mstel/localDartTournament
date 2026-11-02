import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weighted legs are summed across recorded months', () {
    final entries = [
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 10,
        weightedLegs: 5,
      ),
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 12,
        weightedLegs: 7,
      ),
    ];

    expect(totalWeightedLegs(entries), 12);
  });
}
