import 'monthly_player_performance.dart';

class PlayerMonthlyPerformance {
  const PlayerMonthlyPerformance({
    required this.playerId,
    required this.year,
    required this.month,
    required this.weightedLegs,
    this.scoring,
    this.average,
    this.checkoutRate,
  });

  factory PlayerMonthlyPerformance.fromRow(Map<String, Object?> row) =>
      PlayerMonthlyPerformance(
        playerId: row['player_profile_id']! as String,
        year: row['year']! as int,
        month: row['month']! as int,
        weightedLegs: row['weighted_legs']! as int,
        scoring: (row['scoring'] as num?)?.toDouble(),
        average: (row['average'] as num?)?.toDouble(),
        checkoutRate: (row['checkout_rate'] as num?)?.toDouble(),
      );

  final String playerId;
  final int year;
  final int month;
  final int weightedLegs;
  final double? scoring;
  final double? average;
  final double? checkoutRate;

  String get periodKey => '$year-${month.toString().padLeft(2, '0')}';
}

List<PlayerMonthlyPerformance> combineMonthlyPlayerPerformances({
  Iterable<PlayerMonthlyPerformance> recorded = const [],
  Iterable<MonthlyPlayerPerformance> imported = const [],
}) {
  final byPeriod = <(String, int, int), PlayerMonthlyPerformance>{
    for (final entry in recorded)
      (entry.playerId, entry.year, entry.month): entry,
  };
  for (final entry in imported) {
    final year = int.parse(entry.month.substring(0, 4));
    final month = int.parse(entry.month.substring(5, 7));
    // Imported history is authoritative for a matching player-month; never
    // count the same month twice when both storage paths contain a value.
    byPeriod[(entry.playerProfileId, year, month)] = PlayerMonthlyPerformance(
      playerId: entry.playerProfileId,
      year: year,
      month: month,
      weightedLegs: entry.legs,
      scoring: entry.firstNineAverage,
      average: entry.threeDartAverage,
      checkoutRate: entry.checkoutPercentage,
    );
  }
  final result = byPeriod.values.toList()
    ..sort((left, right) {
      final yearOrder = left.year.compareTo(right.year);
      return yearOrder != 0 ? yearOrder : left.month.compareTo(right.month);
    });
  return List.unmodifiable(result);
}

class CurrentFormPerformance {
  const CurrentFormPerformance({
    required this.weightedLegs,
    required this.scoring,
    required this.average,
    required this.checkoutRate,
  });

  final int weightedLegs;
  final double? scoring;
  final double? average;
  final double? checkoutRate;

  Map<String, dynamic> toJson() => {
    'weightedLegs': weightedLegs,
    'scoring': scoring,
    'average': average,
    'checkoutQuote': checkoutRate,
  };
}

CurrentFormPerformance calculateCurrentFormPerformance(
  Iterable<PlayerMonthlyPerformance> entries, {
  DateTime? now,
  int targetLegs = 100,
}) {
  if (targetLegs <= 0) {
    return const CurrentFormPerformance(
      weightedLegs: 0,
      scoring: null,
      average: null,
      checkoutRate: null,
    );
  }
  final today = now ?? DateTime.now();
  final monthStart = DateTime(today.year, today.month);
  final byPeriod = <(int, int), _MonthlyPerformanceTotals>{};
  for (final entry in entries) {
    if (entry.weightedLegs <= 0 ||
        !DateTime(entry.year, entry.month).isBefore(monthStart)) {
      continue;
    }
    final totals = byPeriod.putIfAbsent((
      entry.year,
      entry.month,
    ), _MonthlyPerformanceTotals.new);
    totals.add(entry);
  }

  final periods = byPeriod.keys.toList()
    ..sort((left, right) {
      final byYear = right.$1.compareTo(left.$1);
      return byYear != 0 ? byYear : right.$2.compareTo(left.$2);
    });
  var remainingLegs = targetLegs;
  var weightedLegs = 0;
  final scoring = _WeightedMetric();
  final average = _WeightedMetric();
  final checkoutRate = _WeightedMetric();
  for (final period in periods) {
    if (remainingLegs <= 0) break;
    final totals = byPeriod[period]!;
    final legsTaken = remainingLegs.clamp(0, totals.weightedLegs).toInt();
    final fraction = legsTaken / totals.weightedLegs;
    weightedLegs += legsTaken;
    remainingLegs -= legsTaken;
    scoring.addTotals(totals.scoring, fraction);
    average.addTotals(totals.average, fraction);
    checkoutRate.addTotals(totals.checkoutRate, fraction);
  }
  return CurrentFormPerformance(
    weightedLegs: weightedLegs,
    scoring: scoring.value,
    average: average.value,
    checkoutRate: checkoutRate.value,
  );
}

int totalWeightedLegs(Iterable<PlayerMonthlyPerformance> entries) =>
    entries.fold(0, (total, entry) => total + entry.weightedLegs);

CurrentFormPerformance summarizeMonthlyPerformance(
  Iterable<PlayerMonthlyPerformance> entries,
) {
  final totals = _MonthlyPerformanceTotals();
  for (final entry in entries) {
    if (entry.weightedLegs > 0) totals.add(entry);
  }
  return CurrentFormPerformance(
    weightedLegs: totals.weightedLegs,
    scoring: totals.scoring.value,
    average: totals.average.value,
    checkoutRate: totals.checkoutRate.value,
  );
}

class _MonthlyPerformanceTotals {
  int weightedLegs = 0;
  final _WeightedMetric scoring = _WeightedMetric();
  final _WeightedMetric average = _WeightedMetric();
  final _WeightedMetric checkoutRate = _WeightedMetric();

  void add(PlayerMonthlyPerformance entry) {
    weightedLegs += entry.weightedLegs;
    scoring.addMetric(entry.scoring, entry.weightedLegs.toDouble());
    average.addMetric(entry.average, entry.weightedLegs.toDouble());
    checkoutRate.addMetric(entry.checkoutRate, entry.weightedLegs.toDouble());
  }
}

class _WeightedMetric {
  double _weightedTotal = 0;
  double _weight = 0;

  void addTotals(_WeightedMetric source, double fraction) {
    if (source._weight == 0) return;
    _weightedTotal += source._weightedTotal * fraction;
    _weight += source._weight * fraction;
  }

  void addMetric(double? value, double weight) {
    if (value == null || weight <= 0) return;
    _weightedTotal += value * weight;
    _weight += weight;
  }

  double? get value => _weight == 0 ? null : _weightedTotal / _weight;
}
