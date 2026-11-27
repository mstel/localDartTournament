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
    required this.clubMax,
  });

  final PlayerSpiderValues player;
  final PlayerSpiderValues clubAverage;
  final PlayerSpiderValues clubMax;

  /// Backward-compatible alias for older API consumers.
  PlayerSpiderValues get rankingMax => clubMax;

  static double normalizeWinRate(double winRate) {
    final value = winRate > 1 ? winRate / 100 : winRate;
    // 50% = middle ring (0.5 on 4-ring chart), 100% = full, 0% = center.
    return value.clamp(0.0, 1.0);
  }

  /// Scale cap for normalization: ceil(clubAverage) * 2, min 1.
  /// Values above this get full deflection; it does NOT change the displayed
  /// Vereinsmaximum, which remains the actual observed maximum.
  static double bestPerformancesScaleCap(double clubAverageBestPerformances) {
    final cap = clubAverageBestPerformances.ceil() * 2;
    return cap < 1 ? 1 : cap.toDouble();
  }

  static PlayerSpiderComparison build({
    required PlayerSpiderValues player,
    required Iterable<PlayerSpiderValues> cohort,
  }) {
    final values = cohort.toList();
    if (values.isEmpty) {
      return PlayerSpiderComparison(
        player: player,
        clubAverage: player,
        clubMax: PlayerSpiderValues(
          scoring: player.scoring,
          average: player.average,
          checkoutPercent: player.checkoutPercent,
          bestPerformances: player.bestPerformances,
          winRate: 100,
        ),
      );
    }
    double avg(double Function(PlayerSpiderValues v) pick) =>
        values.map(pick).fold<double>(0, (sum, value) => sum + value) /
        values.length;
    double maxValue(double Function(PlayerSpiderValues v) pick) => values
        .map(pick)
        .fold<double>(0, (max, value) => value > max ? value : max);

    final clubAverage = PlayerSpiderValues(
      scoring: avg((v) => v.scoring),
      average: avg((v) => v.average),
      checkoutPercent: avg((v) => v.checkoutPercent),
      bestPerformances: avg((v) => v.bestPerformances),
      winRate: avg((v) => v.winRate),
    );
    final clubMax = PlayerSpiderValues(
      scoring: maxValue((v) => v.scoring),
      average: maxValue((v) => v.average),
      checkoutPercent: maxValue((v) => v.checkoutPercent),
      bestPerformances: maxValue((v) => v.bestPerformances),
      winRate: 100,
    );
    return PlayerSpiderComparison(
      player: player,
      clubAverage: clubAverage,
      clubMax: clubMax,
    );
  }

  Map<String, dynamic> toJson() => {
    'player': player.toJson(),
    'clubAverage': clubAverage.toJson(),
    'clubMax': clubMax.toJson(),
    // Backward-compatible key for existing homepage consumers.
    'rankingMax': clubMax.toJson(),
    'labels': PlayerSpiderValues.labels,
  };
}
