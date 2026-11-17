import 'package:flutter/material.dart';
import '../../app/app_theme.dart';
import 'adaptive_content.dart';

class SportMetric {
  const SportMetric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
}

/// Small, natural-height score tiles which also work with enlarged text.
class SportMetricGrid extends StatelessWidget {
  const SportMetricGrid({super.key, required this.metrics});
  final List<SportMetric> metrics;
  @override
  Widget build(BuildContext context) => AdaptiveTileLayout(
    minTileWidth: 100,
    children: [
      for (final metric in metrics)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                metric.icon,
                size: 20,
                color: appAccentColor(context),
              ),
              const SizedBox(height: 8),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(metric.label),
            ],
          ),
        ),
    ],
  );
}
