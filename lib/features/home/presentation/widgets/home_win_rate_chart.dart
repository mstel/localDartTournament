import 'package:flutter/material.dart';

import '../../application/home_overview_service.dart';
import '../../../statistics/domain/player_monthly_performance.dart';
import '../../../statistics/presentation/widgets/player_performance_trend_chart.dart';

/// Compact club-wide win-rate trend for the homepage.
///
/// Only the existing "Siegesrate" series of the shared trend chart is shown;
/// the points come from [HomeOverviewSnapshot.winRateSeries].
class HomeWinRateChart extends StatelessWidget {
  const HomeWinRateChart({super.key, required this.points});

  final List<HomeWinRatePoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final entries = [
      for (final point in points)
        PlayerMonthlyPerformance(
          playerId: 'club',
          year: point.year,
          month: point.month,
          weightedLegs: point.matches,
          matches: point.matches,
          wins: point.wins,
          losses: point.losses,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 20),
            child: PlayerPerformanceTrendChart(
              entries: entries,
              year: null,
              seriesIndexes: const [3],
              title: 'Siegesrate pro Monat',
            ),
          ),
        );
      },
    );
  }
}
