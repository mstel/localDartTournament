import 'package:flutter/material.dart';

import '../../../statistics/domain/player_monthly_performance.dart';
import '../../../statistics/presentation/widgets/player_performance_trend_chart.dart';
import '../../application/ranking_year_review_service.dart';

class RankingMonthlyClubPerformanceSection extends StatelessWidget {
  const RankingMonthlyClubPerformanceSection({
    super.key,
    required this.monthlyPerformance,
  });

  final List<RankingMonthlyClubPerformance> monthlyPerformance;

  @override
  Widget build(BuildContext context) {
    if (monthlyPerformance.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gesamt-Performance pro Monat',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Keine Performance-Daten für diesen Zeitraum vorhanden.'),
        ],
      );
    }
    return PlayerPerformanceTrendChart(
      title: 'Gesamt-Performance pro Monat',
      year: null,
      entries: [
        for (final item in monthlyPerformance)
          PlayerMonthlyPerformance(
            playerId: 'club',
            year: item.year,
            month: item.month,
            weightedLegs: item.weightedLegs,
            matches: item.matches,
            scoring: item.scoring,
            average: item.average,
            checkoutRate: item.checkoutRate,
          ),
      ],
    );
  }
}
