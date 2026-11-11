import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';
import 'best_of_comparison_table.dart';
import 'knockout_run_section.dart';
import 'result_entry.dart';
import 'recent_match_result_card.dart';
import 'standings_table.dart';

enum MatchCategoryFilter { open, finished, all }

class StageResultsSplitView extends StatefulWidget {
  const StageResultsSplitView({
    super.key,
    required this.stage,
    required this.standingsFor,
    required this.onEditResult,
    required this.canEditResults,
    this.tournament,
    this.bracketBuilder,
    this.onEditBracketResult,
    this.onPreviewBracket,
    this.qualifyingRank = 1,
    this.isBracketEditMode = false,
    this.canEditBracket = false,
    this.onSwapSlot,
    this.onOpenMatch,
    this.focusMatch,
    this.runningMatches = const {},
    this.initialFilter,
  });

  final TournamentRunStage stage;
  final List<PlayerStanding> Function(
    TournamentGroup group,
    List<String> tieBreakers,
  )
  standingsFor;
  final FutureOr<void> Function(GroupMatch match) onEditResult;
  final bool canEditResults;
  final CreatedTournament? tournament;
  final KnockoutBracketBuilder? bracketBuilder;
  final FutureOr<void> Function(GroupMatch match, VoidCallback onUpdated)?
  onEditBracketResult;
  final VoidCallback? onPreviewBracket;
  final int qualifyingRank;
  final bool isBracketEditMode;
  final bool canEditBracket;
  final void Function(int fromSlotIndex, int toSlotIndex)? onSwapSlot;
  final ValueChanged<GroupMatch>? onOpenMatch;
  final GroupMatch? focusMatch;
  final Set<GroupMatch> runningMatches;
  final MatchCategoryFilter? initialFilter;

  @override
  State<StageResultsSplitView> createState() => _StageResultsSplitViewState();
}

class _StageResultsSplitViewState extends State<StageResultsSplitView> {
  // Default is "Offene Begegnungen" (always visible on initial load, finished and all matches hidden by default)
  late MatchCategoryFilter _filter =
      widget.initialFilter ?? MatchCategoryFilter.open;
  TournamentPlayer? _filteredPlayer;
  final Map<GroupMatch, GlobalKey> _matchTileKeys = {};
  bool _focusScheduled = false;

