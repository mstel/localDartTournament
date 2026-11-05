import 'package:flutter/material.dart';

import '../../domain/player_monthly_performance.dart';

class PlayerPerformanceSection extends StatelessWidget {
  const PlayerPerformanceSection({super.key, required this.performance});

  final List<PlayerMonthlyPerformance> performance;

  double? _mean(Iterable<double?> values) {
    final present = values.whereType<double>().toList();
    if (present.isEmpty) return null;
    return present.reduce((left, right) => left + right) / present.length;
  }

  @override
  Widget build(BuildContext context) {
    final meanScoring = _mean(performance.map((entry) => entry.scoring));
    final meanAverage = _mean(performance.map((entry) => entry.average));
    final meanCheckout = _mean(performance.map((entry) => entry.checkoutRate));
    final currentForm = calculateCurrentFormPerformance(performance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Performance (gesamt)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _PerformanceStatCard(
              label: 'Gewertete Legs',
              value: '${totalWeightedLegs(performance)}',
            ),
            _PerformanceStatCard(
              label: 'Scoring',
              value: meanScoring?.toStringAsFixed(1) ?? '–',
            ),
            _PerformanceStatCard(
              label: 'Average',
              value: meanAverage?.toStringAsFixed(1) ?? '–',
            ),
            _PerformanceStatCard(
              label: 'Checkout Quote',
              value: meanCheckout == null
                  ? '–'
                  : '${meanCheckout.toStringAsFixed(1)} %',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Aktuelle Form: letzte 100 Legs',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('Ausgewertet: ${currentForm.weightedLegs} gewertete Legs'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _PerformanceStatCard(
              label: 'Scoring',
              value: currentForm.scoring?.toStringAsFixed(1) ?? '–',
            ),
            _PerformanceStatCard(
              label: 'Average',
              value: currentForm.average?.toStringAsFixed(1) ?? '–',
            ),
            _PerformanceStatCard(
              label: 'Checkout Quote',
              value: currentForm.checkoutRate == null
                  ? '–'
                  : '${currentForm.checkoutRate!.toStringAsFixed(1)} %',
            ),
          ],
        ),
      ],
    );
  }
}

class _PerformanceStatCard extends StatelessWidget {
  const _PerformanceStatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
