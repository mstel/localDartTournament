import 'package:flutter/material.dart';
import '../application/ranking_year_review_image_generator.dart';
import '../application/ranking_standings_image_generator.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/utils/png_image_export.dart';
import '../application/ranking_order.dart';
import '../domain/local_elo_calculator.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../application/local_ranking_elo_service.dart';
import '../application/local_ranking_series_service.dart';
import '../application/ranking_year_review_service.dart';
import '../domain/local_ranking.dart';
import '../domain/elo_tier.dart';
import 'widgets/elo_trajectory_chart.dart';

import '../../statistics/domain/best_performance.dart';
import '../../statistics/domain/local_statistics.dart';
import '../../statistics/presentation/local_player_statistics_page.dart';
import '../../statistics/presentation/widgets/structured_best_performances_view.dart';

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key, LocalAppDatabase? database})
    : _database = database;

  final LocalAppDatabase? _database;

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

enum _YearReviewMode { ranking, player }

class RankingYearReviewPage extends StatefulWidget {
  const RankingYearReviewPage({super.key});
  @override
  State<RankingYearReviewPage> createState() => _RankingYearReviewPageState();
}

class _RankingYearReviewPageState extends State<RankingYearReviewPage> {
  final _database = LocalAppDatabase();
  late final Future<List<LocalRanking>> _rankings = _database
      .loadLocalRankings();
  late final Future<List<PlayerProfile>> _players = _database
      .loadPlayerProfiles();
  _YearReviewMode _mode = _YearReviewMode.ranking;
  LocalRanking? _selectedRanking;
  PlayerProfile? _selectedPlayer;
  int? _year = DateTime.now().year;
  Future<RankingYearReview>? _rankingReview;
  Future<LocalPlayerStatistics>? _playerReview;
  bool _exporting = false;

  void _selectRanking(LocalRanking? ranking) {
    setState(() {
      _selectedRanking = ranking;
      _rankingReview = ranking == null
          ? null
          : const RankingYearReviewService().calculate(ranking, _year);
    });
  }

  void _selectPlayer(PlayerProfile? player) {
    setState(() {
      _selectedPlayer = player;
      _playerReview = player == null
          ? null
          : const LocalStatisticsService().forPlayers({player.id}, year: _year);
    });
  }

  void _setYear(int? year) {
    setState(() {
      _year = year;
      if (_selectedRanking != null) {
        _rankingReview = const RankingYearReviewService().calculate(
          _selectedRanking!,
          year,
        );
      }
      if (_selectedPlayer != null) {
        _playerReview = const LocalStatisticsService().forPlayers({
          _selectedPlayer!.id,
        }, year: year);
      }
    });
  }

