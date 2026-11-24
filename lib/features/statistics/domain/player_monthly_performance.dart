import 'monthly_player_performance.dart';
import 'tournament_monthly_results.dart';

class PlayerMonthlyPerformance {
  const PlayerMonthlyPerformance({
    required this.playerId,
    required this.year,
    required this.month,
    required this.weightedLegs,
    this.matches = 0,
    this.wins = 0,
    this.losses = 0,
    this.scoring,
    this.average,
    this.checkoutRate,
    this.source = 'manual',
  });

  factory PlayerMonthlyPerformance.fromRow(Map<String, Object?> row) =>
      PlayerMonthlyPerformance(
        playerId: row['player_profile_id']! as String,
        year: row['year']! as int,
        month: row['month']! as int,
        weightedLegs: row['weighted_legs']! as int,
        matches: (row['matches'] as num?)?.toInt() ?? 0,
        wins: (row['wins'] as num?)?.toInt() ?? 0,
        losses: (row['losses'] as num?)?.toInt() ?? 0,
        scoring: (row['scoring'] as num?)?.toDouble(),
        average: (row['average'] as num?)?.toDouble(),
        checkoutRate: (row['checkout_rate'] as num?)?.toDouble(),
        source: row['source'] as String? ?? 'manual',
      );

  final String playerId;
  final int year;
  final int month;
  final int weightedLegs;
  final int matches;
  final int wins;
  final int losses;
  final double? scoring;
  final double? average;
  final double? checkoutRate;

  /// `manual` for historically imported or directly entered months,
  /// `scolia_cumulative` for months derived from cumulative Scolia snapshots.
  final String source;

  double get winRate => matches == 0 ? 0 : wins * 100 / matches;

  String get periodKey => '$year-${month.toString().padLeft(2, '0')}';
}

List<PlayerMonthlyPerformance> combineMonthlyPlayerPerformances({
  Iterable<PlayerMonthlyPerformance> recorded = const [],
  Iterable<MonthlyPlayerPerformance> imported = const [],
  Iterable<TournamentMonthlyResult>? tournamentResults,
}) {
  final byPeriod = <(String, int, int), PlayerMonthlyPerformance>{
    for (final entry in recorded)
      (entry.playerId, entry.year, entry.month): entry,
  };
  for (final entry in imported) {
    final year = int.parse(entry.month.substring(0, 4));
    final month = int.parse(entry.month.substring(5, 7));
    // From October 2026 onwards the cumulative Scolia path is authoritative.
    // Older imported history stays authoritative as before.
    if ((year > 2026 || year == 2026 && month >= 10) &&
        byPeriod.containsKey((entry.playerProfileId, year, month))) {
      continue;
    }
    // Imported history is authoritative for a matching player-month; never
    // count the same month twice when both storage paths contain a value.
    byPeriod[(entry.playerProfileId, year, month)] = PlayerMonthlyPerformance(
      playerId: entry.playerProfileId,
      year: year,
      month: month,
      weightedLegs: entry.legs,
      matches: entry.matches,
      scoring: entry.firstNineAverage,
      average: entry.threeDartAverage,
      checkoutRate: entry.checkoutPercentage,
    );
  }
  // Once tournament results are supplied they are the only source of truth
  // for match counts. Months without a tournament result therefore have zero
  // wins/losses instead of falling back to manually entered values.
  if (tournamentResults != null) {
    final derived = {
      for (final result in tournamentResults) result.key: result,
    };
    for (final entry in byPeriod.entries.toList()) {
      final result = derived[entry.key];
      final base = entry.value;
      final recordedLegs = base.weightedLegs;
      byPeriod[entry.key] = PlayerMonthlyPerformance(
        playerId: base.playerId,
        year: base.year,
        month: base.month,
        weightedLegs: recordedLegs > 0
            ? recordedLegs
            : result?.weightedLegs ?? 0,
        matches: result?.matches ?? 0,
        wins: result?.wins ?? 0,
        losses: result?.losses ?? 0,
        scoring: base.scoring,
        average: base.average,
        checkoutRate: base.checkoutRate,
        source: base.source,
      );
    }
    for (final result in derived.values) {
      if (byPeriod.containsKey(result.key)) continue;
      byPeriod[result.key] = PlayerMonthlyPerformance(
        playerId: result.playerId,
        year: result.year,
        month: result.month,
        weightedLegs: result.weightedLegs,
        matches: result.matches,
        wins: result.wins,
        losses: result.losses,
      );
    }
  }
  final result = byPeriod.values.toList()
    ..sort((left, right) {
      final yearOrder = left.year.compareTo(right.year);
      return yearOrder != 0 ? yearOrder : left.month.compareTo(right.month);
    });
  return List.unmodifiable(result);
}

