import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/utils/png_image_export.dart';
import '../../rankings/domain/local_ranking.dart';
import '../application/player_statistics_image_generator.dart';
import '../domain/best_performance.dart';
import '../domain/local_statistics.dart';
import 'widgets/structured_best_performances_view.dart';

class LocalPlayerStatisticsPage extends StatefulWidget {
  const LocalPlayerStatisticsPage({
    super.key,
    required this.name,
    required this.profileIds,
    this.year,
  });
  final String name;
  final Set<String> profileIds;
  final int? year;
  @override
  State<LocalPlayerStatisticsPage> createState() =>
      _LocalPlayerStatisticsPageState();
}

class _LocalPlayerStatisticsPageState extends State<LocalPlayerStatisticsPage> {
  bool _exporting = false;
  late Future<
    (LocalPlayerStatistics, List<LocalRanking>, List<RankingPosition>)
  >
  _future = _load();

  Future<(LocalPlayerStatistics, List<LocalRanking>, List<RankingPosition>)>
  _load() async {
    const service = LocalStatisticsService();
    final stats = await service.forPlayers(
      widget.profileIds,
      year: widget.year,
    );
    final rankings = await service.rankingsFor(widget.profileIds);
    final positions = await service.rankingPositionsFor(
      widget.profileIds,
      rankings,
    );
    return (stats, rankings, positions);
  }

  Future<void> _export(PlayerStatisticsImageOrientation orientation) async {
    setState(() => _exporting = true);
    try {
      final colorScheme = Theme.of(context).colorScheme;
      final stats = (await _future).$1;
      if (!mounted) return;
      final bytes = await const PlayerStatisticsImageGenerator().generatePng(
        playerName: widget.name,
        statistics: stats,
        colorScheme: colorScheme,
        orientation: orientation,
      );
      if (!mounted) return;
      await exportPngImage(
        context,
        bytes: bytes,
        fileName:
            'spielerprofil-${widget.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}-${orientation.name}.png',
        successMessage: 'Spielerprofil-Grafik erfolgreich exportiert.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Spielerprofil-Grafik fehlgeschlagen: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.year == null
            ? widget.name
            : '${widget.name} · Jahresrückblick ${widget.year}',
      ),
      actions: [
        PopupMenuButton<PlayerStatisticsImageOrientation>(
          tooltip: 'Profilstatistik als Grafik exportieren',
          enabled: !_exporting,
          icon: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          onSelected: _export,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: PlayerStatisticsImageOrientation.portrait,
              child: Text('Als Grafik exportieren · Hochformat'),
            ),
            PopupMenuItem(
              value: PlayerStatisticsImageOrientation.landscape,
              child: Text('Als Grafik exportieren · Querformat'),
            ),
          ],
        ),
      ],
    ),
    body:
        FutureBuilder<
          (LocalPlayerStatistics, List<LocalRanking>, List<RankingPosition>)
        >(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AdaptiveContentList(
                children: [
                  const Text('Statistiken konnten nicht geladen werden.'),
                  TextButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final stats = data.$1;
            final rankings = data.$2;
            final positions = data.$3;
            final performanceCounts = {
              for (final type in BestPerformanceType.values)
                type: stats.bestPerformances
                    .where((item) => item.type == type)
                    .length,
            };
            return AdaptiveContentList(
              children: [
                Text(
                  widget.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),

                // Fix Priority 3: Ranglisten-Mitgliedschaft mit Rangposition
                if (rankings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final pos in positions)
                    _RankingPositionChip(position: pos),
                  if (positions.isEmpty)
                    Text(
                      'Ist Mitglied in Rangliste${rankings.length == 1 ? '' : 'n'} '
                      '${rankings.map((r) => r.name).join(', ')}',
                    ),
                ],

                const SizedBox(height: 16),
                Text(
                  'Turniere & Spiele',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(label: 'Turniere', value: '${stats.tournaments}'),
                    _StatCard(label: 'Spiele', value: '${stats.matches}'),
                    _StatCard(label: 'Siege', value: '${stats.wins}'),
                    _StatCard(label: 'Unentschieden', value: '${stats.draws}'),
                    _StatCard(label: 'Niederlagen', value: '${stats.losses}'),
                    _StatCard(
                      label: 'Turniersiege',
                      value: '${stats.tournamentWins}',
                    ),
                    _StatCard(
                      label: 'Turniersiegchance %',
                      value: '${stats.tournamentWinRate.toStringAsFixed(1)} %',
                    ),
                    _StatCard(
                      label: 'Siegquote',
                      value: '${stats.matchWinRate.toStringAsFixed(1)} %',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Legs & Sets',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      label: 'Legs gewonnen',
                      value: '${stats.legsWon}',
                    ),
                    _StatCard(
                      label: 'Legs verloren',
                      value: '${stats.legsLost}',
                    ),
                    _StatCard(
                      label: 'Leg-Siegquote',
                      value: '${stats.legWinRate.toStringAsFixed(1)} %',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Bestleistungen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatCard(
                      label: '170+ Aufnahmen',
                      value:
                          '${performanceCounts[BestPerformanceType.score170]}',
                    ),
                    _StatCard(
                      label: '180+ Aufnahmen',
                      value:
                          '${performanceCounts[BestPerformanceType.score180]}',
                    ),
                    _StatCard(
                      label: 'High Finish (100+)',
                      value:
                          '${performanceCounts[BestPerformanceType.highFinish]}',
                    ),
                    _StatCard(
                      label: 'Shortlegs (≤18 Darts)',
                      value:
                          '${performanceCounts[BestPerformanceType.shortLeg]}',
                    ),
                  ],
                ),
                StructuredBestPerformancesView(
                  bestPerformances: stats.bestPerformances,
                ),
              ],
            );
          },
        ),
  );
}

class _RankingPositionChip extends StatelessWidget {
  const _RankingPositionChip({required this.position});
  final RankingPosition position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rank = position.position;
    final total = position.total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Platz $rank von $total',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                TextSpan(
                  text: '  in ${position.ranking.name}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label, value;
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
