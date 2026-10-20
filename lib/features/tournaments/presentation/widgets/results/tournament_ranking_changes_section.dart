import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import '../../../../rankings/domain/local_ranking.dart';
import '../../../../rankings/domain/elo_tier.dart';
import '../../../../rankings/application/local_ranking_elo_service.dart';
import '../../../data/app_database.dart';

class TournamentRankingChangesSection extends StatefulWidget {
  const TournamentRankingChangesSection({
    super.key,
    required this.tournament,
    this.database,
  });

  final CreatedTournament tournament;
  final LocalAppDatabase? database;

  @override
  State<TournamentRankingChangesSection> createState() =>
      _TournamentRankingChangesSectionState();
}

class _PlayerRankingDelta {
  const _PlayerRankingDelta({
    required this.playerProfileId,
    required this.playerName,
    required this.delta,
    required this.ratingBefore,
    required this.ratingAfter,
    required this.tierBefore,
    required this.tierAfter,
    required this.enableTiers,
    required this.rankingName,
  });

  final String playerProfileId;
  final String playerName;
  final int delta;
  final int ratingBefore;
  final int ratingAfter;
  final EloTier tierBefore;
  final EloTier tierAfter;
  final bool enableTiers;
  final String rankingName;

  bool get hasTierChange => enableTiers && tierBefore != tierAfter;
  bool get isPromotion => hasTierChange && ratingAfter > ratingBefore;
}

class _TournamentRankingChangesSectionState
    extends State<TournamentRankingChangesSection>
    with SingleTickerProviderStateMixin {
  late Future<List<_PlayerRankingDelta>> _deltasFuture;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _deltasFuture = _calculateDeltas();
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<List<_PlayerRankingDelta>> _calculateDeltas() async {
    final t = widget.tournament;
    final db = widget.database ?? LocalAppDatabase();
    final allRankings = await db.loadLocalRankings();
    final eloRankings = allRankings
        .where(
          (r) =>
              r.type == RankingType.elo &&
              (t.rankingIds.isEmpty || t.rankingIds.contains(r.id)),
        )
        .toList();

    if (eloRankings.isEmpty) return const [];

    final result = <_PlayerRankingDelta>[];

    for (final ranking in eloRankings) {
      try {
        final service = LocalRankingEloService(database: db);
        final snapshot = await service.calculate(ranking);

        for (final entry in snapshot.history.entries) {
          final items = entry.value
              .where((item) => item.tournamentId == t.id)
              .toList();
          if (items.isEmpty) continue;

          final totalDelta = items.fold<int>(0, (sum, i) => sum + i.delta);
          final firstItem = items.first;
          final lastItem = items.last;
          final ratingBefore = firstItem.ratingAfter - firstItem.delta;
          final ratingAfter = lastItem.ratingAfter;
          final playerName =
              snapshot.entries
                  .where((p) => p.id == entry.key)
                  .firstOrNull
                  ?.name ??
              entry.key;

          result.add(
            _PlayerRankingDelta(
              playerProfileId: entry.key,
              playerName: playerName,
              delta: totalDelta,
              ratingBefore: ratingBefore,
              ratingAfter: ratingAfter,
              tierBefore: EloTier.fromElo(ratingBefore),
              tierAfter: EloTier.fromElo(ratingAfter),
              enableTiers: ranking.enableTiers,
              rankingName: ranking.name,
            ),
          );
        }
      } catch (_) {
        // Continue with other rankings if calculation fails
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_PlayerRankingDelta>>(
      future: _deltasFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final deltas = snapshot.data!;
        final tierChanges = deltas.where((d) => d.hasTierChange).toList();
        final gains = deltas.where((d) => d.delta > 0).toList()
          ..sort((a, b) => b.delta.compareTo(a.delta));
        final losses = deltas.where((d) => d.delta < 0).toList()
          ..sort((a, b) => a.delta.compareTo(b.delta));

        final topGains = gains.take(3).toList();
        final topLosses = losses.take(3).toList();

        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.trending_up,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Änderungen der Rangliste',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tier-Wechsel (Auf- und Abstiege) mit Animation
            if (tierChanges.isNotEmpty) ...[
              ScaleTransition(
                scale: _scaleAnimation,
                child: Card(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.military_tech,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Liga-Auf- & Abstiege',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final change in tierChanges)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Icon(
                                  change.isPromotion
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  color: change.isPromotion
                                      ? Colors.green
                                      : Colors.red,
                                  size: 18,
                                ),
                                Text(
                                  change.playerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                _MiniTierBadge(tier: change.tierBefore),
                                const Icon(Icons.arrow_forward, size: 14),
                                _MiniTierBadge(tier: change.tierAfter),
                                Text(
                                  '${change.ratingBefore} → ${change.ratingAfter} Elo',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${change.delta > 0 ? "+" : ""}${change.delta}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: change.delta > 0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Top 3 Zuwachs & Top 3 Verlust
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top 3 Punktezuwachs
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.arrow_circle_up,
                                color: Colors.green,
                                size: 20,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Größter Punktezuwachs',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          if (topGains.isEmpty)
                            const Text(
                              'Keine Punktegewinne',
                              style: TextStyle(fontSize: 12),
                            )
                          else
                            for (var i = 0; i < topGains.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${i + 1}. ${topGains[i].playerName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${topGains[i].ratingBefore} → ${topGains[i].ratingAfter} Elo · +${topGains[i].delta}',
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Bottom 3 Punkteverlust
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.arrow_circle_down,
                                color: Colors.red,
                                size: 20,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Größter Punkteverlust',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          if (topLosses.isEmpty)
                            const Text(
                              'Keine Punkteverluste',
                              style: TextStyle(fontSize: 12),
                            )
                          else
                            for (var i = 0; i < topLosses.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${i + 1}. ${topLosses[i].playerName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${topLosses[i].ratingBefore} → ${topLosses[i].ratingAfter} Elo · ${topLosses[i].delta}',
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MiniTierBadge extends StatelessWidget {
  const _MiniTierBadge({required this.tier});
  final EloTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.2),
        border: Border.all(color: tier.color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tier.icon, size: 11, color: tier.color),
          const SizedBox(width: 3),
          Text(
            tier.name,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: tier.color,
            ),
          ),
        ],
      ),
    );
  }
}
