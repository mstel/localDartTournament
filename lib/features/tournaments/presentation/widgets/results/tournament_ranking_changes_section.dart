import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import '../../../../rankings/domain/elo_tier.dart';
import '../../../../rankings/application/tournament_ranking_changes_service.dart';
import '../../../data/app_database.dart';
import '../../../data/tournament_storage.dart';

class TournamentRankingChangesSection extends StatefulWidget {
  const TournamentRankingChangesSection({
    super.key,
    required this.tournament,
    this.database,
    this.storage,
  });

  final CreatedTournament tournament;
  final LocalAppDatabase? database;
  final TournamentStorage? storage;

  @override
  State<TournamentRankingChangesSection> createState() =>
      _TournamentRankingChangesSectionState();
}

class _TournamentRankingChangesSectionState
    extends State<TournamentRankingChangesSection>
    with SingleTickerProviderStateMixin {
  late Future<List<TournamentRankingPlayerChange>> _deltasFuture;
  late String _rankingFingerprint;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  String _fingerprint() =>
      '${widget.tournament.countsForRanking}:${(widget.tournament.rankingIds.toList()..sort()).join(',')}';

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
    _rankingFingerprint = _fingerprint();
    _deltasFuture = _calculateDeltas();
    _animController.forward();
  }

  @override
  void didUpdateWidget(covariant TournamentRankingChangesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextFingerprint = _fingerprint();
    if (nextFingerprint != _rankingFingerprint) {
      _rankingFingerprint = nextFingerprint;
      _deltasFuture = _calculateDeltas();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<List<TournamentRankingPlayerChange>> _calculateDeltas() =>
      TournamentRankingChangesService(
        database: widget.database,
        storage: widget.storage,
      ).calculate(widget.tournament);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TournamentRankingPlayerChange>>(
      future: _deltasFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Ranglistenänderungen konnten nicht geladen werden.'),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final deltas = snapshot.data!;
        final tierChanges = deltas.where((d) => d.hasTierChange).toList();
        final gains = deltas.where((d) => d.delta > 0).toList()
          ..sort((a, b) => b.delta.compareTo(a.delta));
        final losses = deltas.where((d) => d.delta < 0).toList()
          ..sort((a, b) => a.delta.compareTo(b.delta));

        final topGains = gains;
        final topLosses = losses;

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
                            child: Row(
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
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${change.rankingName} · ${change.playerName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${change.delta > 0 ? "+" : ""}${change.delta} Elo '
                                        '(${change.ratingBefore} → ${change.ratingAfter})',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: change.delta > 0
                                              ? Colors.green
                                              : change.delta < 0
                                              ? Colors.red
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _MiniTierBadge(tier: change.tierBefore),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(Icons.arrow_forward, size: 14),
                                ),
                                _MiniTierBadge(tier: change.tierAfter),
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
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${i + 1}. ${topGains[i].rankingName} · '
                                        '${topGains[i].playerName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '+${topGains[i].delta} '
                                      '(${topGains[i].ratingBefore} → '
                                      '${topGains[i].ratingAfter})',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
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
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${i + 1}. ${topLosses[i].rankingName} · '
                                        '${topLosses[i].playerName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${topLosses[i].delta} '
                                      '(${topLosses[i].ratingBefore} → '
                                      '${topLosses[i].ratingAfter})',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
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