List<PlayerMonthlyPerformance> aggregateMonthlyPlayerPerformances(
  Iterable<PlayerMonthlyPerformance> entries,
) {
  final byPeriod = <(int, int), _MonthlyPerformanceTotals>{};
  final matches = <(int, int), int>{};
  final wins = <(int, int), int>{};
  final losses = <(int, int), int>{};
  final firstPlayer = <(int, int), String>{};
  for (final entry in entries) {
    final period = (entry.year, entry.month);
    byPeriod.putIfAbsent(period, _MonthlyPerformanceTotals.new).add(entry);
    matches.update(
      period,
      (count) => count + entry.matches,
      ifAbsent: () => entry.matches,
    );
    wins.update(
      period,
      (count) => count + entry.wins,
      ifAbsent: () => entry.wins,
    );
    losses.update(
      period,
      (count) => count + entry.losses,
      ifAbsent: () => entry.losses,
    );
    firstPlayer.putIfAbsent(period, () => entry.playerId);
  }
  final periods = byPeriod.keys.toList()
    ..sort((left, right) {
      final yearOrder = left.$1.compareTo(right.$1);
      return yearOrder != 0 ? yearOrder : left.$2.compareTo(right.$2);
    });
  return List.unmodifiable([
    for (final period in periods)
      PlayerMonthlyPerformance(
        playerId: firstPlayer[period]!,
        year: period.$1,
        month: period.$2,
        matches: matches[period]!,
        wins: wins[period]!,
        losses: losses[period]!,
        weightedLegs: byPeriod[period]!.weightedLegs,
        scoring: byPeriod[period]!.scoring.value,
        average: byPeriod[period]!.average.value,
        checkoutRate: byPeriod[period]!.checkoutRate.value,
      ),
  ]);
}

class CurrentFormPerformance {
  const CurrentFormPerformance({
    required this.weightedLegs,
    required this.matches,
    required this.wins,
    required this.losses,
    required this.scoring,
    required this.average,
    required this.checkoutRate,
  });

  final int weightedLegs;
  final int matches;
  final int wins;
  final int losses;
  final double? scoring;
  final double? average;
  final double? checkoutRate;

  double get winRate => matches == 0 ? 0 : wins * 100 / matches;

  Map<String, dynamic> toJson() => {
    'weightedLegs': weightedLegs,
    'matches': matches,
    'wins': wins,
    'losses': losses,
    'winRate': winRate,
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
      matches: 0,
      wins: 0,
      losses: 0,
      scoring: null,
      average: null,
      checkoutRate: null,
    );
  }
  final today = now ?? DateTime.now();
  final monthStart = DateTime(today.year, today.month);
  final byPeriod = <(int, int), _MonthlyPerformanceTotals>{};
  for (final entry in entries) {
    if ((entry.weightedLegs <= 0 && entry.matches <= 0) ||
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
  var remainingWeight = targetLegs;
  var weightedLegs = 0;
  var matches = 0;
  var wins = 0;
  var losses = 0;
  final scoring = _WeightedMetric();
  final average = _WeightedMetric();
  final checkoutRate = _WeightedMetric();
  for (final period in periods) {
    if (remainingWeight <= 0) break;
    final totals = byPeriod[period]!;
    final weightTaken = remainingWeight
        .clamp(0, totals.selectionWeight)
        .toInt();
    if (totals.selectionWeight <= 0) continue;
    final fraction = weightTaken / totals.selectionWeight;
    weightedLegs += (totals.weightedLegs * fraction).round();
    matches += (totals.matches * fraction).round();
    wins += (totals.wins * fraction).round();
    losses += (totals.losses * fraction).round();
    remainingWeight -= weightTaken;
    scoring.addTotals(totals.scoring, fraction);
    average.addTotals(totals.average, fraction);
    checkoutRate.addTotals(totals.checkoutRate, fraction);
  }
  return CurrentFormPerformance(
    weightedLegs: weightedLegs,
    matches: matches,
    wins: wins,
    losses: losses,
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
    if (entry.weightedLegs > 0 || entry.matches > 0) totals.add(entry);
  }
  return CurrentFormPerformance(
    weightedLegs: totals.weightedLegs,
    matches: totals.matches,
    wins: totals.wins,
    losses: totals.losses,
    scoring: totals.scoring.value,
    average: totals.average.value,
    checkoutRate: totals.checkoutRate.value,
  );
}

class _MonthlyPerformanceTotals {
  int weightedLegs = 0;
  int selectionWeight = 0;
  int matches = 0;
  int wins = 0;
  int losses = 0;
  final _WeightedMetric scoring = _WeightedMetric();
  final _WeightedMetric average = _WeightedMetric();
  final _WeightedMetric checkoutRate = _WeightedMetric();

  void add(PlayerMonthlyPerformance entry) {
    // Legs remain the preferred weight for scoring averages. If a month only
    // contains tournament results, use the match count as a neutral weight so
    // wins/losses still contribute to current form and summaries.
    final effectiveWeight = entry.weightedLegs > 0
        ? entry.weightedLegs
        : entry.matches;
    weightedLegs += entry.weightedLegs;
    selectionWeight += effectiveWeight;
    matches += entry.matches;
    wins += entry.wins;
    losses += entry.losses;
    scoring.addMetric(entry.scoring, effectiveWeight.toDouble());
    average.addMetric(entry.average, effectiveWeight.toDouble());
    checkoutRate.addMetric(entry.checkoutRate, effectiveWeight.toDouble());
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
