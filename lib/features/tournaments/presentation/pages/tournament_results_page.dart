import '../../../../shared/widgets/sport_menu.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime, TournamentRunPage;
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import '../../domain/engines/placement_engine.dart';
import '../../domain/engines/group_standings_engine.dart';
import '../../domain/knockout_round_names.dart';
import 'package:flutter/material.dart';

import '../../domain/tournament_models.dart';
import '../../data/app_database.dart';
import '../../data/tournament_storage.dart';
import '../../../league/domain/league_match.dart';
import '../../../rankings/application/tournament_match_elo_service.dart';
import '../../../rankings/domain/local_elo_calculator.dart';
import '../../../statistics/domain/best_performance.dart';
import '../widgets/run/best_performance_editor.dart';
import 'challonge_archive_page.dart';
import '../../application/tournament_timing.dart';
import '../../application/tournament_run_controller.dart';
import '../../application/tournament_duration_range.dart';
import '../../application/tournament_completion_image_generator.dart';
import '../widgets/results/tournament_ranking_assignment.dart';
import '../widgets/results/tournament_ranking_changes_section.dart';
import '../widgets/tournament_export_dialog.dart';

class TournamentResultsPage extends StatefulWidget {
  const TournamentResultsPage({
    super.key,
    required this.tournament,
    this.database,
    this.storage,
  });

  final CreatedTournament tournament;
  final LocalAppDatabase? database;
  final TournamentStorage? storage;

  @override
  State<TournamentResultsPage> createState() => _TournamentResultsPageState();
}

class _TournamentResultsPageState extends State<TournamentResultsPage> {
  CreatedTournament get tournament => widget.tournament;

