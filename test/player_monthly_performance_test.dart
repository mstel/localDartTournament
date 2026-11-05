import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/statistics/domain/monthly_player_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'imported monthly aggregates feed weighted performance calculations',
    () {
      final combined = combineMonthlyPlayerPerformances(
        recorded: const [
          PlayerMonthlyPerformance(
            playerId: 'player-1',
            year: 2025,
            month: 10,
            weightedLegs: 20,
            scoring: 45,
            average: 80,
            checkoutRate: 30,
          ),
        ],
        imported: const [
          MonthlyPlayerPerformance(
            playerProfileId: 'player-1',
            sourcePlayerName: 'Spieler 1',
            month: '2025-10',
            threeDartAverage: 90,
            firstNineAverage: 55,
            legs: 60,
            matches: 15,
          ),
          MonthlyPlayerPerformance(
            playerProfileId: 'player-1',
            sourcePlayerName: 'Spieler 1',
            month: '2025-09',
            threeDartAverage: 70,
            firstNineAverage: 40,
            checkoutPercentage: 25,
            legs: 50,
            matches: 12,
          ),
        ],
      );

      expect(combined, hasLength(2));
      expect(combined.first.weightedLegs, 50);
      expect(combined.last.weightedLegs, 60);
      expect(combined.last.average, 90);
      expect(combined.last.scoring, 55);
      expect(combined.last.checkoutRate, isNull);
      expect(totalWeightedLegs(combined), 110);

      final overall = summarizeMonthlyPerformance(combined);
      expect(overall.weightedLegs, 110);
      expect(overall.average, closeTo((70 * 50 + 90 * 60) / 110, 0.001));
      expect(overall.scoring, closeTo((40 * 50 + 55 * 60) / 110, 0.001));
      expect(overall.checkoutRate, 25);

      final current = calculateCurrentFormPerformance(
        combined,
        now: DateTime(2025, 11),
      );
      expect(current.weightedLegs, 100);
      expect(current.average, 82);
      expect(current.scoring, 49);
    },
  );

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

  test('current form weights recent months and skips the current month', () {
    final entries = [
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 10,
        weightedLegs: 30,
        scoring: 80,
        average: 50,
        checkoutRate: 40,
      ),
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 8,
        weightedLegs: 70,
        scoring: 60,
        average: 40,
        checkoutRate: 20,
      ),
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 7,
        weightedLegs: 25,
        scoring: 20,
        average: 10,
        checkoutRate: 5,
      ),
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 11,
        weightedLegs: 50,
        scoring: 999,
        average: 999,
        checkoutRate: 99,
      ),
    ];

    final result = calculateCurrentFormPerformance(
      entries,
      now: DateTime(2026, 11, 3),
    );

    expect(result.weightedLegs, 100);
    expect(result.scoring, 66);
    expect(result.average, 43);
    expect(result.checkoutRate, 26);
  });

  test('current form uses all available completed-month legs below 100', () {
    final result = calculateCurrentFormPerformance([
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 10,
        weightedLegs: 30,
        scoring: 80,
        average: 50,
        checkoutRate: 40,
      ),
      const PlayerMonthlyPerformance(
        playerId: 'player-1',
        year: 2026,
        month: 9,
        weightedLegs: 20,
        scoring: 60,
        average: 40,
        checkoutRate: 20,
      ),
    ], now: DateTime(2026, 11, 3));

    expect(result.weightedLegs, 50);
    expect(result.scoring, 72);
    expect(result.average, 46);
    expect(result.checkoutRate, 32);
  });
}
