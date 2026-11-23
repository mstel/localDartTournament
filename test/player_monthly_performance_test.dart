import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/statistics/domain/monthly_player_performance.dart';
import 'package:dart_tournament_manager/features/statistics/domain/tournament_monthly_results.dart';
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
            sourcePlayerName: 'Teilnehmer 1',
            month: '2025-10',
            threeDartAverage: 90,
            firstNineAverage: 55,
            legs: 60,
            matches: 15,
          ),
          MonthlyPlayerPerformance(
            playerProfileId: 'player-1',
            sourcePlayerName: 'Teilnehmer 1',
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
      expect(combined.last.matches, 15);
      expect(combined.last.wins, 0);
      expect(combined.last.losses, 0);
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

  test(
    'tournament results replace manual match counts but keep recorded metrics',
    () {
      final combined = combineMonthlyPlayerPerformances(
        recorded: const [
          PlayerMonthlyPerformance(
            playerId: 'player-1',
            year: 2025,
            month: 10,
            weightedLegs: 20,
            matches: 99,
            wins: 88,
            losses: 77,
            average: 80,
            scoring: 45,
          ),
        ],
        tournamentResults: const [
          TournamentMonthlyResult(
            playerId: 'player-1',
            year: 2025,
            month: 10,
            matches: 4,
            wins: 3,
            losses: 1,
            weightedLegs: 14,
          ),
          TournamentMonthlyResult(
            playerId: 'player-1',
            year: 2025,
            month: 9,
            matches: 2,
            wins: 0,
            losses: 2,
            weightedLegs: 8,
          ),
        ],
      );

      expect(combined, hasLength(2));
      expect(combined.first.month, 9);
      expect(combined.first.weightedLegs, 8);
      expect(combined.first.matches, 2);
      expect(combined.first.wins, 0);
      expect(combined.first.losses, 2);
      expect(combined.last.weightedLegs, 20);
      expect(combined.last.matches, 4);
      expect(combined.last.wins, 3);
      expect(combined.last.losses, 1);
      expect(combined.last.winRate, 75);
      expect(combined.last.average, 80);
      expect(combined.last.scoring, 45);

      final summary = summarizeMonthlyPerformance(combined);
      expect(summary.matches, 6);
      expect(summary.wins, 3);
      expect(summary.losses, 3);
      expect(summary.winRate, 50);
    },
  );

  test('monthly rows, aggregation and current form keep match results', () {
    const recent = PlayerMonthlyPerformance(
      playerId: 'player-1',
      year: 2026,
      month: 10,
      weightedLegs: 50,
      matches: 10,
      wins: 7,
      losses: 3,
    );
    const older = PlayerMonthlyPerformance(
      playerId: 'player-1',
      year: 2026,
      month: 9,
      weightedLegs: 70,
      matches: 14,
      wins: 7,
      losses: 7,
    );

    final row = PlayerMonthlyPerformance.fromRow({
      'player_profile_id': 'player-1',
      'year': 2026,
      'month': 10,
      'weighted_legs': 50,
      'matches': 10,
      'wins': 7,
      'losses': 3,
      'scoring': null,
      'average': null,
      'checkout_rate': null,
    });
    expect(row.matches, 10);
    expect(row.wins, 7);
    expect(row.losses, 3);
    expect(row.winRate, 70);

    final aggregated = aggregateMonthlyPlayerPerformances([
      recent,
      const PlayerMonthlyPerformance(
        playerId: 'player-2',
        year: 2026,
        month: 10,
        weightedLegs: 10,
        matches: 4,
        wins: 1,
        losses: 3,
      ),
    ]);
    expect(aggregated, hasLength(1));
    expect(aggregated.single.matches, 14);
    expect(aggregated.single.wins, 8);
    expect(aggregated.single.losses, 6);
    expect(aggregated.single.winRate, closeTo(8 * 100 / 14, 0.001));

    final current = calculateCurrentFormPerformance(
      [recent, older],
      now: DateTime(2026, 11, 3),
    );
    expect(current.matches, 20);
    expect(current.wins, 12);
    expect(current.losses, 8);
    expect(current.winRate, 60);
    expect(current.toJson(), containsPair('matches', 20));
    expect(current.toJson(), containsPair('wins', 12));
    expect(current.toJson(), containsPair('losses', 8));
    expect(current.toJson(), containsPair('winRate', 60.0));

    final empty = calculateCurrentFormPerformance(
      [recent],
      now: DateTime(2026, 11, 3),
      targetLegs: 0,
    );
    expect(empty.matches, 0);
    expect(empty.wins, 0);
    expect(empty.losses, 0);
    expect(empty.winRate, 0);
  });

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
