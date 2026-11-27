import 'best_performance.dart';
import 'local_statistics.dart';
import 'player_monthly_performance.dart';

class PlayerSpiderValues {
  const PlayerSpiderValues({
    required this.scoring,
    required this.average,
    required this.checkoutPercent,
    required this.bestPerformances,
    required this.winRate,
  });

  final double scoring;
  final double average;
  final double checkoutPercent;
  final double bestPerformances;
  final double winRate;

  static const labels = [
    'Scoring',
    'Average',
    'Checkout%',
    'Bestleistungen',
    'Siegesrate',
  ];

  List<double> toList() => [
    scoring,
    average,
    checkoutPercent,
    bestPerformances,
    winRate,
  ];

  Map<String, dynamic> toJson() => {
    'scoring': scoring,
    'average': average,
    'checkoutPercent': checkoutPercent,
    'bestPerformances': bestPerformances,
    'winRate': winRate,
  };

  factory PlayerSpiderValues.fromStats({
    required LocalPlayerStatistics stats,
    required Iterable<PlayerMonthlyPerformance> performance,
  }) {
    final summary = summarizeMonthlyPerformance(performance);
    final bestCount = stats.bestPerformances.where((performance) {
      final type = performance.normalizedType;
      return type == BestPerformanceType.bigFish170 ||
          type == BestPerformanceType.score171Plus ||
          type == BestPerformanceType.score180 ||
          type == BestPerformanceType.highFinish ||
          type == BestPerformanceType.bullseyeFinish ||
          type == BestPerformanceType.shortLeg;
    }).length;
    return PlayerSpiderValues(
      scoring: summary.scoring ?? 0,
      average: summary.average ?? 0,
      checkoutPercent: summary.checkoutRate ?? 0,
      bestPerformances: bestCount.toDouble(),
      winRate: stats.matchWinRate,
    );
  }
}

class PlayerSpiderComparison {
  const PlayerSpiderComparison({
    required this.player,
    required this.clubAverage,
    required this.rankingMax,
  });

  final PlayerSpiderValues player;
  final PlayerSpiderValues clubAverage;
  final PlayerSpiderValues rankingMax;

  static PlayerSpiderComparison build({
    required PlayerSpiderValues player,
    required Iterable<PlayerSpiderValues> cohort,
  }) {
    final values = cohort.toList();
    if (values.isEmpty) {
      return PlayerSpiderComparison(
        player: player,
        clubAverage: player,
        rankingMax: player,
      );
    }
    double avg(double Function(PlayerSpiderValues v) pick) =>
        values.map(pick).fold<double>(0, (sum, value) => sum + value) /
        values.length;
    double maxValue(double Function(PlayerSpiderValues v) pick) =>
        values.map(pick).fold<double>(0, (max, value) => value > max ? value : max);

    final clubAverage = PlayerSpiderValues(
      scoring: avg((v) => v.scoring),
      average: avg((v) => v.average),
      checkoutPercent: avg((v) => v.checkoutPercent),
      bestPerformances: avg((v) => v.bestPerformances),
      winRate: avg((v) => v.winRate),
    );
    final rankingMax = PlayerSpiderValues(
      scoring: maxValue((v) => v.scoring),
      average: maxValue((v) => v.average),
      checkoutPercent: maxValue((v) => v.checkoutPercent),
      bestPerformances: maxValue((v) => v.bestPerformances),
      winRate: maxValue((v) => v.winRate),
    );
    return PlayerSpiderComparison(
      player: player,
      clubAverage: clubAverage,
      rankingMax: rankingMax,
    );
  }

  Map<String, dynamic> toJson() => {
    'player': player.toJson(),
    'clubAverage': clubAverage.toJson(),
    'rankingMax': rankingMax.toJson(),
    'labels': PlayerSpiderValues.labels,
  };
}
