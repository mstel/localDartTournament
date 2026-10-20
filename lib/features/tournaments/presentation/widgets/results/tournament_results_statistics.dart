import 'package:flutter/material.dart';
import '../../../../statistics/domain/best_performance.dart';
import '../../../domain/tournament_models.dart';

class TournamentResultsStatistics extends StatelessWidget {
  const TournamentResultsStatistics({super.key, required this.tournament});
  final CreatedTournament tournament;

  @override
  Widget build(BuildContext context) {
    final performances = [
      for (final stage in tournament.runStages)
        if (stage is KnockoutTournamentRunStage)
          ...stage.matches.expand((match) => match.bestPerformances)
        else if (stage is GroupTournamentRunStage)
          ...stage.groups.expand(
            (group) => [
              ...group.matches,
              ...group.knockoutRounds.expand((round) => round),
              ...group.placementMatches,
            ].expand((match) => match.bestPerformances),
          ),
    ];
    final heading = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bestleistungen', style: heading),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 640 ? 4 : 2;
            final spacing = 8.0;
            final tileWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final type in BestPerformanceType.values)
                  SizedBox(
                    width: tileWidth,
                    child: _PerformanceCountCard(
                      type: type,
                      count: performances
                          .where((item) => item.type == type)
                          .length,
                    ),
                  ),
              ],
            );
          },
        ),
        if (performances.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final performance in performances)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.military_tech_outlined),
              title: Text('${performance.playerName} · ${performance.label}'),
              trailing: performance.value == null
                  ? null
                  : Text('${performance.value}'),
            ),
        ],
      ],
    );
  }
}

class _PerformanceCountCard extends StatelessWidget {
  const _PerformanceCountCard({required this.type, required this.count});

  final BestPerformanceType type;
  final int count;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (type) {
            BestPerformanceType.score170 => '170+',
            BestPerformanceType.score180 => '180+',
            BestPerformanceType.highFinish => 'High Finishes',
            BestPerformanceType.shortLeg => 'Shortlegs',
          }),
          const SizedBox(height: 6),
          Text('$count', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    ),
  );
}
