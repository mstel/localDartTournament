import 'package:flutter/material.dart';
import '../../../../../shared/widgets/adaptive_content.dart';
import '../../../../statistics/domain/best_performance.dart';
import '../../../../statistics/domain/tournament_player_statistics.dart';
import '../../../../statistics/presentation/tournament_statistics_view.dart';
import '../../../domain/tournament_models.dart';

class TournamentResultsStatistics extends StatelessWidget {
  const TournamentResultsStatistics({super.key, required this.tournament});
  final CreatedTournament tournament;

  @override
  Widget build(BuildContext context) {
    final players = const TournamentStatisticsCalculator().calculate([
      tournament,
    ]);
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
        AdaptiveTileLayout(
          minTileWidth: 190,
          children: [
            for (final type in BestPerformanceType.values.where(
              (type) => type != BestPerformanceType.score170,
            ))
              _PerformanceCountCard(
                type: type,
                count: performances
                    .where((item) => item.normalizedType == type)
                    .length,
              ),
          ],
        ),
        if (performances.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final performance in performances)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.military_tech_outlined),
              title: Text('${performance.playerName} · ${performance.label}'),
              trailing: performance.value == null
                  ? (performance.details == null
                        ? null
                        : Text(performance.details!))
                  : Text('${performance.value}'),
            ),
        ],
        const SizedBox(height: 20),
        Text('Teilnehmerstatistiken', style: heading),
        const SizedBox(height: 12),
        if (players.isEmpty)
          const Text('Noch keine abgeschlossenen Begegnungen gespeichert.'),
        AdaptiveTileLayout(
          children: [
            for (final player in players) TournamentStatisticsCard(row: player),
          ],
        ),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (type) {
            BestPerformanceType.bigFish170 => '170 (Big Fish)',
            BestPerformanceType.score171Plus ||
            BestPerformanceType.score170 => '171+',
            BestPerformanceType.score180 => '180+',
            BestPerformanceType.highFinish => 'High Finishes',
            BestPerformanceType.bullseyeFinish => 'Bullseye Finishes',
            BestPerformanceType.shortLeg => 'Shortlegs',
          }),
          const SizedBox(height: 6),
          Text('$count', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    ),
  );
}