  @override
  Widget build(BuildContext context) {
    if (tournament.importedArchive != null &&
        !tournament.importedArchive!.usesNativeLogic) {
      return ChallongeArchivePage(tournament: tournament);
    }
    final summary = _TournamentResultSummary.fromTournament(tournament);
    final podium = summary.ranking.take(3).toList();
    final performances = [
      for (final entry in _resultMatches(tournament))
        ...entry.match.bestPerformances,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Turnierergebnisse'),
        actions: [
          if (tournament.importedArchive != null)
            IconButton(
              tooltip: 'Mit Challonge vergleichen',
              icon: const Icon(Icons.compare_arrows),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChallongeArchivePage(tournament: tournament),
                ),
              ),
            ),
          if (tournament.stages.isNotEmpty &&
              tournament.importedArchive == null)
            IconButton(
              tooltip: 'Einstellungen',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _showSettings,
            ),
        ],
      ),
      body: SafeArea(
        child: AdaptiveContentList(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF142B3A), Color(0xFF175C59)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        tournament.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Turnier abgeschlossen',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Art: ${_tournamentTypeLabel(tournament)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Builder(
                        builder: (context) {
                          final timing = TournamentTiming.durationSummary(
                            tournament,
                          );
                          final averageLegsPerMatch = summary.matchCount == 0
                              ? 0.0
                              : summary.legCount / summary.matchCount;
                          final expectedRange = _expectedDurationRangeText();
                          return Column(
                            children: [
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 16,
                                runSpacing: 6,
                                children: [
                                  _CompletionMetric(
                                    label: 'Teilnehmer',
                                    value: '${summary.playerCount}',
                                  ),
                                  _CompletionMetric(
                                    label: 'Begegnungen',
                                    value: '${summary.matchCount}',
                                  ),
                                  _CompletionMetric(
                                    label: 'Gespielte Legs',
                                    value: '${summary.legCount}',
                                  ),
                                  _CompletionMetric(
                                    label: 'Legs / Match',
                                    value: averageLegsPerMatch.toStringAsFixed(
                                      1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DefaultTextStyle(
                                style:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ) ??
                                    const TextStyle(color: Colors.white),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    if (timing != null)
                                      Text(
                                        TournamentDurationRange.actualDurationLabel(
                                          timing.totalDuration,
                                        ),
                                      ),
                                    if (expectedRange != null)
                                      Tooltip(
                                        message:
                                            'Erwartete Spanne der Turnierdauer: $expectedRange',
                                        child: Text(
                                          expectedRange,
                                          key: const ValueKey(
                                            'expected-duration-range',
                                          ),
                                        ),
                                      ),
                                    if (timing == null && expectedRange == null)
                                      const Text('Dauer: nicht erfasst'),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (tournament.stages.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          tournament.stages
                              .map(
                                (stage) =>
                                    '${stage.name}: ${stage.gameFormat.label}',
                              )
                              .join('\n'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SportMenuGroup(
              title: 'Ergebnisse ansehen',
              actions: [
                SportMenuAction(
                  label: 'Spielergebnisse',
                  icon: Icons.groups_outlined,
                  onTap: () => _openPlayerList(context, summary),
                ),
                SportMenuAction(
                  label: 'Alle Begegnungen',
                  icon: Icons.sports_score,
                  onTap: () => _openMatches(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Podium',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (podium.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Es liegen noch keine Ergebnisse vor.'),
                ),
              )
            else ...[
              _Podium(
                ranking: podium,
                onPlayerTap: (stats) => _openPlayer(context, stats.player),
              ),
            ],
            const SizedBox(height: 16),
            TournamentRankingAssignment(
              tournament: tournament,
              database: widget.database,
              storage: widget.storage,
              onSaved: () {
                if (mounted) setState(() {});
              },
            ),
            if (tournament.countsForRanking &&
                tournament.rankingIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              TournamentRankingChangesSection(
                tournament: tournament,
                database: widget.database,
                storage: widget.storage,
              ),
            ],
            if (performances.isNotEmpty) ...[
              const SizedBox(height: 12),
              _BestPerformancesSummary(performances: performances),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => TournamentExportDialog.show(
                context,
                tournament,
                resultSummary: _exportSummary(summary),
                completionImageData: _completionImageData(
                  summary,
                  podium,
                  performances,
                ),
                database: widget.database,
                storage: widget.storage,
              ),
              icon: const Icon(Icons.ios_share),
              label: const Text('Turnier exportieren'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reopenTournament() async {
    final lastStageIndex = tournament.stages.length - 1;
    if (lastStageIndex < 0 || tournament.reopenedForCorrections) return;

    final previousFinishedAt = tournament.finishedAt;
    final previousPausedAt = tournament.pausedAt;
    final previousActiveStageIndex = tournament.activeStageIndex;
    final previousCompletedStages = Set<int>.from(
      tournament.completedStageIndexes,
    );
    final controller = TournamentRunController(storage: widget.storage);
    tournament
      ..finishedAt = null
      ..pausedAt ??= DateTime.now()
      ..reopenedForCorrections = true;

    try {
      await controller.saveProgress(
        tournament: tournament,
        activeStageIndex: lastStageIndex,
        completedStageIndexes: {...previousCompletedStages}
          ..remove(lastStageIndex),
      );
    } catch (error) {
      tournament
        ..finishedAt = previousFinishedAt
        ..pausedAt = previousPausedAt
        ..reopenedForCorrections = false
        ..activeStageIndex = previousActiveStageIndex;
      tournament.completedStageIndexes
        ..clear()
        ..addAll(previousCompletedStages);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Turnier konnte nicht geöffnet werden: $error'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => TournamentRunPage(
          tournament: tournament,
          runController: controller,
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    final reopen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Einstellungen'),
        content: const Text(
          'Das Turnier wird mit allen Ergebnissen erneut geöffnet. '
          'Die Turnieruhr bleibt pausiert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.replay),
            label: const Text('Turnier erneut öffnen'),
          ),
        ],
      ),
    );
    if (reopen == true) await _reopenTournament();
  }

  Map<String, Object?> _exportSummary(_TournamentResultSummary summary) {
    final timing = TournamentTiming.durationSummary(tournament);
    final expectedRange = _expectedDurationRange();
    return {
      'participantCount': summary.playerCount,
      'matchCount': summary.matchCount,
      'legCount': summary.legCount,
      'averageLegsPerMatch': summary.matchCount == 0
          ? 0
          : summary.legCount / summary.matchCount,
      'actualDurationSeconds': timing?.totalDuration.inSeconds,
      'expectedMinimumMinutes': expectedRange?.minimumMinutes,
      'expectedMaximumMinutes': expectedRange?.maximumMinutes,
      'podium': [
        for (final stats in summary.ranking.take(3))
          {
            'name': stats.player.name,
            'wins': stats.wins,
            'losses': stats.losses,
            'legsFor': stats.legsFor,
            'legsAgainst': stats.legsAgainst,
          },
      ],
    };
  }

  TournamentCompletionImageData _completionImageData(
    _TournamentResultSummary summary,
    List<_PlayerResultStats> podium,
    List<BestPerformance> performances,
  ) {
    final timing = TournamentTiming.durationSummary(tournament);
    final expectedRange = _expectedDurationRange();
    final durationParts = [
      if (timing != null)
        TournamentDurationRange.actualDurationLabel(timing.totalDuration),
      if (expectedRange != null)
        TournamentDurationRange.estimatedDurationLabel(
          minimumMinutes: expectedRange.minimumMinutes,
          maximumMinutes: expectedRange.maximumMinutes,
        ),
    ];
    return TournamentCompletionImageData(
      tournamentName: tournament.name,
      tournamentType: _tournamentTypeLabel(tournament),
      participantCount: summary.playerCount,
      matchCount: summary.matchCount,
      legCount: summary.legCount,
      averageLegsPerMatch: summary.matchCount == 0
          ? 0
          : summary.legCount / summary.matchCount,
      durationSummary: durationParts.join('\n'),
      podium: [
        for (var index = 0; index < podium.length; index++)
          TournamentCompletionPodiumEntry(
            place: index + 1,
            playerName: podium[index].player.name,
            wins: podium[index].wins,
            losses: podium[index].losses,
            legsFor: podium[index].legsFor,
            legsAgainst: podium[index].legsAgainst,
          ),
      ],
      rankingChanges: const [],
      bestPerformances: performances,
    );
  }

  ({int minimumMinutes, int maximumMinutes})? _expectedDurationRange() {
    final estimate = tournament.plannedMinutes;
    if (estimate == null) return null;
    final stages = <({int bestOfLegs, int matchCount})>[];
    for (var index = 0; index < tournament.stages.length; index++) {
      final stage = tournament.stages[index];
      final matchCount = index < tournament.runStages.length
          ? _matchesForRunStage(
              tournament.runStages[index],
            ).where((match) => match.hasPlayers).length
          : 0;
      stages.add((
        bestOfLegs: stage.gameFormat.bestOfLegs,
        matchCount: matchCount > 0 ? matchCount : 1,
      ));
    }
    if (stages.isEmpty) return null;
    return TournamentDurationRange.forEstimate(
      estimatedMinutes: estimate,
      matches: stages,
    );
  }

  List<GroupMatch> _matchesForRunStage(TournamentRunStage stage) =>
      switch (stage) {
        GroupTournamentRunStage() => [
          for (final group in stage.groups) ...[
            ...group.matches,
            ...group.knockoutRounds.expand((round) => round),
            ...group.placementMatches,
          ],
        ],
        KnockoutTournamentRunStage() => stage.matches,
        _ => const [],
      };

  String? _expectedDurationRangeText() {
    final range = _expectedDurationRange();
    if (range == null) return null;
    return TournamentDurationRange.estimatedDurationLabel(
      minimumMinutes: range.minimumMinutes,
      maximumMinutes: range.maximumMinutes,
    );
  }

  void _openPlayer(BuildContext context, TournamentPlayer player) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TournamentPlayerResultsPage(tournament: tournament, player: player),
      ),
    );
  }

  void _openPlayerList(BuildContext context, _TournamentResultSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TournamentPlayerListPage(
          tournament: tournament,
          ranking: summary.ranking,
        ),
      ),
    );
  }

  Future<void> _openMatches(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TournamentMatchesPage(tournament: tournament),
      ),
    );
    if (mounted) setState(() {});
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.ranking, required this.onPlayerTap});

  final List<_PlayerResultStats> ranking;
  final ValueChanged<_PlayerResultStats> onPlayerTap;

  @override
  Widget build(BuildContext context) {
    const medals = [Icons.looks_one, Icons.looks_two, Icons.looks_3];
    const colors = [Color(0xffffc107), Color(0xffb0bec5), Color(0xffcd7f32)];
    return AdaptiveTileLayout(
      minTileWidth: 220,
      children: [
        for (var index = 0; index < ranking.length; index++)
          InkWell(
            onTap: () => onPlayerTap(ranking[index]),
            borderRadius: BorderRadius.circular(12),
            child: Card(
              color: colors[index].withValues(alpha: .18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
                child: Column(
                  children: [
                    Icon(medals[index], size: 34, color: colors[index]),
                    const SizedBox(height: 6),
                    Text(
                      '${index + 1}. Platz',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ranking[index].player.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ranking[index].wins} Siege · ${ranking[index].losses} Niederlagen · '
                      '${ranking[index].legsFor}:${ranking[index].legsAgainst} Legs',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CompletionMetric extends StatelessWidget {
  const _CompletionMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white)),
    ],
  );
}

class _BestPerformancesSummary extends StatelessWidget {
  const _BestPerformancesSummary({required this.performances});

  final List<BestPerformance> performances;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Bestleistungen',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            for (final performance in performances)
              ListTile(
                leading: const Icon(Icons.military_tech_outlined),
                title: Text('${performance.playerName} · ${performance.label}'),
                trailing: performance.value == null
                    ? null
                    : Text('${performance.value}'),
              ),
          ],
        ),
      ),
    ],
  );
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.place,
    required this.stats,
    required this.maxLegs,
    required this.onTap,
  });

  final int place;
  final _PlayerResultStats stats;
  final int maxLegs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = maxLegs == 0 ? 0.0 : stats.legsFor / maxLegs;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text('$place')),
      title: Text(stats.player.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stats.wins} Siege · ${stats.losses} Niederlagen · ${stats.legsFor}:${stats.legsAgainst} Legs',
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(value: value),
        ],
      ),
      isThreeLine: true,
    );
  }
}

