import 'package:flutter/material.dart';
import '../../domain/best_performance.dart';

/// Summarizes best performances with collapsible groups for shortlegs and high finishes,
/// avoiding redundant listings for 180s and 170s.
class StructuredBestPerformancesView extends StatelessWidget {
  const StructuredBestPerformancesView({
    super.key,
    required this.bestPerformances,
  });

  final List<BestPerformance> bestPerformances;

  @override
  Widget build(BuildContext context) {
    if (bestPerformances.isEmpty) {
      return const SizedBox.shrink();
    }

    final shortLegs = bestPerformances
        .where((item) => item.type == BestPerformanceType.shortLeg)
        .toList();
    final highFinishes = bestPerformances
        .where((item) => item.type == BestPerformanceType.highFinish)
        .toList();
    final bullseyeFinishes = bestPerformances
        .where(
          (item) => item.normalizedType == BestPerformanceType.bullseyeFinish,
        )
        .toList();
    final score170 = bestPerformances
        .where((item) => item.normalizedType == BestPerformanceType.bigFish170)
        .length;
    final score171Plus = bestPerformances
        .where(
          (item) => item.normalizedType == BestPerformanceType.score171Plus,
        )
        .length;
    final score180 = bestPerformances
        .where((item) => item.normalizedType == BestPerformanceType.score180)
        .length;

    // Group shortlegs by dart count (ascending 9 to 18)
    final shortLegsByDarts = <int, int>{};
    for (final item in shortLegs) {
      final darts = item.value ?? 18;
      shortLegsByDarts[darts] = (shortLegsByDarts[darts] ?? 0) + 1;
    }
    final sortedDarts = shortLegsByDarts.keys.toList()..sort();

    // Group high finishes by finish score (descending 170 to 100)
    final highFinishesByScore = <int, int>{};
    for (final item in highFinishes) {
      final score = item.value ?? 100;
      highFinishesByScore[score] = (highFinishesByScore[score] ?? 0) + 1;
    }
    final sortedScores = highFinishesByScore.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    if (shortLegs.isEmpty &&
        highFinishes.isEmpty &&
        bullseyeFinishes.isEmpty &&
        score170 == 0 &&
        score171Plus == 0 &&
        score180 == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (score170 > 0)
          _PerformanceSummaryCard(
            icon: Icons.bolt,
            title: '170 (Big Fish)',
            count: score170,
          ),
        if (score171Plus > 0)
          _PerformanceSummaryCard(
            icon: Icons.bolt,
            title: '171+ Aufnahmen',
            count: score171Plus,
          ),
        if (score180 > 0)
          _PerformanceSummaryCard(
            icon: Icons.bolt,
            title: '180+ Aufnahmen',
            count: score180,
          ),
        if (bullseyeFinishes.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ExpansionTile(
              leading: const Icon(Icons.gps_fixed, color: Colors.redAccent),
              title: Text('Bullseye Finishes (${bullseyeFinishes.length})'),
              children: [
                for (final finish in bullseyeFinishes)
                  ListTile(
                    dense: true,
                    title: Text(finish.playerName),
                    subtitle: Text(finish.details ?? 'Bullseye'),
                  ),
              ],
            ),
          ),
        if (shortLegs.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ExpansionTile(
              leading: const Icon(Icons.flash_on_outlined, color: Colors.amber),
              title: Text('Shortlegs (${shortLegs.length})'),
              subtitle: const Text(
                'Hier tippen für Aufschlüsselung nach Darts (9–18)',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              children: [
                for (final darts in sortedDarts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$darts Darts',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${shortLegsByDarts[darts]}×',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (highFinishes.isNotEmpty)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ExpansionTile(
              leading: const Icon(Icons.stars_outlined, color: Colors.orange),
              title: Text('High Finishes (${highFinishes.length})'),
              subtitle: const Text(
                'Hier tippen für Aufschlüsselung nach Checkouts',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              children: [
                for (final score in sortedScores)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$score Checkout',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${highFinishesByScore[score]}×',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PerformanceSummaryCard extends StatelessWidget {
  const _PerformanceSummaryCard({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(leading: Icon(icon), title: Text('$title · $count')),
  );
}
