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