  Future<void> _exportReview(
    LocalRanking ranking,
    RankingYearReview review,
    RankingReviewImageOrientation orientation,
  ) async {
    setState(() => _exporting = true);
    try {
      final colorScheme = Theme.of(context).colorScheme;
      const generator = RankingYearReviewImageGenerator();
      final pngBytes = await generator.generatePng(
        ranking: ranking,
        review: review,
        orientation: orientation,
        colorScheme: colorScheme,
      );
      if (!mounted) return;
      final cleanName = ranking.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName =
          'ranglisten-rueckblick-$cleanName-${review.year ?? "gesamt"}-${orientation.name}.png';
      await exportPngImage(
        context,
        bytes: pngBytes,
        fileName: fileName,
        successMessage: 'Jahresrückblick erfolgreich als Grafik exportiert.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grafikexport fehlgeschlagen: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List<int>.generate(
      currentYear - 1999,
      (index) => currentYear - index,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Jahresrückblick')),
      body: FutureBuilder<(List<LocalRanking>, List<PlayerProfile>)>(
        future: Future.wait([_rankings, _players]).then(
          (res) =>
              (res[0] as List<LocalRanking>, res[1] as List<PlayerProfile>),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (rankings, players) = snapshot.data!;
          final currentSelectedRanking =
              _selectedRanking ?? (rankings.isNotEmpty ? rankings.first : null);
          if (_selectedRanking == null && rankings.isNotEmpty) {
            _rankingReview ??= const RankingYearReviewService().calculate(
              rankings.first,
              _year,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedRanking == null) {
                _selectRanking(rankings.first);
              }
            });
          }

          return AdaptiveContentList(
            children: [
              Center(
                child: SegmentedButton<_YearReviewMode>(
                  segments: const [
                    ButtonSegment(
                      value: _YearReviewMode.ranking,
                      label: Text('Nach Rangliste'),
                      icon: Icon(Icons.leaderboard_outlined),
                    ),
                    ButtonSegment(
                      value: _YearReviewMode.player,
                      label: Text('Nach Spieler'),
                      icon: Icon(Icons.person_outline),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (set) {
                    setState(() => _mode = set.first);
                  },
                ),
              ),
              const SizedBox(height: 24),
              if (_mode == _YearReviewMode.ranking) ...[
                Text(
                  'Rückblick nach Rangliste',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<LocalRanking>(
                  initialValue: currentSelectedRanking,
                  decoration: const InputDecoration(
                    labelText: 'Rangliste auswählen',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.emoji_events_outlined),
                  ),
                  items: [
                    for (final ranking in rankings)
                      DropdownMenuItem(
                        value: ranking,
                        child: Text(ranking.name),
                      ),
                  ],
                  onChanged: _selectRanking,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _year,
                  menuMaxHeight: 320,
                  decoration: const InputDecoration(
                    labelText: 'Zeitraum',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Gesamter Zeitraum'),
                    ),
                    for (final year in years)
                      DropdownMenuItem<int?>(value: year, child: Text('$year')),
                  ],
                  onChanged: _setYear,
                ),
                if (rankings.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Lege zuerst eine Rangliste an und weise Spieler zu.',
                  ),
                ],
                if (_rankingReview != null && _selectedRanking != null) ...[
                  const SizedBox(height: 16),
                  FutureBuilder<RankingYearReview>(
                    future: _rankingReview,
                    builder: (context, data) {
                      if (!data.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final review = data.data!;
                      final rows = review.players.entries.toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            '${review.tournaments} Turniere · ${review.totalLegs} Legs · ${review.totalBestPerformances} Bestleistungen · ${review.total180} × 180+ · ${review.total170} × 170+ · ${review.totalShortLegs} Shortlegs · ${review.totalHighFinishes} High Finishes',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _exporting
                                    ? null
                                    : () => _exportReview(
                                        _selectedRanking!,
                                        review,
                                        RankingReviewImageOrientation.portrait,
                                      ),
                                icon: _exporting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.stay_current_portrait),
                                label: const Text('Hochformat exportieren'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _exporting
                                    ? null
                                    : () => _exportReview(
                                        _selectedRanking!,
                                        review,
                                        RankingReviewImageOrientation.landscape,
                                      ),
                                icon: const Icon(Icons.stay_current_landscape),
                                label: const Text('Querformat exportieren'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_year != null) ...[
                            Text(
                              'Turniere pro Monat',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            for (var i = 0; i < 12; i++)
                              _MonthBar(
                                month: i + 1,
                                count: review.monthlyTournaments[i],
                                max: review.monthlyTournaments.fold<int>(
                                  0,
                                  (a, b) => a > b ? a : b,
                                ),
                              ),
                          ] else ...[
                            Text(
                              'Turniere pro Jahr',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            if (review.yearlyTournaments.isEmpty)
                              const Text(
                                'Keine Turniere im gewählten Zeitraum vorhanden.',
                              )
                            else
                              for (final entry
                                  in review.yearlyTournaments.entries.toList()
                                    ..sort((a, b) => a.key.compareTo(b.key)))
                                _YearBar(
                                  year: entry.key,
                                  count: entry.value,
                                  max: review.yearlyTournaments.values
                                      .fold<int>(0, (a, b) => a > b ? a : b),
                                ),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            'Kategorien & Bestleistungen',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          _ReviewLeaders(
                            title: 'Meiste Teilnahmen',
                            rows: rows,
                            metric: (s) => s.participations,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste Turniersiege',
                            rows: rows,
                            metric: (s) => s.tournamentWins,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste gewonnene Legs',
                            rows: rows,
                            metric: (s) => s.legsWon,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste verlorene Legs',
                            rows: rows,
                            metric: (s) => s.legsLost,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste Bestleistungen',
                            rows: rows,
                            metric: (s) => s.bestPerformances,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste 180+',
                            rows: rows,
                            metric: (s) => s.scores180,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste 170+',
                            rows: rows,
                            metric: (s) => s.scores170,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste Shortlegs',
                            rows: rows,
                            metric: (s) => s.shortLegs,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                          _ReviewLeaders(
                            title: 'Meiste High Finishes',
                            rows: rows,
                            metric: (s) => s.highFinishes,
                            profileIds: review.profileIds,
                            year: _year,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ] else ...[
                Text(
                  'Rückblick nach Spieler',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<PlayerProfile>(
                  initialValue: _selectedPlayer,
                  decoration: const InputDecoration(
                    labelText: 'Spieler auswählen',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_search_outlined),
                  ),
                  items: [
                    for (final player in players)
                      DropdownMenuItem(
                        value: player,
                        child: Text(player.displayName),
                      ),
                  ],
                  onChanged: _selectPlayer,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _year,
                  menuMaxHeight: 320,
                  decoration: const InputDecoration(
                    labelText: 'Zeitraum',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Gesamter Zeitraum'),
                    ),
                    for (final year in years)
                      DropdownMenuItem<int?>(value: year, child: Text('$year')),
                  ],
                  onChanged: _setYear,
                ),
                if (players.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Noch keine Spielerprofile vorhanden.'),
                ],
                if (_playerReview != null && _selectedPlayer != null) ...[
                  const SizedBox(height: 20),
                  FutureBuilder<LocalPlayerStatistics>(
                    future: _playerReview,
                    builder: (context, data) {
                      if (!data.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final stats = data.data!;
                      final p = _selectedPlayer!;
                      final performanceCounts = {
                        for (final type in BestPerformanceType.values)
                          type: stats.bestPerformances
                              .where((item) => item.type == type)
                              .length,
                      };
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p.displayName} · ${_year == null ? "Gesamter Zeitraum" : "$_year"}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _StatMiniCard(
                                label:
                                    'Turniere ${_year == null ? "gesamt" : "in $_year"}',
                                value: '${stats.tournaments}',
                              ),
                              _StatMiniCard(
                                label: 'Spiele',
                                value: '${stats.matches}',
                              ),
                              _StatMiniCard(
                                label: 'Siege / Niederlagen',
                                value: '${stats.wins} / ${stats.losses}',
                              ),
                              _StatMiniCard(
                                label: 'Siegquote',
                                value:
                                    '${stats.matchWinRate.toStringAsFixed(1)} %',
                              ),
                              _StatMiniCard(
                                label: 'Legs (gew./verl.)',
                                value: '${stats.legsWon} / ${stats.legsLost}',
                              ),
                              _StatMiniCard(
                                label: 'Leg-Siegquote',
                                value:
                                    '${stats.legWinRate.toStringAsFixed(1)} %',
                              ),
                              _StatMiniCard(
                                label: '180+ Aufnahmen',
                                value:
                                    '${performanceCounts[BestPerformanceType.score180]}',
                              ),
                              _StatMiniCard(
                                label: 'High Finishes (100+)',
                                value:
                                    '${performanceCounts[BestPerformanceType.highFinish]}',
                              ),
                              _StatMiniCard(
                                label: 'Shortlegs (≤18)',
                                value:
                                    '${performanceCounts[BestPerformanceType.shortLeg]}',
                              ),
                            ],
                          ),
                          StructuredBestPerformancesView(
                            bestPerformances: stats.bestPerformances,
                          ),
                          if (stats.tournaments == 0 && stats.matches == 0) ...[
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Keine Turnierspiele oder Bestleistungen für ${p.displayName} im gewählten Zeitraum erfasst.',
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatMiniCard extends StatelessWidget {
  const _StatMiniCard({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _ReviewLeaders extends StatefulWidget {
  const _ReviewLeaders({
    required this.title,
    required this.rows,
    required this.metric,
    required this.profileIds,
    this.year,
  });
  final String title;
  final List<MapEntry<String, RankingYearPlayerStats>> rows;
  final int Function(RankingYearPlayerStats) metric;
  final Map<String, String> profileIds;
  final int? year;

  @override
  State<_ReviewLeaders> createState() => _ReviewLeadersState();
}

class _ReviewLeadersState extends State<_ReviewLeaders> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranked = widget.rows.where((r) => widget.metric(r.value) > 0).toList()
      ..sort(
        (a, b) => widget.metric(b.value).compareTo(widget.metric(a.value)),
      );
    final visible = ranked.take(_showAll ? ranked.length : 5).toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: ExpansionTile(
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(
          50,
        ),
        collapsedBackgroundColor: theme.colorScheme.surface,
        title: Text(
          widget.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: ranked.isEmpty
            ? Text('Keine Daten', style: TextStyle(color: theme.hintColor))
            : Row(
                children: [
                  Icon(
                    Icons.emoji_events,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${ranked.first.key} (${widget.metric(ranked.first.value)})',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(30),
            child: Column(
              children: [
                const Divider(height: 1),
                for (var i = 0; i < visible.length; i++) ...[
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: i == 0
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHigh,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: i == 0
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    title: Text(
                      ranked[i].key,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.metric(ranked[i].value)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right, size: 16),
                      ],
                    ),
                    onTap: () {
                      final pId = widget.profileIds[ranked[i].key];
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LocalPlayerStatisticsPage(
                            name: ranked[i].key,
                            profileIds: pId != null ? {pId} : const <String>{},
                            year: widget.year,
                          ),
                        ),
                      );
                    },
                  ),
                  if (i < visible.length - 1)
                    Divider(
                      height: 1,
                      indent: 48,
                      color: theme.colorScheme.outlineVariant.withAlpha(40),
                    ),
                ],
                if (ranked.length > 5)
                  TextButton(
                    key: ValueKey('year-review-show-all-${widget.title}'),
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(
                      _showAll ? 'Weniger anzeigen' : 'Alle anzeigen',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.count,
    required this.max,
  });
  final int month, count, max;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 38, child: Text('$month.')),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max == 0 ? 0 : count / max,
              minHeight: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 28, child: Text('$count')),
      ],
    ),
  );
}

class _YearBar extends StatelessWidget {
  const _YearBar({required this.year, required this.count, required this.max});
  final int year, count, max;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 44, child: Text('$year')),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max == 0 ? 0 : count / max,
              minHeight: 12,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 32,
          child: Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

class _RankingsPageState extends State<RankingsPage> {
  late final LocalAppDatabase _database =
      widget._database ?? LocalAppDatabase();
  late Future<List<LocalRanking>> _rankings = _database.loadLocalRankings();
  RankingSortMode _sortMode = RankingSortMode.alphabetical;
  bool _saving = false;

  Future<void> _create() async {
    final ranking = await showDialog<LocalRanking>(
      context: context,
      builder: (_) => const _RankingEditorDialog(),
    );
    if (ranking == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _database.saveLocalRanking(ranking);
      if (mounted) setState(() => _rankings = _database.loadLocalRankings());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rangliste konnte nicht gespeichert werden: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(LocalRanking ranking) async {
    final updated = await showDialog<LocalRanking>(
      context: context,
      builder: (_) => _RankingEditorDialog(initial: ranking),
    );
    if (updated == null) return;
    await _database.saveLocalRanking(updated);
    if (mounted) setState(() => _rankings = _database.loadLocalRankings());
  }

  Future<void> _moveRanking(
    List<LocalRanking> orderedRankings,
    int index,
    int offset,
  ) async {
    final targetIndex = index + offset;
    if (targetIndex < 0 || targetIndex >= orderedRankings.length) return;
    final reordered = [...orderedRankings];
    final moved = reordered.removeAt(index);
    reordered.insert(targetIndex, moved);
    setState(() => _saving = true);
    try {
      await _database.saveLocalRankingOrder(
        reordered.map((ranking) => ranking.id).toList(),
      );
      if (mounted) setState(() => _rankings = _database.loadLocalRankings());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reihenfolge konnte nicht gespeichert werden: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assignTournaments(LocalRanking ranking) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _RankingTournamentsPage(ranking: ranking),
      ),
    );
  }

  Future<void> _assignPlayers(LocalRanking ranking) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _RankingPlayersPage(database: _database, ranking: ranking),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _rankings = _database.loadLocalRankings());
    }
  }

  Future<void> _openRanking(LocalRanking ranking) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ranking.type == RankingType.elo
            ? LocalRankingStandingsPage(database: _database, ranking: ranking)
            : LocalRankingSeriesStandingsPage(
                database: _database,
                ranking: ranking,
              ),
      ),
    );
  }

  Future<void> _delete(LocalRanking ranking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rangliste löschen?'),
        content: Text(
          '„${ranking.name}“ und ihre Spielerzuweisungen werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _database.deleteLocalRanking(ranking.id);
    if (mounted) setState(() => _rankings = _database.loadLocalRankings());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ranglisten')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _saving ? null : _create,
      icon: const Icon(Icons.add),
      label: const Text('Rangliste erstellen'),
    ),
    body: SafeArea(
      child: FutureBuilder<List<LocalRanking>>(
        future: _rankings,
        builder: (context, snapshot) {
          final rankings = sortRankings(
            snapshot.data ?? const <LocalRanking>[],
            _sortMode,
          );
          return AdaptiveContentList(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            children: [
              Text(
                'Ranglisten verwalten',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Ranglisten werden lokal geführt und im konto-bezogenen Supabase-Datenstand gesichert.',
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(),
              if (snapshot.hasError)
                const Text('Ranglisten konnten nicht geladen werden.'),
              DropdownButtonFormField<RankingSortMode>(
                initialValue: _sortMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sortierung',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final mode in RankingSortMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: (mode) {
                  if (mode != null) setState(() => _sortMode = mode);
                },
              ),
              if (snapshot.hasData && snapshot.data!.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Noch keine Ranglisten angelegt.'),
                  ),
                ),
              for (var index = 0; index < rankings.length; index++)
                Card(
                  child: ListTile(
                    key: ValueKey('ranking-${rankings[index].id}'),
                    leading: Icon(
                      rankings[index].type == RankingType.elo
                          ? Icons.trending_up
                          : Icons.emoji_events_outlined,
                    ),
                    title: Text(rankings[index].name),
                    subtitle: Text(
                      rankings[index].type == RankingType.elo
                          ? 'Klassische Elo-Wertung · Start ${rankings[index].startRating}'
                          : 'Turnierserie · Teilnahme, Sets, Platzierungen und Bestleistungen',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_sortMode == RankingSortMode.custom) ...[
                          IconButton(
                            tooltip: 'Nach oben verschieben',
                            onPressed: _saving || index == 0
                                ? null
                                : () => _moveRanking(rankings, index, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: 'Nach unten verschieben',
                            onPressed: _saving || index == rankings.length - 1
                                ? null
                                : () => _moveRanking(rankings, index, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                        ],
                        // Fix 4.2: Einstellungen direkt zugänglich (statt nur im Menü)
                        IconButton(
                          tooltip: 'Einstellungen',
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => _edit(rankings[index]),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Weitere Aktionen',
                          onSelected: (value) {
                            if (value == 'players') {
                              _assignPlayers(rankings[index]);
                            }
                            if (value == 'tournaments') {
                              _assignTournaments(rankings[index]);
                            }
                            if (value == 'table') {
                              _openRanking(rankings[index]);
                            }
                            if (value == 'delete') {
                              _delete(rankings[index]);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'players',
                              child: Text('Spieler zuweisen'),
                            ),
                            PopupMenuItem(
                              value: 'tournaments',
                              child: Text('Turniere zuweisen'),
                            ),
                            PopupMenuItem(
                              value: 'table',
                              child: Text('Ranglistenstand öffnen'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Rangliste löschen'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => _openRanking(rankings[index]),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _RankingEditorDialog extends StatefulWidget {
  const _RankingEditorDialog({this.initial});
  final LocalRanking? initial;

  @override
  State<_RankingEditorDialog> createState() => _RankingEditorDialogState();
}

class _RankingEditorDialogState extends State<_RankingEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  RankingType _type = RankingType.elo;
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _dateError;
  final Map<String, TextEditingController> _numbers = {
    'Startwertung': TextEditingController(text: '1000'),
    'K-Faktor Neu': TextEditingController(text: '25'),
    'K-Faktor Normal': TextEditingController(text: '15'),
    'K-Faktor Pro': TextEditingController(text: '10'),
    'Spiele bis Normal': TextEditingController(text: '10'),
    'Pro-Spieler ab Wertung': TextEditingController(text: '2400'),
    'Punkte Teilnahme': TextEditingController(text: '1'),
    'Punkte je gewonnenem Set': TextEditingController(text: '1'),
    'Punkte Platz 1': TextEditingController(text: '10'),
    'Punkte Platz 2': TextEditingController(text: '6'),
    'Punkte Platz 3': TextEditingController(text: '3'),
    'Punkte je Bestleistung': TextEditingController(text: '1'),
  };
  bool _enableTiers = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _name.text = initial.name;
    _type = initial.type;
    _enableTiers = initial.enableTiers;
    _fromDate =
        initial.validFromDate ??
        (initial.validFromYear == null
            ? null
            : DateTime(initial.validFromYear!, 1, 1));
    _toDate =
        initial.validToDate ??
        (initial.validToYear == null
            ? null
            : DateTime(initial.validToYear!, 12, 31));
    for (final entry in _numbers.entries) {
      final values = <String, int>{
        'Startwertung': initial.startRating,
        'K-Faktor Neu': initial.newPlayerK,
        'K-Faktor Normal': initial.normalPlayerK,
        'K-Faktor Pro': initial.proPlayerK,
        'Spiele bis Normal': initial.matchesBeforeNormal,
        'Pro-Spieler ab Wertung': initial.proRatingThreshold,
        'Punkte Teilnahme': initial.participationPoints,
        'Punkte je gewonnenem Set': initial.setWinPoints,
        'Punkte Platz 1': initial.firstPlacePoints,
        'Punkte Platz 2': initial.secondPlacePoints,
        'Punkte Platz 3': initial.thirdPlacePoints,
        'Punkte je Bestleistung': initial.bestPerformancePoints,
      };
      entry.value.text = '${values[entry.key]}';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int _value(String label) => int.tryParse(_numbers[label]!.text.trim()) ?? 0;

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime(2100),
      helpText: start ? 'Gültig ab Datum' : 'Gültig bis Datum',
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
      if (_fromDate != null &&
          _toDate != null &&
          _toDate!.isBefore(_fromDate!)) {
        _dateError = 'Das Enddatum darf nicht vor dem Startdatum liegen.';
      } else {
        _dateError = null;
      }
    });
  }

  void _submit() {
    setState(() {
      if (_fromDate != null &&
          _toDate != null &&
          _toDate!.isBefore(_fromDate!)) {
        _dateError = 'Das Enddatum darf nicht vor dem Startdatum liegen.';
      } else {
        _dateError = null;
      }
    });
    if (!_formKey.currentState!.validate() || _dateError != null) return;

    Navigator.pop(
      context,
      LocalRanking(
        id:
            widget.initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        type: _type,
        startRating: _value('Startwertung'),
        newPlayerK: _value('K-Faktor Neu'),
        normalPlayerK: _value('K-Faktor Normal'),
        proPlayerK: _value('K-Faktor Pro'),
        matchesBeforeNormal: _value('Spiele bis Normal'),
        proRatingThreshold: _value('Pro-Spieler ab Wertung'),
        participationPoints: _value('Punkte Teilnahme'),
        setWinPoints: _value('Punkte je gewonnenem Set'),
        firstPlacePoints: _value('Punkte Platz 1'),
        secondPlacePoints: _value('Punkte Platz 2'),
        thirdPlacePoints: _value('Punkte Platz 3'),
        bestPerformancePoints: _value('Punkte je Bestleistung'),
        validFromYear: _fromDate?.year,
        validToYear: _toDate?.year,
        validFromDate: _fromDate,
        validToDate: _toDate,
        enableTiers: _enableTiers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Rangliste erstellen' : 'Rangliste bearbeiten',
    ),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_dateError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _dateError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TextFormField(
              controller: _name,
              autofocus: widget.initial == null,
              maxLength: 80,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              decoration: const InputDecoration(
                labelText: 'Name der Rangliste',
                hintText: 'z. B. DC Unzenberg 2026',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Bitte einen Namen eingeben.'
                  : null,
            ),
            const SizedBox(height: 20),
            Text(
              'Gültigkeitszeitraum (optional)',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Ohne Angabe gelten alle Turniere.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(start: true),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _fromDate == null
                        ? 'Startdatum wählen'
                        : 'Ab ${_fromDate!.day.toString().padLeft(2, '0')}.${_fromDate!.month.toString().padLeft(2, '0')}.${_fromDate!.year}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(start: false),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _toDate == null
                        ? 'Enddatum wählen'
                        : 'Bis ${_toDate!.day.toString().padLeft(2, '0')}.${_toDate!.month.toString().padLeft(2, '0')}.${_toDate!.year}',
                  ),
                ),
                if (_fromDate != null || _toDate != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _fromDate = null;
                      _toDate = null;
                      _dateError = null;
                    }),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Zurücksetzen'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Wertungsmodus',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RankingType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Typ',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: RankingType.elo,
                  child: Text('Klassische Elo-Rangliste'),
                ),
                DropdownMenuItem(
                  value: RankingType.series,
                  child: Text('Turnierserie mit Punkten'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _type = value ?? RankingType.elo),
            ),
            const SizedBox(height: 20),
            Text(
              _type == RankingType.elo ? 'Elo-Parameter' : 'Punkte-Parameter',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            for (final entry in _numbers.entries)
              if (_type == RankingType.elo
                  ? entry.key.startsWith('Start') ||
                        entry.key.startsWith('K-Faktor') ||
                        entry.key.startsWith('Spiele') ||
                        entry.key.startsWith('Pro-Spieler')
                  : entry.key.startsWith('Punkte'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    controller: entry.value,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: entry.key,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (value) =>
                        int.tryParse((value ?? '').trim()) == null
                        ? 'Bitte eine ganze Zahl eingeben.'
                        : null,
                  ),
                ),
            if (_type == RankingType.elo) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auf- & Abstiegssystem (Elo-Tiers)'),
                subtitle: const Text(
                  'Spieler nach Elo in Ligen/Tiers einordnen:\n'
                  '💎 Diamant (≥1200) · 🎖️ Platin (≥1100) · 🏆 Gold (≥1000) · 🛡️ Silber (≥900) · 🥉 Bronze (<900)',
                ),
                value: _enableTiers,
                onChanged: (val) => setState(() => _enableTiers = val),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(
          widget.initial == null ? 'Rangliste erstellen' : 'Speichern',
        ),
      ),
    ],
  );
}

class _RankingTournamentsPage extends StatefulWidget {
  const _RankingTournamentsPage({required this.ranking});
  final LocalRanking ranking;
  @override
  State<_RankingTournamentsPage> createState() =>
      _RankingTournamentsPageState();
}

class _RankingTournamentsPageState extends State<_RankingTournamentsPage> {
  final _storage = TournamentStorage();
  // ignore: prefer_final_fields
  late final Future<List<CreatedTournament>> _future = _storage
      .loadTournaments();
  final Set<String> _selected = {};
  bool _ready = false, _saving = false;

  Future<void> _save(List<CreatedTournament> tournaments) async {
    setState(() => _saving = true);
    try {
      for (final tournament in tournaments) {
        final ids = tournament.rankingIds.toSet();
        if (_selected.contains(tournament.id)) {
          ids.add(widget.ranking.id);
        } else {
          ids.remove(widget.ranking.id);
        }
        await _storage.saveTournament(
          CreatedTournament.fromJson({
            ...tournament.toJson(),
            'countsForRanking': ids.isNotEmpty,
            'rankingIds': ids.toList(),
          }),
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Turniere · ${widget.ranking.name}'),
      actions: [
        TextButton.icon(
          onPressed: _saving
              ? null
              : () async {
                  final data = await _future;
                  if (mounted) _save(data);
                },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Speichern'),
        ),
      ],
    ),
    body: FutureBuilder<List<CreatedTournament>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final tournaments = snapshot.data!;
        if (!_ready) {
          for (final t in tournaments) {
            if (t.countsForRanking &&
                t.rankingIds.contains(widget.ranking.id)) {
              _selected.add(t.id);
            }
          }
          _ready = true;
        }
        return AdaptiveContentList(
          children: [
            Text(
              'Ranglistenturniere zuweisen',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Bei Elo zählen nur Begegnungen, bei denen beide zugewiesenen Spieler Mitglieder dieser Rangliste sind.',
            ),
            if (tournaments.isEmpty)
              const Text('Noch keine Turniere vorhanden.'),
            for (final tournament in tournaments)
              CheckboxListTile(
                value: _selected.contains(tournament.id),
                title: Text(tournament.name),
                subtitle: Text(
                  (tournament.finishedAt ?? tournament.createdAt)
                      .toLocal()
                      .toString()
                      .split(' ')
                      .first,
                ),
                onChanged: (checked) => setState(() {
                  checked == true
                      ? _selected.add(tournament.id)
                      : _selected.remove(tournament.id);
                }),
              ),
          ],
        );
      },
    ),
  );
}

class _RankingPlayersPage extends StatefulWidget {
  const _RankingPlayersPage({required this.database, required this.ranking});
  final LocalAppDatabase database;
  final LocalRanking ranking;

  @override
  State<_RankingPlayersPage> createState() => _RankingPlayersPageState();
}

class _RankingPlayersPageState extends State<_RankingPlayersPage> {
  // ignore: prefer_final_fields
  late Future<(List<PlayerProfile>, List<String>)> _load = _loadData();
  final Set<String> _selected = {};
  bool _initialized = false;
  bool _saving = false;

  Future<(List<PlayerProfile>, List<String>)> _loadData() async => (
    await widget.database.loadPlayerProfiles(),
    await widget.database.loadRankingPlayerIds(widget.ranking.id),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.database.setRankingPlayers(widget.ranking.id, _selected);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.ranking.name),
      actions: [
        TextButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Speichern'),
        ),
      ],
    ),
    body: FutureBuilder<(List<PlayerProfile>, List<String>)>(
      future: _load,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (players, assigned) = snapshot.data!;
        if (!_initialized) {
          _selected.addAll(assigned);
          _initialized = true;
        }
        return AdaptiveContentList(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Spieler zuweisen',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Nur zugewiesene Spieler zählen in dieser Rangliste. Bei Elo werden Begegnungen nur gewertet, wenn beide Spieler Mitglied sind.',
            ),
            if (players.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('Lege zuerst Spieler im Hauptmenü an.'),
                ),
              ),
            for (final player in players)
              CheckboxListTile(
                value: _selected.contains(player.id),
                title: Text(player.displayName),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selected.add(player.id);
                  } else {
                    _selected.remove(player.id);
                  }
                }),
              ),
          ],
        );
      },
    ),
  );
}

class LocalRankingStandingsPage extends StatefulWidget {
  const LocalRankingStandingsPage({
    super.key,
    required this.database,
    required this.ranking,
  });

  final LocalAppDatabase database;
  final LocalRanking ranking;

  @override
  State<LocalRankingStandingsPage> createState() =>
      _LocalRankingStandingsPageState();
}

class _LocalRankingStandingsPageState extends State<LocalRankingStandingsPage> {
  late Future<LocalEloSnapshot> _snapshot = _calculate();
  bool _exporting = false;

  Future<LocalEloSnapshot> _calculate() => LocalRankingEloService(
    database: widget.database,
  ).calculate(widget.ranking);

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final colorScheme = Theme.of(context).colorScheme;
      final snapshot = await _snapshot;
      if (!mounted) return;
      final bytes = await const RankingStandingsImageGenerator().generatePng(
        ranking: widget.ranking,
        snapshot: snapshot,
        colorScheme: colorScheme,
      );
      if (!mounted) return;
      await exportPngImage(
        context,
        bytes: bytes,
        fileName: 'rangliste-${widget.ranking.id}.png',
        successMessage: 'Ranglisten-Grafik erfolgreich exportiert.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ranglisten-Grafik fehlgeschlagen: $error'),
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
      title: Text(widget.ranking.name),
      actions: [
        IconButton(
          tooltip: 'Ranglisten-Grafik hochkant exportieren',
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
        ),
        IconButton(
          tooltip: 'Rangliste aktualisieren',
          onPressed: () => setState(() => _snapshot = _calculate()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<LocalEloSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) => AdaptiveContentList(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Aktueller Stand',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(),
          if (snapshot.hasError)
            Text(
              'Ranglistenstand konnte nicht berechnet werden: ${snapshot.error}',
            ),
          if (snapshot.data case final entries?) ...[
            const Text(
              'Elo wird chronologisch aus abgeschlossenen Turnierspielen berechnet. Nur zugewiesene Spieler und für diese Rangliste markierte Turniere zählen.',
            ),
            for (var i = 0; i < entries.entries.length; i++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Row(
                    children: [
                      Flexible(child: Text(entries.entries[i].name)),
                      if (widget.ranking.enableTiers) ...[
                        const SizedBox(width: 8),
                        _TierBadge(
                          tier: EloTier.fromElo(entries.entries[i].rating),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${entries.entries[i].matches} gewertete Matches · ${entries.entries[i].wins} Siege · ${entries.entries[i].losses} Niederlagen',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entries.entries[i].rating} Elo',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                  onTap: () {
                    final player = entries.entries[i];
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlayerEloHistoryPage(
                          player: player,
                          rankingName: widget.ranking.name,
                          history: entries.history[player.id] ?? const [],
                          enableTiers: widget.ranking.enableTiers,
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (entries.entries.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('Noch keine gewerteten Ergebnisse.'),
                  subtitle: Text(
                    'Spieler zuweisen und ein Turnier für diese Rangliste markieren.',
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

class LocalRankingSeriesStandingsPage extends StatefulWidget {
  const LocalRankingSeriesStandingsPage({
    super.key,
    required this.database,
    required this.ranking,
  });

  final LocalAppDatabase database;
  final LocalRanking ranking;

  @override
  State<LocalRankingSeriesStandingsPage> createState() =>
      _LocalRankingSeriesStandingsPageState();
}

class _LocalRankingSeriesStandingsPageState
    extends State<LocalRankingSeriesStandingsPage> {
  late Future<List<LocalSeriesEntry>> _entries = _calculate();
  bool _exporting = false;

  Future<List<LocalSeriesEntry>> _calculate() => LocalRankingSeriesService(
    database: widget.database,
  ).calculate(widget.ranking);

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final colorScheme = Theme.of(context).colorScheme;
      final entries = await _entries;
      if (!mounted) return;
      final rows = [
        for (var index = 0; index < entries.length; index++)
          RankingStandingImageRow(
            name: '${index + 1}. ${entries[index].player.displayName}',
            value: '${entries[index].points} Punkte',
            details:
                '${entries[index].participations} Teilnahmen · ${entries[index].setsWon} Sets · ${entries[index].bestPerformances} Bestleistungen',
          ),
      ];
      final bytes = await const RankingStandingsImageGenerator().generateRows(
        title: widget.ranking.name,
        subtitle: 'Ranglistenstand · ${entries.length} Spieler',
        rows: rows,
        colorScheme: colorScheme,
      );
      if (!mounted) return;
      await exportPngImage(
        context,
        bytes: bytes,
        fileName: 'rangliste-${widget.ranking.id}.png',
        successMessage: 'Ranglisten-Grafik erfolgreich exportiert.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ranglisten-Grafik fehlgeschlagen: $error'),
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
      title: Text(widget.ranking.name),
      actions: [
        IconButton(
          tooltip: 'Ranglisten-Grafik hochkant exportieren',
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
        ),
        IconButton(
          tooltip: 'Rangliste aktualisieren',
          onPressed: () => setState(() => _entries = _calculate()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<LocalSeriesEntry>>(
      future: _entries,
      builder: (context, snapshot) => AdaptiveContentList(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Serienwertung',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            'Teilnahme: ${widget.ranking.participationPoints} P. · gewonnenes Set: ${widget.ranking.setWinPoints} P. · Platz 1/2/3: ${widget.ranking.firstPlacePoints}/${widget.ranking.secondPlacePoints}/${widget.ranking.thirdPlacePoints} P.',
          ),
          if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(),
          if (snapshot.hasError)
            Text(
              'Serienwertung konnte nicht berechnet werden: ${snapshot.error}',
            ),
          if (snapshot.hasData) ...[
            const Text(
              'Erfasste Bestleistungen zählen mit den eingestellten Punkten zur Serienwertung.',
            ),
            for (var i = 0; i < snapshot.data!.length; i++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(snapshot.data![i].player.displayName),
                  subtitle: Text(
                    '${snapshot.data![i].participations} Teilnahmen · ${snapshot.data![i].setsWon} gewonnene Sets · ${snapshot.data![i].bestPerformances} Bestleistungen · Plätze 1/2/3: ${snapshot.data![i].firstPlaces}/${snapshot.data![i].secondPlaces}/${snapshot.data![i].thirdPlaces}',
                  ),
                  trailing: Text(
                    '${snapshot.data![i].points} P.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

class PlayerEloHistoryPage extends StatelessWidget {
  const PlayerEloHistoryPage({
    super.key,
    required this.player,
    required this.rankingName,
    required this.history,
    this.enableTiers = false,
  });

  final LocalEloPlayer player;
  final String rankingName;
  final List<LocalEloHistoryItem> history;
  final bool enableTiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final orderedHistory = history.toList()
      ..sort((a, b) {
        final time = a.playedAt.compareTo(b.playedAt);
        if (time != 0) return time;
        final tournament = a.tournamentId.compareTo(b.tournamentId);
        return tournament != 0
            ? tournament
            : a.matchIndex.compareTo(b.matchIndex);
      });
    final tournamentGroups = <_TournamentEloGroup>[];
    for (final item in orderedHistory) {
      if (tournamentGroups.isNotEmpty &&
          tournamentGroups.last.tournamentId == item.tournamentId) {
        tournamentGroups.last.matches.add(item);
      } else {
        final group = _TournamentEloGroup(
          tournamentId: item.tournamentId,
          tournamentName: item.tournamentName,
          playedAt: item.playedAt,
        );
        group.matches.add(item);
        tournamentGroups.add(group);
      }
    }
    final reversedGroups = tournamentGroups.reversed.toList();
    final trajectory = _eloTrajectory(history);

    return Scaffold(
      appBar: AppBar(title: Text('Elo-Verlauf: ${player.name}')),
      body: SafeArea(
        child: AdaptiveContentList(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rangliste: $rankingName',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _StatChip(
                          label: 'Aktuelle Wertung',
                          value: '${player.rating} Elo',
                          icon: Icons.trending_up,
                        ),
                        if (enableTiers)
                          _StatChip(
                            label: 'Liga / Tier',
                            value: EloTier.fromElo(player.rating).name,
                            icon: EloTier.fromElo(player.rating).icon,
                          ),
                        _StatChip(
                          label: 'Matches',
                          value:
                              '${player.matches} (${player.wins}S / ${player.losses}N)',
                          icon: Icons.sports_score,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (trajectory.length > 1) ...[
              Text(
                'Elo-Entwicklung pro Turnier',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EloTrajectoryChart(
                        points: trajectory,
                        color: colorScheme.primary,
                        gridColor: colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(trajectory.first.tournamentName),
                          Text(trajectory.last.tournamentName),
                          Text(
                            '${trajectory.first.rating} → ${trajectory.last.rating} Elo',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Turnier- und Spielverlauf',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (reversedGroups.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Noch keine gewerteten Begegnungen in dieser Rangliste.',
                  ),
                ),
              ),
            for (final group in reversedGroups)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  key: PageStorageKey('elo-group-${group.tournamentId}'),
                  leading: CircleAvatar(
                    backgroundColor: group.totalDelta > 0
                        ? Colors.green.shade100
                        : group.totalDelta < 0
                        ? Colors.red.shade100
                        : colorScheme.surfaceContainerHighest,
                    child: Icon(
                      group.totalDelta > 0
                          ? Icons.arrow_upward
                          : group.totalDelta < 0
                          ? Icons.arrow_downward
                          : Icons.remove,
                      color: group.totalDelta > 0
                          ? Colors.green.shade800
                          : group.totalDelta < 0
                          ? Colors.red.shade800
                          : colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    group.tournamentName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${group.playedAt.day}.${group.playedAt.month}.${group.playedAt.year} · ${group.wins} Siege · ${group.losses} Niederlagen${group.draws > 0 ? " · ${group.draws} Unentschieden" : ""}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: group.totalDelta > 0
                          ? Colors.green.shade100
                          : group.totalDelta < 0
                          ? Colors.red.shade100
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${group.totalDelta >= 0 ? "+" : ""}${group.totalDelta} Elo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: group.totalDelta > 0
                            ? Colors.green.shade900
                            : group.totalDelta < 0
                            ? Colors.red.shade900
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  children: [
                    const Divider(height: 1),
                    for (final match in group.matches)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          match.delta > 0
                              ? Icons.check_circle_outline
                              : match.delta < 0
                              ? Icons.highlight_off
                              : Icons.remove_circle_outline,
                          color: match.delta > 0
                              ? Colors.green
                              : match.delta < 0
                              ? Colors.red
                              : Colors.grey,
                          size: 20,
                        ),
                        title: Text('vs. ${match.opponentName}'),
                        subtitle: Text(
                          'Ergebnis: ${match.score} · Elo danach: ${match.ratingAfter}',
                        ),
                        trailing: Text(
                          '${match.delta >= 0 ? "+" : ""}${match.delta}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: match.delta > 0
                                ? Colors.green.shade800
                                : match.delta < 0
                                ? Colors.red.shade800
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<EloTrajectoryPoint> _eloTrajectory(List<LocalEloHistoryItem> history) {
  if (history.isEmpty) return const [];
  final ordered = history.toList()
    ..sort((a, b) {
      final time = a.playedAt.compareTo(b.playedAt);
      if (time != 0) return time;
      final tournament = a.tournamentId.compareTo(b.tournamentId);
      return tournament != 0
          ? tournament
          : a.matchIndex.compareTo(b.matchIndex);
    });
  final byTournament = <String, List<LocalEloHistoryItem>>{};
  for (final item in ordered) {
    (byTournament[item.tournamentId] ??= []).add(item);
  }
  final tournaments = byTournament.values.toList()
    ..sort((a, b) {
      final time = a.last.playedAt.compareTo(b.last.playedAt);
      return time != 0
          ? time
          : a.last.tournamentId.compareTo(b.last.tournamentId);
    });
  final first = ordered.first;
  return [
    EloTrajectoryPoint(
      playedAt: first.playedAt,
      tournamentName: 'Start',
      rating: first.ratingAfter - first.delta,
      delta: 0,
    ),
    for (final tournament in tournaments)
      EloTrajectoryPoint(
        playedAt: tournament.last.playedAt,
        tournamentName: tournament.last.tournamentName,
        rating: tournament.last.ratingAfter,
        delta: tournament.fold<int>(0, (sum, item) => sum + item.delta),
      ),
  ];
}

class _TournamentEloGroup {
  _TournamentEloGroup({
    required this.tournamentId,
    required this.tournamentName,
    required this.playedAt,
  });

  final String tournamentId;
  final String tournamentName;
  final DateTime playedAt;
  final List<LocalEloHistoryItem> matches = [];

  int get totalDelta => matches.fold<int>(0, (sum, m) => sum + m.delta);
  int get wins => matches.where((m) => m.delta > 0).length;
  int get losses => matches.where((m) => m.delta < 0).length;
  int get draws => matches.where((m) => m.delta == 0).length;
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});
  final EloTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.15),
        border: Border.all(color: tier.color, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tier.icon, size: 13, color: tier.color),
          const SizedBox(width: 4),
          Text(
            tier.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: tier.color,
            ),
          ),
        ],
      ),
    );
  }
}
