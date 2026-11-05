class MonthlyPlayerPerformance {
  const MonthlyPlayerPerformance({
    required this.playerProfileId,
    required this.sourcePlayerName,
    required this.month,
    required this.threeDartAverage,
    required this.firstNineAverage,
    required this.legs,
    required this.matches,
    this.checkoutPercentage,
  });

  final String playerProfileId;
  final String sourcePlayerName;
  final String month;
  final double threeDartAverage;
  final double firstNineAverage;
  final double? checkoutPercentage;
  final int legs;
  final int matches;

  DateTime get monthDate => DateTime(
    int.parse(month.substring(0, 4)),
    int.parse(month.substring(5, 7)),
  );

  factory MonthlyPlayerPerformance.fromRow(Map<String, Object?> row) =>
      MonthlyPlayerPerformance(
        playerProfileId: row['player_profile_id'] as String,
        sourcePlayerName: row['source_player_name'] as String,
        month: row['month'] as String,
        threeDartAverage: (row['three_dart_average'] as num).toDouble(),
        firstNineAverage: (row['first_nine_average'] as num).toDouble(),
        checkoutPercentage: (row['checkout_percentage'] as num?)?.toDouble(),
        legs: row['legs'] as int,
        matches: row['matches'] as int,
      );
}