  @override
  void didUpdateWidget(covariant StageResultsSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter ?? MatchCategoryFilter.open;
    }
    if (oldWidget.focusMatch != widget.focusMatch) {
      _filter = MatchCategoryFilter.finished;
      _focusScheduled = false;
    }
  }

  GlobalKey _keyForMatch(GroupMatch match) =>
      _matchTileKeys.putIfAbsent(match, GlobalKey.new);

  void _scheduleFocusScroll() {
    final match = widget.focusMatch;
    if (match == null || _focusScheduled) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _matchTileKeys[match]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
          alignment: 0.2,
        );
      }
    });
  }

  String _playerKey(TournamentPlayer player) => player.profileId ?? player.name;

  void _selectPlayer(TournamentPlayer player) {
    setState(() => _filteredPlayer = player);
  }

  Future<void> _editResult(GroupMatch match) async {
    if (_filteredPlayer != null) {
      setState(() => _filteredPlayer = null);
    }
    await widget.onEditResult(match);
  }

  bool _matchesPlayerFilter(GroupMatch match) {
    final player = _filteredPlayer;
    if (player == null) return true;
    final selectedKeys = player.individuals.map(_playerKey).toSet();
    bool includesSelectedPlayer(TournamentPlayer participant) => participant
        .individuals
        .any((individual) => selectedKeys.contains(_playerKey(individual)));

    if (match.isKratzer) {
      return match.players.any(includesSelectedPlayer);
    }
    return (match.homePlayer != null &&
            includesSelectedPlayer(match.homePlayer!)) ||
        (match.awayPlayer != null && includesSelectedPlayer(match.awayPlayer!));
  }

  @override
  Widget build(BuildContext context) {
    _scheduleFocusScroll();
    final stage = widget.stage;

    if (stage is GroupTournamentRunStage) {
      return _buildGroupStageResults(context, stage);
    } else if (stage is KnockoutTournamentRunStage) {
      return _buildKnockoutStageResults(context, stage);
    }

    return const SizedBox.shrink();
  }

  Widget _buildGroupStageResults(
    BuildContext context,
    GroupTournamentRunStage stage,
  ) {
    final standingsByGroup = {
      for (final group in stage.groups)
        if (['round_robin', 'swiss'].contains(group.playType))
          group: widget.standingsFor(group, stage.tieBreakers),
    };

    // Calculate match counts for filter segments
    int openCount = 0;
    int finishedCount = 0;
    int totalCount = 0;

    for (final group in stage.groups) {
      for (final match in group.matches) {
        if (!match.hasPlayers) continue;
        totalCount++;
        if (match.hasResult) {
          finishedCount++;
        } else {
          openCount++;
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        final matchesSection = _buildGroupMatchesColumn(
          context: context,
          stage: stage,
          openCount: openCount,
          finishedCount: finishedCount,
          totalCount: totalCount,
        );

        final standingsSection = _buildGroupStandingsColumn(
          context: context,
          stage: stage,
          standingsByGroup: standingsByGroup,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2/3 column on the left for matches (unfolded, direct access)
              Expanded(flex: 2, child: matchesSection),
              const SizedBox(width: 16),
              // 1/3 column on the right for standings / tables
              Expanded(flex: 1, child: standingsSection),
            ],
          );
        }

        // On mobile / narrow screens, stack vertically
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            matchesSection,
            const SizedBox(height: 20),
            standingsSection,
          ],
        );
      },
    );
  }

  Widget _buildGroupMatchesColumn({
    required BuildContext context,
    required GroupTournamentRunStage stage,
    required int openCount,
    required int finishedCount,
    required int totalCount,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category Filter Segmented Button: "Offene Begegnungen" (default), "Bereits gespielt", "Alle Begegnungen"
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<MatchCategoryFilter>(
            segments: [
              ButtonSegment<MatchCategoryFilter>(
                value: MatchCategoryFilter.open,
                label: Text('Offene Begegnungen ($openCount)'),
                icon: const Icon(Icons.play_circle_outline, size: 18),
              ),
              ButtonSegment<MatchCategoryFilter>(
                value: MatchCategoryFilter.finished,
                label: Text('Bereits gespielt ($finishedCount)'),
                icon: const Icon(Icons.check_circle_outline, size: 18),
              ),
              ButtonSegment<MatchCategoryFilter>(
                value: MatchCategoryFilter.all,
                label: Text('Alle Begegnungen ($totalCount)'),
                icon: const Icon(Icons.list_alt, size: 18),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                setState(() => _filter = selected.first);
              }
            },
          ),
        ),
        const SizedBox(height: 12),

        if (stage.groups.any((g) => g.playType == 'swiss'))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Swiss: Nächste Runde erst nach allen Ergebnissen der vorherigen Runde.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

        if (_filteredPlayer case final player?) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                  label: Text('Begegnungen von ${player.name}'),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _filteredPlayer = null),
                  icon: const Icon(Icons.clear),
                  label: const Text('Filter aufheben'),
                ),
              ],
            ),
          ),
        ],

        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1200
                ? math.min(4, stage.groups.length)
                : constraints.maxWidth >= 900 && stage.groups.length > 1
                ? 2
                : 1;
            final groupWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 12 * (columns - 1)) / columns;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final group in stage.groups)
                  SizedBox(
                    width: groupWidth,
                    child: _buildGroupMatchList(
                      context: context,
                      group: group,
                      showGroupHeader: true,
                      compact: columns > 1,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        _buildRecentResultsSection(
          context,
          stage.groups.expand((group) => group.matches).toList(),
        ),
      ],
    );
  }

  Widget _buildRecentResultsSection(
    BuildContext context,
    List<GroupMatch> matches,
  ) {
    final tournament = widget.tournament;
    if (tournament == null) return const SizedBox.shrink();
    final recent = matches.where((match) => match.hasResult).toList()
      ..sort((left, right) {
        final leftTime = left.finishedAt ?? left.startedAt;
        final rightTime = right.finishedAt ?? right.startedAt;
        if (leftTime == null) return rightTime == null ? 0 : 1;
        if (rightTime == null) return -1;
        return rightTime.compareTo(leftTime);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Letzte Ergebnisse',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const Text('Noch keine beendeten Partien vorhanden.')
        else
          for (final match in recent.take(8))
            RecentMatchResultLogEntry(
              tournament: tournament,
              match: match,
              eloChanges: const [],
              showBoardNumber: tournament.directorModeEnabled,
              onTap: widget.onOpenMatch == null
                  ? null
                  : () => widget.onOpenMatch!(match),
            ),
      ],
    );
  }

  Widget _buildGroupMatchList({
    required BuildContext context,
    required TournamentGroup group,
    required bool showGroupHeader,
    required bool compact,
  }) {
    final theme = Theme.of(context);

    final filteredMatches = group.matches.where((m) {
      if (!m.hasPlayers) return false;
      if (!_matchesPlayerFilter(m)) return false;
      switch (_filter) {
        case MatchCategoryFilter.open:
          return !m.hasResult;
        case MatchCategoryFilter.finished:
          return m.hasResult;
        case MatchCategoryFilter.all:
          return true;
      }
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showGroupHeader) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  group.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${filteredMatches.length} Partien',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (filteredMatches.isEmpty)
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  _filteredPlayer != null
                      ? 'Keine Begegnungen von ${_filteredPlayer!.name} in dieser Ansicht.'
                      : _filter == MatchCategoryFilter.open
                      ? 'Alle Begegnungen in ${group.name} sind abgeschlossen.'
                      : _filter == MatchCategoryFilter.finished
                      ? 'Noch keine gespielten Partien in ${group.name}.'
                      : 'Keine Begegnungen vorhanden.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final match in filteredMatches)
                    SizedBox(
                      width: width,
                      child: MatchResultTile(
                        key: _keyForMatch(match),
                        match: match,
                        tournament: widget.tournament,
                        onEditResult: _editResult,
                        canEditResult: widget.canEditResults,
                        leadingLabel: match.isDecider ? match.label : null,
                        showRoundLabel: match.isDecider,
                        compact: compact,
                        onPlayerTap: _selectPlayer,
                        isRunning: widget.runningMatches.contains(match),
                        isFocused: identical(widget.focusMatch, match),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildGroupStandingsColumn({
    required BuildContext context,
    required GroupTournamentRunStage stage,
    required Map<TournamentGroup, List<PlayerStanding>> standingsByGroup,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tabellen & Zwischenstände',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < stage.groups.length; index++)
          if (standingsByGroup.containsKey(stage.groups[index]))
            Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: Text(
                      stage.groups[index].name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  StandingsTable(
                    standings: standingsByGroup[stage.groups[index]]!,
                    group: stage.groups[index],
                    groupNumber: index + 1,
                    qualificationPlan: stage.qualificationPlan,
                    tieBreakers: stage.tieBreakers,
                    onPlayerTap: _selectPlayer,
                  ),
                ],
              ),
            ),
        if (stage.qualificationPlan != null &&
            stage.qualificationPlan!.extraCount > 0 &&
            stage.groups.every(
              (group) => ['round_robin', 'swiss'].contains(group.playType),
            ))
          BestOfComparisonTable(
            stage: stage,
            standingsByGroup: standingsByGroup,
          ),
      ],
    );
  }

  Widget _buildKnockoutStageResults(
    BuildContext context,
    KnockoutTournamentRunStage stage,
  ) {
    // Gather all KO matches
    final allRounds = stage.rounds;
    final allMatches = [
      for (final round in allRounds) ...round,
      ...stage.placementMatches,
    ];

    int openCount = 0;
    int finishedCount = 0;
    int totalCount = 0;

    for (final match in allMatches) {
      if (!match.hasPlayers) continue;
      totalCount++;
      if (match.hasResult) {
        finishedCount++;
      } else {
        openCount++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        final matchesSection = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<MatchCategoryFilter>(
                segments: [
                  ButtonSegment<MatchCategoryFilter>(
                    value: MatchCategoryFilter.open,
                    label: Text('Offene Begegnungen ($openCount)'),
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                  ),
                  ButtonSegment<MatchCategoryFilter>(
                    value: MatchCategoryFilter.finished,
                    label: Text('Bereits gespielt ($finishedCount)'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                  ),
                  ButtonSegment<MatchCategoryFilter>(
                    value: MatchCategoryFilter.all,
                    label: Text('Alle Begegnungen ($totalCount)'),
                    icon: const Icon(Icons.list_alt, size: 18),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    setState(() => _filter = selected.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildKnockoutMatchList(stage),
            const SizedBox(height: 20),
            _buildRecentResultsSection(context, allMatches),
          ],
        );

        final bracketSection = stage.isKratzer
            ? _buildKratzerLifePanel(context, stage)
            : widget.bracketBuilder != null
            ? Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.account_tree_outlined, size: 28),
                      const SizedBox(height: 8),
                      Text(
                        'Turnierbaum',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            widget.onPreviewBracket ??
                            () => _openFullBracketPreview(context, stage),
                        icon: const Icon(Icons.open_in_full),
                        label: const Text('KO Baum öffnen'),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink();

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: matchesSection),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: bracketSection),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            matchesSection,
            const SizedBox(height: 20),
            bracketSection,
          ],
        );
      },
    );
  }

  Widget _buildKratzerLifePanel(
    BuildContext context,
    KnockoutTournamentRunStage stage,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lebenstand',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            for (final player in stage.participants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(player.name),
                subtitle: Text(
                  '${stage.scratchesFor(player)} Kratzer · '
                  '${stage.bonusLivesFor(player)} Bonusleben',
                ),
                leading: Icon(
                  stage.livesRemainingFor(player) == 0
                      ? Icons.person_off_outlined
                      : Icons.favorite_outline,
                ),
                trailing: Text('${stage.livesRemainingFor(player)}'),
              ),
          ],
        ),
      ),
    );
  }

  void _openFullBracketPreview(
    BuildContext context,
    KnockoutTournamentRunStage stage,
  ) {
    final bracketBuilder = widget.bracketBuilder;
    if (bracketBuilder == null) return;
    var bracketRevision = 0;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text('${stage.name} · Turnierbaum'),
              leading: IconButton(
                tooltip: 'Zurück zu Partien & Ergebnisse',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: KeyedSubtree(
                    key: ValueKey(bracketRevision),
                    child: bracketBuilder(
                      stage,
                      widget.qualifyingRank,
                      (match) async {
                        void refreshBracket() {
                          if (dialogContext.mounted) {
                            setDialogState(() => bracketRevision++);
                          }
                        }

                        final editBracketResult = widget.onEditBracketResult;
                        if (editBracketResult == null) {
                          await widget.onEditResult(match);
                          refreshBracket();
                        } else {
                          await editBracketResult(match, refreshBracket);
                        }
                      },
                      widget.canEditResults,
                      widget.isBracketEditMode && widget.canEditBracket,
                      widget.onSwapSlot ?? (a, b) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKnockoutMatchList(KnockoutTournamentRunStage stage) {
    final theme = Theme.of(context);
    final allRounds = stage.rounds;

    final visibleRounds = <int, List<GroupMatch>>{};
    for (var i = 0; i < allRounds.length; i++) {
      final matches = allRounds[i].where((m) {
        if (!m.hasPlayers) return false;
        switch (_filter) {
          case MatchCategoryFilter.open:
            return !m.hasResult;
          case MatchCategoryFilter.finished:
            return m.hasResult;
          case MatchCategoryFilter.all:
            return true;
        }
      }).toList();
      if (matches.isNotEmpty) {
        visibleRounds[i] = matches;
      }
    }

    final placementFiltered = stage.placementMatches.where((m) {
      if (!m.hasPlayers) return false;
      switch (_filter) {
        case MatchCategoryFilter.open:
          return !m.hasResult;
        case MatchCategoryFilter.finished:
          return m.hasResult;
        case MatchCategoryFilter.all:
          return true;
      }
    }).toList();

    if (visibleRounds.isEmpty && placementFiltered.isEmpty) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              _filter == MatchCategoryFilter.open
                  ? 'Keine offenen K.-o.-Begegnungen.'
                  : _filter == MatchCategoryFilter.finished
                  ? 'Noch keine K.-o.-Begegnungen beendet.'
                  : 'Keine K.-o.-Begegnungen vorhanden.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in visibleRounds.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              stage.eliminationLossLimit == 1
                  ? knockoutRoundName(entry.key, stage.rounds.length)
                  : 'Runde ${entry.key + 1}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final match in entry.value)
            MatchResultTile(
              key: _keyForMatch(match),
              match: match,
              tournament: widget.tournament,
              onEditResult: widget.onEditResult,
              canEditResult: widget.canEditResults,
              leadingLabel: match.label,
              isRunning: widget.runningMatches.contains(match),
              isFocused: identical(widget.focusMatch, match),
            ),
          const SizedBox(height: 8),
        ],
        if (placementFiltered.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              'Platzierungsspiele',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final match in placementFiltered)
            MatchResultTile(
              key: ValueKey(match),
              match: match,
              tournament: widget.tournament,
              onEditResult: widget.onEditResult,
              canEditResult: widget.canEditResults,
              leadingLabel: match.label,
            ),
        ],
      ],
    );
  }
}
