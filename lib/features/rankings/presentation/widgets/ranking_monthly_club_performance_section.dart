import 'package:flutter/material.dart';

import '../../application/ranking_year_review_service.dart';

class RankingMonthlyClubPerformanceSection extends StatelessWidget {
  const RankingMonthlyClubPerformanceSection({
    super.key,
    required this.monthlyPerformance,
  });

  final List<RankingMonthlyClubPerformance> monthlyPerformance;

  @override
  Widget build(BuildContext context) {
    final maxLegs = monthlyPerformance.fold<int>(
      0,
      (maximum, item) =>
          item.weightedLegs > maximum ? item.weightedLegs : maximum,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vereinsentwicklung pro Monat',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (monthlyPerformance.isEmpty)
          const Text(
            'Keine Performance-Daten für diese Rangliste im gewählten Jahr '
            'vorhanden.',
          )
        else
          for (final performance in monthlyPerformance)
            _ClubMonthPerformanceRow(
              performance: performance,
              maxLegs: maxLegs,
            ),
      ],
    );
  }
}

class _ClubMonthPerformanceRow extends StatelessWidget {
  const _ClubMonthPerformanceRow({
    required this.performance,
    required this.maxLegs,
  });

  final RankingMonthlyClubPerformance performance;
  final int maxLegs;

  @override
  Widget build(BuildContext context) {
    const months = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];
    final month = months[performance.month - 1];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [Text(month), Text('${performance.weightedLegs} Legs')],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: maxLegs == 0 ? 0 : performance.weightedLegs / maxLegs,
              minHeight: 12,
            ),
          ),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('Scoring: ${_format(performance.scoring)}'),
              Text('Average: ${_format(performance.average)}'),
              Text('Checkout-Quote: ${_format(performance.checkoutRate)} %'),
            ],
          ),
        ],
      ),
    );
  }

  String _format(double? value) => value?.toStringAsFixed(1) ?? '–';
}