class _TournamentPlayerListPage extends StatelessWidget {
  const _TournamentPlayerListPage({
    required this.tournament,
    required this.ranking,
  });

  final CreatedTournament tournament;
  final List<_PlayerResultStats> ranking;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Spielerübersicht')),
    body: AdaptiveContentList(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Spieler auswählen, um alle Begegnungen und Ergebnisse zu sehen.',
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < ranking.length; index++)
                _RankingRow(
                  place: index + 1,
                  stats: ranking[index],
                  maxLegs: ranking.fold<int>(
                    0,
                    (maxLegs, entry) =>
                        entry.legsFor > maxLegs ? entry.legsFor : maxLegs,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TournamentPlayerResultsPage(
                        tournament: tournament,
                        player: ranking[index].player,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class TournamentPlayerResultsPage extends StatefulWidget {
  const TournamentPlayerResultsPage({
    super.key,
    required this.tournament,
    required this.player,
  });

  final CreatedTournament tournament;
  final TournamentPlayer player;

  @override
  State<TournamentPlayerResultsPage> createState() =>
      _TournamentPlayerResultsPageState();
}

class _TournamentPlayerResultsPageState
    extends State<TournamentPlayerResultsPage> {
  late final Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges =
      _loadTournamentEloChanges(widget.tournament);

  @override
  Widget build(BuildContext context) {
    final matches = _resultMatches(widget.tournament)
        .where(
          (entry) =>
              entry.match.homePlayer?.name == widget.player.name ||
              entry.match.awayPlayer?.name == widget.player.name,
        )
        .toList();
    final played = matches.where((entry) => entry.match.hasResult).toList();
    final wins = played
        .where((entry) => entry.match.winner?.name == widget.player.name)
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.player.name)),
      body: AdaptiveContentList(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Ergebnisse von ${widget.player.name}',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('$wins Siege aus ${played.length} gewerteten Begegnungen'),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, List<TournamentMatchEloChange>>>(
            future: _eloChanges,
            builder: (context, snapshot) => Column(
              children: [
                if (snapshot.hasError) const _EloChangesLoadError(),
                if (matches.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Für diesen Spieler liegen keine Begegnungen vor.',
                      ),
                    ),
                  )
                else
                  for (final entry in matches)
                    _ResultMatchCard(
                      entry: entry,
                      highlightPlayer: widget.player,
                      eloChanges: _eloChangesForMatch(
                        widget.tournament,
                        entry.match,
                        snapshot.data ?? const {},
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

class TournamentMatchesPage extends StatefulWidget {
  const TournamentMatchesPage({super.key, required this.tournament});

  final CreatedTournament tournament;

  @override
  State<TournamentMatchesPage> createState() => _TournamentMatchesPageState();
}

class _TournamentMatchesPageState extends State<TournamentMatchesPage> {
  bool _saving = false;
  late final Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges =
      _loadTournamentEloChanges(widget.tournament);

  Future<void> _editBestPerformances(GroupMatch match) async {
    var items = [...match.bestPerformances];
    final result = await showDialog<List<BestPerformance>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bestleistungen erfassen'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: BestPerformanceEditor(
                match: match,
                initial: items,
                onChanged: (value) {
                  items = value;
                  setDialogState(() {});
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, items),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      match.bestPerformances = result;
      await TournamentStorage().saveTournament(widget.tournament);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bestleistungen konnten nicht gespeichert werden: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _resultMatches(widget.tournament);
    return Scaffold(
      appBar: AppBar(title: const Text('Alle Begegnungen')),
      body: AdaptiveContentList(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${matches.where((entry) => entry.match.hasResult).length} gewertete Begegnungen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_saving) const LinearProgressIndicator(),
          FutureBuilder<Map<String, List<TournamentMatchEloChange>>>(
            future: _eloChanges,
            builder: (context, snapshot) => Column(
              children: [
                if (snapshot.hasError) const _EloChangesLoadError(),
                if (matches.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Es wurden noch keine Begegnungen angelegt.'),
                    ),
                  )
                else
                  for (final entry in matches)
                    _ResultMatchCard(
                      entry: entry,
                      eloChanges: _eloChangesForMatch(
                        widget.tournament,
                        entry.match,
                        snapshot.data ?? const {},
                      ),
                      onEditBestPerformances: entry.match.hasResult
                          ? () => _editBestPerformances(entry.match)
                          : null,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultMatchCard extends StatelessWidget {
  const _ResultMatchCard({
    required this.entry,
    this.highlightPlayer,
    this.eloChanges = const [],
    this.onEditBestPerformances,
  });

  final _ResultMatch entry;
  final TournamentPlayer? highlightPlayer;
  final List<TournamentMatchEloChange> eloChanges;
  final VoidCallback? onEditBestPerformances;

  @override
  Widget build(BuildContext context) {
    final match = entry.match;
    final home = match.homePlayer?.name ?? 'Noch offen';
    final away = match.awayPlayer?.name ?? 'Noch offen';
    final score = match.isAnnulled
        ? 'Annulliert'
        : match.hasResult
        ? match.scoreLabel
        : 'Noch nicht gespielt';
    final highlightHome = highlightPlayer?.name == home;
    final highlightAway = highlightPlayer?.name == away;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.stageName} · ${entry.roundName}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '$home  $score  $away',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            for (final change in eloChanges)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${change.rankingName}: $home '),
                      _eloDeltaSpan(context, change.homeDelta),
                      const TextSpan(text: ' · '),
                      TextSpan(text: '$away '),
                      _eloDeltaSpan(context, change.awayDelta),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            if (highlightHome || highlightAway)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  highlightHome
                      ? '$home spielte zuhause'
                      : '$away spielte auswärts',
                ),
              ),
            if (onEditBestPerformances != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onEditBestPerformances,
                  icon: const Icon(Icons.military_tech_outlined),
                  label: Text(
                    entry.match.bestPerformances.isEmpty
                        ? 'Bestleistung erfassen'
                        : 'Bestleistungen bearbeiten (${entry.match.bestPerformances.length})',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, List<TournamentMatchEloChange>>> _loadTournamentEloChanges(
  CreatedTournament tournament,
) {
  if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
    return Future.value(const {});
  }
  return TournamentMatchEloService().calculate(tournament);
}

List<TournamentMatchEloChange> _eloChangesForMatch(
  CreatedTournament tournament,
  GroupMatch match,
  Map<String, List<TournamentMatchEloChange>> changes,
) {
  final key = const LocalEloCalculator().matchKey(tournament, match);
  return key == null ? const [] : changes[key] ?? const [];
}

String _formatEloDelta(int? delta) {
  if (delta == null) return '—';
  return delta > 0 ? '+$delta Elo' : '$delta Elo';
}

TextSpan _eloDeltaSpan(BuildContext context, int? delta) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final color = delta == null || delta == 0
      ? Theme.of(context).colorScheme.onSurface
      : delta > 0
      ? isDark
            ? const Color(0xFF86EFAC)
            : const Color(0xFF0B6B45)
      : isDark
      ? const Color(0xFFEF9A9A)
      : const Color(0xFFC62828);
  return TextSpan(
    text: _formatEloDelta(delta),
    style: TextStyle(color: color, fontWeight: FontWeight.w600),
  );
}

class _EloChangesLoadError extends StatelessWidget {
  const _EloChangesLoadError();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Text('Ranglistenänderungen konnten nicht geladen werden.'),
  );
}

String _tournamentTypeLabel(CreatedTournament tournament) {
  if (tournament.leagueMatch != null) {
    return tournament.leagueMatch!.variant == LeagueMatchVariant.adjusted
        ? 'Angepasstes Liga-/Freundschaftsspiel'
        : 'Traditionelles Ligaspiel';
  }
  if (tournament.importedArchive != null) return 'Challonge-Turnier';
  if (tournament.countsForRanking && tournament.rankingIds.isNotEmpty) {
    return 'Ranglistenturnier';
  }
  return 'Normales Turnier';
}

class _ResultMatch {
  const _ResultMatch(this.stageName, this.match, this.roundName);
  final String stageName;
  final String roundName;
  final GroupMatch match;
}

List<_ResultMatch> _resultMatches(CreatedTournament tournament) => [
  for (final stage in tournament.runStages)
    if (stage is KnockoutTournamentRunStage)
      for (final match in stage.matches)
        _ResultMatch(stage.name, match, stageMatchName(stage, match))
    else if (stage is GroupTournamentRunStage)
      for (final group in stage.groups)
        for (final match in <GroupMatch>{
          ...group.matches,
          ...group.knockoutRounds.expand((round) => round),
          ...group.placementMatches,
        })
          _ResultMatch(
            '${stage.name} · ${group.name}',
            match,
            stageMatchName(stage, match),
          ),
];

class _TournamentResultSummary {
  _TournamentResultSummary({
    required this.ranking,
    required this.matchCount,
    required this.legCount,
    required this.playerCount,
    required this.rankingHint,
  });

  final List<_PlayerResultStats> ranking;
  final int matchCount;
  final int legCount;
  final int playerCount;
  final String rankingHint;

  int get maxLegs =>
      ranking.fold(0, (max, item) => item.legsFor > max ? item.legsFor : max);

  factory _TournamentResultSummary.fromTournament(
    CreatedTournament tournament,
  ) {
    final stats = {
      for (final player in tournament.players)
        player.name: _PlayerResultStats(player),
    };
    var matchCount = 0;
    var legCount = 0;

    for (final stage in tournament.runStages) {
      for (final match in _matchesFor(stage)) {
        if (!match.hasResult) continue;
        final home = match.homePlayer!;
        final away = match.awayPlayer!;
        final homeStats = stats.putIfAbsent(
          home.name,
          () => _PlayerResultStats(home),
        );
        final awayStats = stats.putIfAbsent(
          away.name,
          () => _PlayerResultStats(away),
        );
        final homeLegs = match.homeLegs!;
        final awayLegs = match.awayLegs!;
        matchCount++;
        legCount += homeLegs + awayLegs;
        homeStats.legsFor += homeLegs;
        homeStats.legsAgainst += awayLegs;
        awayStats.legsFor += awayLegs;
        awayStats.legsAgainst += homeLegs;
        if (match.winner == match.homePlayer) {
          homeStats.wins++;
          awayStats.losses++;
        } else if (match.winner == match.awayPlayer) {
          awayStats.wins++;
          homeStats.losses++;
        }
      }
    }

    final finalStage = tournament.runStages.isEmpty
        ? null
        : tournament.runStages.last;
    final native = tournament.importedArchive?.usesNativeLogic == true;
    final runtime = native ? ProductionTournamentRuntime(tournament) : null;
    final finalStageRanking = finalStage is KnockoutTournamentRunStage
        ? runtime?.ranking(finalStage, const []) ?? _knockoutRanking(finalStage)
        : native &&
              finalStage is GroupTournamentRunStage &&
              finalStage.groups.length == 1
        ? runtime!
              .standings(finalStage.groups.single, finalStage.tieBreakers)
              .map((s) => s.player)
              .toList()
        : finalStage is GroupTournamentRunStage && finalStage.groups.length == 1
        ? const GroupStandingsEngine()
              .calculate(
                finalStage.groups.single,
                finalStage.tieBreakers,
                tournament: tournament,
              )
              .map((standing) => standing.player)
              .toList()
        : const <TournamentPlayer>[];
    final ranking = <_PlayerResultStats>[];
    for (final player in finalStageRanking) {
      final entry = stats[player.name];
      if (entry != null) ranking.add(entry);
    }
    final remaining =
        stats.values.where((entry) => !ranking.contains(entry)).toList()
          ..sort(_compareStats);
    ranking.addAll(remaining);

    return _TournamentResultSummary(
      ranking: ranking,
      matchCount: matchCount,
      legCount: legCount,
      playerCount: tournament.players.length,
      rankingHint: finalStage is KnockoutTournamentRunStage
          ? 'Die Platzierung folgt dem finalen K.-o.-Baum; die Balken zeigen gewonnene Legs im gesamten Turnier.'
          : finalStage is GroupTournamentRunStage &&
                finalStage.groups.length == 1
          ? 'Die Platzierung folgt den Tie-Breaker-Einstellungen der finalen Gruppenphase.'
          : 'Die Platzierung folgt den Gesamtwerten aus allen eingetragenen Spielen.',
    );
  }

  static int _compareStats(_PlayerResultStats a, _PlayerResultStats b) {
    final wins = b.wins.compareTo(a.wins);
    if (wins != 0) return wins;
    final difference = b.legDifference.compareTo(a.legDifference);
    if (difference != 0) return difference;
    final legs = b.legsFor.compareTo(a.legsFor);
    if (legs != 0) return legs;
    return a.player.name.compareTo(b.player.name);
  }

  static List<GroupMatch> _matchesFor(TournamentRunStage stage) {
    if (stage is KnockoutTournamentRunStage) return stage.matches;
    if (stage is GroupTournamentRunStage) {
      return [for (final group in stage.groups) ...group.matches];
    }
    return const [];
  }

  static List<TournamentPlayer> _knockoutRanking(
    KnockoutTournamentRunStage stage,
  ) {
    final ranking = <TournamentPlayer>[];
    void add(TournamentPlayer? player) {
      if (player != null &&
          !ranking.any((entry) => entry.name == player.name)) {
        ranking.add(player);
      }
    }

    if (stage.eliminationLossLimit > 1) {
      final losses = <String, int>{};
      final lastRound = <String, int>{};
      final players = <TournamentPlayer>[];
      for (final round in stage.rounds) {
        for (final match in round) {
          addUnique(players, match.homePlayer);
          addUnique(players, match.awayPlayer);
          if (!match.hasResult) continue;
          final loser = match.loser;
          final winner = match.winner;
          if (loser != null) losses[loser.name] = (losses[loser.name] ?? 0) + 1;
          if (loser != null) lastRound[loser.name] = match.round;
          if (winner != null) lastRound[winner.name] = match.round;
        }
      }
      players.sort((a, b) {
        final lossComparison = (losses[a.name] ?? 0).compareTo(
          losses[b.name] ?? 0,
        );
        if (lossComparison != 0) return lossComparison;
        final roundComparison = (lastRound[b.name] ?? 0).compareTo(
          lastRound[a.name] ?? 0,
        );
        if (roundComparison != 0) return roundComparison;
        return a.name.compareTo(b.name);
      });
      if (stage.finalEndsTournament &&
          stage.rounds.isNotEmpty &&
          stage.rounds.last.length == 1 &&
          stage.rounds.last.single.hasResult) {
        final last = stage.rounds.last.single;
        players.removeWhere(
          (p) => p.name == last.winner?.name || p.name == last.loser?.name,
        );
        players.insertAll(0, [
          if (last.winner != null) last.winner!,
          if (last.loser != null) last.loser!,
        ]);
      }
      return players;
    }

    if (stage.rounds.isNotEmpty) {
      final finalRound = stage.rounds.last;
      if (finalRound.length == 1) {
        add(finalRound.first.winner);
        add(finalRound.first.loser);
      } else {
        for (final match in finalRound) {
          add(match.winner);
        }
      }
      for (final match in stage.placementMatches.where(
        (match) => match.label == 'Spiel um Platz 3',
      )) {
        add(match.winner);
        add(match.loser);
      }
      for (
        var roundIndex = stage.rounds.length - 2;
        roundIndex >= 0;
        roundIndex--
      ) {
        for (final match in stage.rounds[roundIndex]) {
          add(match.loser);
        }
      }
    }
    return PlacementEngine.applyRanking(ranking, stage.placementMatches);
  }

  static void addUnique(
    List<TournamentPlayer> players,
    TournamentPlayer? player,
  ) {
    if (player != null && !players.any((entry) => entry.name == player.name)) {
      players.add(player);
    }
  }
}

class _PlayerResultStats {
  _PlayerResultStats(this.player);

  final TournamentPlayer player;
  int wins = 0;
  int losses = 0;
  int legsFor = 0;
  int legsAgainst = 0;

  int get legDifference => legsFor - legsAgainst;
}
