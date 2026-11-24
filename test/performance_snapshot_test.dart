import 'package:dart_tournament_manager/features/statistics/domain/performance_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

PerformanceSnapshot _snapshot(
  int year,
  int month,
  int legs, {
  double? average,
  double? scoring,
  double? checkout,
  int matches = 0,
  int? newLegsOverride,
}) {
  return PerformanceSnapshot.create(
    id: '$year-$month',
    playerId: 'player-1',
    year: year,
    month: month,
    windowLegs: legs,
    matches: matches,
    average: average,
    scoring: scoring,
    checkoutRate: checkout,
    newLegsOverride: newLegsOverride,
  );
}

void main() {
  test('October is the unchanged base and November is derived from totals', () {
    final derivation = derivePerformanceMonths([
      _snapshot(2026, 10, 30, average: 42, scoring: 50, checkout: 30),
      _snapshot(2026, 11, 60, average: 43, scoring: 52, checkout: 32),
    ]);

    expect(derivation.months, hasLength(2));
    final october = derivation.months.first;
    expect(october.periodKey, '2026-10');
    expect(october.weightedLegs, 30);
    expect(october.average, 42);
    expect(october.scoring, 50);
    expect(october.checkoutRate, 30);

    final november = derivation.months.last;
    expect(november.weightedLegs, 30);
    expect(november.average, closeTo(44, 0.0001));
    expect(november.scoring, closeTo(54, 0.0001));
    expect(november.checkoutRate, closeTo(34, 0.0001));
    expect(november.isEstimated, isFalse);
    expect(derivation.warnings, isEmpty);
  });

  test(
    'rolling 100 leg window uses known months and an explicit leg count',
    () {
      // October: 28 legs with average 42. November: 50 legs with average 44.
      // December: 40 legs with average 46, so Scolia shows 10 October legs,
      // 50 November legs and 40 December legs in its 100-leg window.
      const octoberAverage = 42.0;
      const novemberAverage = 44.0;
      const decemberAverage = 46.0;
      final novemberWindowAverage =
          (28 * octoberAverage + 50 * novemberAverage) / 78;
      final decemberWindowAverage =
          (10 * octoberAverage + 50 * novemberAverage + 40 * decemberAverage) /
          100;

      final derivation = derivePerformanceMonths([
        _snapshot(2026, 10, 28, average: octoberAverage),
        _snapshot(2026, 11, 78, average: novemberWindowAverage),
        _snapshot(
          2026,
          12,
          100,
          average: decemberWindowAverage,
          newLegsOverride: 40,
        ),
      ]);

      final december = derivation.monthFor('2026-12')!;
      expect(december.weightedLegs, 40);
      expect(december.average, closeTo(decemberAverage, 0.0001));
      expect(december.isEstimated, isFalse);
    },
  );

  test('saturated window without new leg count is marked as estimated', () {
    final derivation = derivePerformanceMonths([
      _snapshot(2026, 10, 28, average: 42),
      _snapshot(2026, 11, 78, average: 43.282051282),
      _snapshot(2026, 12, 100, average: 44.6),
    ]);

    final december = derivation.monthFor('2026-12')!;
    expect(december.isEstimated, isTrue);
    expect(derivation.warnings, isNotEmpty);
    expect(derivation.warnings.single, contains('100'));
  });

  test('months without new legs are not created', () {
    final derivation = derivePerformanceMonths([
      _snapshot(2026, 10, 30, average: 42),
      _snapshot(2026, 11, 30, average: 42),
    ]);

    expect(derivation.months, hasLength(1));
    expect(derivation.monthFor('2026-11'), isNull);
  });

  test('correcting a measurement recomputes all dependent months', () {
    final october = _snapshot(2026, 10, 30, average: 42);
    final before = derivePerformanceMonths([
      october,
      _snapshot(2026, 11, 60, average: 43),
    ]);
    final after = derivePerformanceMonths([
      october,
      _snapshot(2026, 11, 60, average: 44),
    ]);

    expect(before.monthFor('2026-11')!.average, closeTo(44, 0.0001));
    expect(after.monthFor('2026-11')!.average, closeTo(46, 0.0001));
  });

  test('missing cumulative metrics are not invented', () {
    final derivation = derivePerformanceMonths([
      _snapshot(2026, 10, 30),
      _snapshot(2026, 11, 60, average: 45),
    ]);

    expect(derivation.monthFor('2026-10')!.average, isNull);
    expect(derivation.monthFor('2026-11')!.average, isNull);
  });
}
