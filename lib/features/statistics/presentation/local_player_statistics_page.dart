import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/utils/png_image_export.dart';
import '../../achievements/application/ranking_achievement_service.dart';
import '../../achievements/presentation/ranking_achievement_section.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../application/player_statistics_image_generator.dart';
import '../domain/best_performance.dart';
import '../domain/local_statistics.dart';
import '../domain/player_monthly_performance.dart';
import 'widgets/player_performance_section.dart';
import 'widgets/structured_best_performances_view.dart';

class LocalPlayerStatisticsPage extends StatefulWidget {
  const LocalPlayerStatisticsPage({
    super.key,
    required this.name,
    required this.profileIds,
    this.year,
    LocalAppDatabase? database,
    TournamentStorage? tournamentStorage,
  }) : _database = database,
       _tournamentStorage = tournamentStorage;
  final String name;
  final Set<String> profileIds;
  final int? year;
  final LocalAppDatabase? _database;
  final TournamentStorage? _tournamentStorage;
  @override
  State<LocalPlayerStatisticsPage> createState() =>
      _LocalPlayerStatisticsPageState();
}

class _LocalPlayerStatisticsPageState extends State<LocalPlayerStatisticsPage> {
  bool _exporting = false;
  late final _database = widget._database ?? LocalAppDatabase();
  late final _tournamentStorage =
      widget._tournamentStorage ?? TournamentStorage();
  late Future<
    (
      LocalPlayerStatistics,
      List<LocalRanking>,
      List<RankingPosition>,
      List<PlayerMonthlyPerformance>,
      List<RankingAchievementView>,
    )
  >
  _future = _load();

  Future<
    (
      LocalPlayerStatistics,
      List<LocalRanking>,
      List<RankingPosition>,
      List<PlayerMonthlyPerformance>,
      List<RankingAchievementView>,
    )
  >
  _load() async {
    final service = LocalStatisticsService(
      database: _database,
      storage: _tournamentStorage,
    );
    final stats = await service.forPlayers(
      widget.profileIds,
      year: widget.year,
    );
    final rankings = await service.rankingsFor(widget.profileIds);
    final positions = await service.rankingPositionsFor(
      widget.profileIds,
      rankings,
    );
    final performance = [
      for (final profileId in widget.profileIds)
        ...await _database.loadPlayerMonthlyPerformance(profileId),
    ];
    final achievementViews = <RankingAchievementView>[];
    final achievementRankings = rankings
        .where((ranking) => ranking.achievementsEnabled)
        .toList();
    final achievementService = RankingAchievementService(
      database: _database,
      tournamentStorage: _tournamentStorage,
    );
    for (final ranking in achievementRankings) {
      final assignedIds = await _database.loadRankingPlayerIds(ranking.id);
      for (final profileId in widget.profileIds.where(assignedIds.contains)) {
        final evaluation = await achievementService.loadPlayerEvaluation(
          ranking: ranking,
          playerProfileId: profileId,
        );
        if (evaluation == null) continue;
        achievementViews.add(
          RankingAchievementView(
            ranking: ranking,
            playerProfileId: profileId,
            evaluation: evaluation,
          ),
        );
      }
    }
    return (stats, rankings, positions, performance, achievementViews);
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
            backgroundColor: Theme.of(context).colorScheme.error,
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
          (
            LocalPlayerStatistics,
            List<LocalRanking>,
            List<RankingPosition>,
            List<PlayerMonthlyPerformance>,
            List<RankingAchievementView>,
          )
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
            final performance = data.$4;
            final achievements = data.$5;
            final performanceCounts = {
              for (final type in BestPerformanceType.values.where(
                (type) => type != BestPerformanceType.score170,
              ))
                type: stats.bestPerformances
                    .where((item) => item.normalizedType == type)
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
                    _StatCard(
                      label: 'Spiele gespielt',
                      value: '${stats.matches}',
                    ),
                    _StatCard(label: 'Spiele gewonnen', value: '${stats.wins}'),
                    _StatCard(
                      label: 'Spiele verloren',
                      value: '${stats.losses}',
                    ),
                    _StatCard(
                      label: 'Spiele unentschieden',
                      value: '${stats.draws}',
                    ),
                    _StatCard(
                      label: 'Siegquote Spiele',
                      value: '${stats.matchWinRate.toStringAsFixed(1)} %',
                    ),
                    _StatCard(
                      label: 'Turniere gespielt',
                      value: '${stats.tournaments}',
                    ),
                    _StatCard(
                      label: 'Turniere gewonnen',
                      value: '${stats.tournamentWins}',
                    ),
                    _StatCard(
                      label: 'Turniersiegquote',
                      value: '${stats.tournamentWinRate.toStringAsFixed(1)} %',
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
                      label: 'Legs gespielt',
                      value: '${stats.legsPlayed}',
                    ),
                    _StatCard(
                      label: 'Legs gewonnen',
                      value: '${stats.legsWon}',
                    ),
                    _StatCard(
                      label: 'Legs verloren',
                      value: '${stats.legsLost}',
                    ),
                    _StatCard(
                      label: 'Siegquote Legs',
                      value: '${stats.legWinRate.toStringAsFixed(1)} %',
                    ),
                    _StatCard(
                      label: 'Sets gespielt',
                      value: '${stats.setsPlayed}',
                    ),
                    _StatCard(
                      label: 'Sets gewonnen',
                      value: '${stats.setsWon}',
                    ),
                    _StatCard(
                      label: 'Sets verloren',
                      value: '${stats.setsLost}',
                    ),
                    _StatCard(
                      label: 'Siegquote Sets',
                      value: '${stats.setWinRate.toStringAsFixed(1)} %',
                    ),
                  ],
                ),
                PlayerPerformanceSection(performance: performance),
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
                      label: '170 (Big Fish)',
                      value:
                          '${performanceCounts[BestPerformanceType.bigFish170]}',
                    ),
                    _StatCard(
                      label: '171+ Aufnahmen',
                      value:
                          '${performanceCounts[BestPerformanceType.score171Plus]}',
                    ),
                    _StatCard(
                      label: '180+ Aufnahmen',
                      value:
                          '${performanceCounts[BestPerformanceType.score180]}',
                    ),
                    _StatCard(
                      label: 'Bullseye Finishes',
                      value:
                          '${performanceCounts[BestPerformanceType.bullseyeFinish]}',
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
                RankingAchievementSection(achievements: achievements),
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
