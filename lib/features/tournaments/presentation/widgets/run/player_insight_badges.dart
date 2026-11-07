import 'package:flutter/material.dart';

import '../../../domain/player_insight.dart';
import '../../../domain/tournament_models.dart';

class PlayerInsightBadgeRow extends StatelessWidget {
  const PlayerInsightBadgeRow({super.key, required this.insights});

  final List<PlayerInsight> insights;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 3,
      runSpacing: 2,
      children: [
        for (final insight in insights.take(3))
          Tooltip(
            message: insight.explanation,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_insightIcon(insight.type), size: 12),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          insight.type.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

List<PlayerInsight> insightsForMatch(
  GroupMatch match,
  Map<String, List<PlayerInsight>> playerInsights,
) {
  if (match.isKratzer || match.homePlayer == null || match.awayPlayer == null) {
    return const [];
  }
  final homeId = _playerInsightId(match.homePlayer!);
  final awayId = _playerInsightId(match.awayPlayer!);
  final selected = [
    for (final entry in [(homeId, awayId), (awayId, homeId)])
      for (final insight in playerInsights[entry.$1] ?? const [])
        if (insight.rivalId == null || insight.rivalId == entry.$2) insight,
  ];
  final grouped = <PlayerInsightType, List<PlayerInsight>>{};
  for (final insight in selected) {
    (grouped[insight.type] ??= []).add(insight);
  }
  return [
    for (final group in grouped.values.take(3))
      if (group.length == 1)
        group.single
      else
        PlayerInsight(
          type: group.first.type,
          playerId: group.first.playerId,
          explanation: [
            for (final insight in group)
              '${insight.playerId == homeId ? match.homePlayer!.name : match.awayPlayer!.name}: '
                  '${insight.explanation}',
          ].join('\n'),
        ),
  ];
}

IconData _insightIcon(PlayerInsightType type) => switch (type) {
  PlayerInsightType.hotStreak => Icons.local_fire_department,
  PlayerInsightType.coldStreak => Icons.ac_unit,
  PlayerInsightType.risingStar => Icons.trending_up,
  PlayerInsightType.momentum => Icons.speed,
  PlayerInsightType.unstoppable => Icons.bolt,
  PlayerInsightType.backOnTrack => Icons.replay,
  PlayerInsightType.consistent => Icons.check_circle_outline,
  PlayerInsightType.bogeyOpponent => Icons.sports,
  PlayerInsightType.rival => Icons.handshake_outlined,
  PlayerInsightType.sweetRevenge => Icons.gpp_good_outlined,
  PlayerInsightType.giantKiller => Icons.sports_kabaddi,
  PlayerInsightType.lastLegStanding => Icons.last_page,
  PlayerInsightType.underdog => Icons.arrow_upward,
  PlayerInsightType.titleDefender => Icons.emoji_events_outlined,
  PlayerInsightType.eloClimber => Icons.north_east,
};

String _playerInsightId(TournamentPlayer player) =>
    player.profileId ?? 'name:${player.name.trim().toLowerCase()}';
