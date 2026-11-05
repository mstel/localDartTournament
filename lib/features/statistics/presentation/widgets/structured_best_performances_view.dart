import 'package:flutter/material.dart';

import '../../domain/best_performance.dart';

class StructuredBestPerformancesView extends StatelessWidget {
  const StructuredBestPerformancesView({
    super.key,
    required this.bestPerformances,
    this.occurrences = const [],
    this.onTournamentTap,
  });

  final List<BestPerformance> bestPerformances;
  final List<BestPerformanceOccurrence> occurrences;
  final ValueChanged<String>? onTournamentTap;

  static const _types = [
    BestPerformanceType.score180,
    BestPerformanceType.bigFish170,
    BestPerformanceType.score171Plus,
    BestPerformanceType.highFinish,
    BestPerformanceType.bullseyeFinish,
    BestPerformanceType.shortLeg,
  ];

  @override
  Widget build(BuildContext context) {
    final normalized = bestPerformances
        .where(
          (performance) =>
              performance.normalizedType != BestPerformanceType.score170,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in _types)
          if (normalized.any(
            (performance) => performance.normalizedType == type,
          ))
            _PerformanceGroup(
              type: type,
              performances: normalized
                  .where((performance) => performance.normalizedType == type)
                  .toList(),
              occurrences: occurrences
                  .where(
                    (occurrence) =>
                        occurrence.performance.normalizedType == type,
                  )
                  .toList(),
              onTournamentTap: onTournamentTap,
            ),
      ],
    );
  }
}

class _PerformanceGroup extends StatelessWidget {
  const _PerformanceGroup({
    required this.type,
    required this.performances,
    required this.occurrences,
    required this.onTournamentTap,
  });

  final BestPerformanceType type;
  final List<BestPerformance> performances;
  final List<BestPerformanceOccurrence> occurrences;
  final ValueChanged<String>? onTournamentTap;

  @override
  Widget build(BuildContext context) {
    final title = switch (type) {
      BestPerformanceType.bigFish170 => '170 (Big Fish)',
      BestPerformanceType.score171Plus ||
      BestPerformanceType.score170 => '171+ Aufnahmen',
      BestPerformanceType.score180 => '180+ Aufnahmen',
      BestPerformanceType.highFinish => 'High Finishes',
      BestPerformanceType.bullseyeFinish => 'Bullseye Finishes',
      BestPerformanceType.shortLeg => 'Shortlegs',
    };
    final icon = switch (type) {
      BestPerformanceType.bullseyeFinish => Icons.gps_fixed,
      BestPerformanceType.highFinish => Icons.stars_outlined,
      BestPerformanceType.shortLeg => Icons.flash_on_outlined,
      _ => Icons.bolt,
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text('$title (${performances.length})'),
        children: occurrences.isEmpty
            ? [
                for (final performance in _groupedLegacyEntries())
                  ListTile(
                    dense: true,
                    title: Text(performance.$1),
                    trailing: Text('${performance.$2}×'),
                  ),
              ]
            : [
                for (final occurrence in occurrences)
                  _PerformanceOccurrenceRow(
                    occurrence: occurrence,
                    onTournamentTap: onTournamentTap,
                  ),
              ],
      ),
    );
  }

  List<(String, int)> _groupedLegacyEntries() {
    final counts = <String, int>{};
    for (final performance in performances) {
      final label = switch (type) {
        BestPerformanceType.shortLeg => '${performance.value ?? 18} Darts',
        BestPerformanceType.highFinish =>
          '${performance.value ?? 100} Checkout',
        BestPerformanceType.bullseyeFinish => 'Bullseye',
        _ => performance.details ?? performance.value?.toString() ?? 'Erfasst',
      };
      counts.update(label, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts.entries.map((entry) => (entry.key, entry.value)).toList();
  }
}

class _PerformanceOccurrenceRow extends StatelessWidget {
  const _PerformanceOccurrenceRow({
    required this.occurrence,
    required this.onTournamentTap,
  });

  final BestPerformanceOccurrence occurrence;
  final ValueChanged<String>? onTournamentTap;

  @override
  Widget build(BuildContext context) {
    final performance = occurrence.performance;
    final description = switch (performance.normalizedType) {
      BestPerformanceType.shortLeg =>
        performance.details ?? '${performance.value ?? 18} Darts',
      BestPerformanceType.highFinish =>
        performance.details ?? '${performance.value ?? 0} Checkout',
      BestPerformanceType.bullseyeFinish =>
        performance.details ?? 'Bullseye Finish',
      _ =>
        performance.details ??
            performance.value?.toString() ??
            performance.label,
    };
    final link = TextButton(
      onPressed: onTournamentTap == null
          ? null
          : () => onTournamentTap!(occurrence.tournamentId),
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: Theme.of(context).textTheme.bodyMedium,
      ),
      child: Text(occurrence.tournamentName, softWrap: true),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$description · ',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          link,
        ],
      ),
    );
  }
}
