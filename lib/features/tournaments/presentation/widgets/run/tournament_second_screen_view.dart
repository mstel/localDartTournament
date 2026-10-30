import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;
import 'package:flutter/services.dart';

import '../../../../../shared/theme/tournament_display_palette.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/engines/group_standings_engine.dart';
import '../../../domain/tournament_flow_priority_settings.dart';
import '../../../domain/engines/qualification_certainty.dart';
import '../../../application/group_stage_preview_service.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../application/tournament_flow_priority_preferences.dart';
import '../../../application/tournament_timing.dart';
import '../../../application/group_advancement_forecast_service.dart';
import '../../../domain/engines/group_advancement_forecast_engine.dart';
import 'standings_table.dart';
import 'recommended_matches_table.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../../rankings/domain/local_elo_calculator.dart';
import 'recent_match_result_card.dart';

/// Feste, responsive Info-Tafel für den Vereinsheim-TV (2. Bildschirm).
class TournamentSecondScreenView extends StatefulWidget {
  const TournamentSecondScreenView({
    super.key,
    required this.tournament,
    this.isStandaloneWindow = false,
    this.onClose,
    this.showNextStagePreviewInitially = false,
    this.forecastService,
  });

  final CreatedTournament tournament;
  final bool isStandaloneWindow;
  final VoidCallback? onClose;
  final bool showNextStagePreviewInitially;
  final GroupAdvancementForecastService? forecastService;

  @override
  State<TournamentSecondScreenView> createState() =>
      _TournamentSecondScreenViewState();
}

class _TournamentSecondScreenViewState
    extends State<TournamentSecondScreenView> {
  bool _showNextStagePreview = false;
  bool _showInlineNextStagePreview = false;
  bool _showPrognosis = false;
  Timer? _clockTimer;
  final _previewVerticalController = ScrollController();
  final _previewHorizontalController = ScrollController();
  TournamentFlowPrioritySettings _prioritySettings =
      TournamentFlowPriority.defaultSettings;
  String? _prioritySettingsError;
  late Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges;
  late String _eloInputFingerprint;
  Future<Map<String, AdvancementChance>>? _advancementForecast;
  late String _forecastFingerprint;

  @override
  void initState() {
    super.initState();
    _showNextStagePreview = widget.showNextStagePreviewInitially;
    unawaited(_loadPrioritySettings());
    _refreshEloChanges();
    _refreshAdvancementForecast();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _loadPrioritySettings() async {
    try {
      final settings = await TournamentFlowPriorityPreferences().load();
      if (!mounted) return;
      setState(() {
        _prioritySettings = settings;
        _prioritySettingsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _prioritySettingsError =
            'Hinweiseinstellungen konnten nicht geladen werden: $error',
      );
    }
  }

  @override
  void didUpdateWidget(covariant TournamentSecondScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fingerprint = jsonEncode(widget.tournament.toJson());
    if (fingerprint != _eloInputFingerprint) {
      _refreshEloChanges(fingerprint: fingerprint);
    }
    if (fingerprint != _forecastFingerprint) {
      _refreshAdvancementForecast(fingerprint: fingerprint);
    }
  }

  void _refreshEloChanges({String? fingerprint}) {
    _eloInputFingerprint =
        fingerprint ?? jsonEncode(widget.tournament.toJson());
    _eloChanges = TournamentMatchEloService().calculate(widget.tournament);
  }

  void _refreshAdvancementForecast({String? fingerprint}) {
    _forecastFingerprint =
        fingerprint ?? jsonEncode(widget.tournament.toJson());
    _advancementForecast = null;
  }

  Future<Map<String, AdvancementChance>> _forecastFor(
    GroupTournamentRunStage stage,
  ) {
    final cached = _advancementForecast;
    if (cached != null) return cached;
    final tournament = widget.tournament;
    if (tournament.runStages.isEmpty) return Future.value(const {});
    final activeIndex = tournament.activeStageIndex.clamp(
      0,
      tournament.runStages.length - 1,
    );
    if (_nextKnockoutStage(tournament, activeIndex, stage) == null) {
      return _advancementForecast = Future.value(const {});
    }
    return _advancementForecast =
        (widget.forecastService ?? GroupAdvancementForecastService()).calculate(
          tournament: tournament,
          stage: stage,
        );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _previewVerticalController.dispose();
    _previewHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _closeStandaloneWindow() async {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    await SystemNavigator.pop();
  }

  void _returnFromPreview() {
    if (widget.showNextStagePreviewInitially && widget.onClose != null) {
      widget.onClose!();
      return;
    }
    setState(() => _showNextStagePreview = false);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h Std. $m Min. ${s}s';
    return '$m Min. ${s}s';
  }

  String _formatClockTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  List<GroupMatch> _matchesOf(TournamentRunStage? stage) {
    if (stage is GroupTournamentRunStage) {
      return stage.groups.expand(_matchesOfGroup).toList();
    } else if (stage is KnockoutTournamentRunStage) {
      return [...stage.rounds.expand((r) => r), ...stage.placementMatches];
    }
    return [];
  }

  List<GroupMatch> _matchesOfGroup(TournamentGroup group) {
    if (group.knockoutRounds.isEmpty) return group.matches;
    return [
      ...group.knockoutRounds.expand((round) => round),
      ...group.placementMatches,
      ...group.matches.where((match) => match.isDecider),
    ];
  }

  int _countMatchesForProgress(TournamentRunStage stage) {
    final matches = _matchesOf(stage);
    if (stage is KnockoutTournamentRunStage) return matches.length;
    return matches.where((match) => match.hasPlayers).length;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final theme = Theme.of(context);
    final timing = TournamentTiming.snapshot(t, DateTime.now());

    final activeIndex = t.activeStageIndex.clamp(
      0,
      t.runStages.isEmpty ? 0 : t.runStages.length - 1,
    );
    final activeStage = t.runStages.isNotEmpty
        ? t.runStages[activeIndex]
        : null;

    final allMatches = TournamentTiming.matches(t);
    final playedMatches = allMatches.where((m) => m.hasResult).toList();

    final viewWidget = Container(
      decoration: BoxDecoration(
        color: widget.isStandaloneWindow
            ? const Color(0xFF0D1318)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.isStandaloneWindow ? 0 : 16),
      ),
      padding: EdgeInsets.all(widget.isStandaloneWindow ? 20 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF144D34),
                      border: Border.all(color: const Color(0xFF70E0BA)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tv,
                          size: 16,
                          color: Color(0xFF70E0BA),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.isStandaloneWindow
                                ? 'TV-LIVE-ÜBERSICHT'
                                : 'LIVE-TICKER',
                            style: const TextStyle(
                              color: Color(0xFF70E0BA),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    t.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              if (widget.isStandaloneWindow)
                IconButton(
                  tooltip: 'Schließen',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => _closeStandaloneWindow(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _showNextStagePreview
                ? _buildNextStagePreview(context, t, activeIndex, activeStage)
                : _buildOverview(
                    context,
                    t: t,
                    activeIndex: activeIndex,
                    activeStage: activeStage,
                    timing: timing,
                    playedMatches: playedMatches,
                  ),
          ),
        ],
      ),
    );

    if (!widget.isStandaloneWindow) {
      return SizedBox(height: 520, child: viewWidget);
    }
    return viewWidget;
  }

  Widget _buildOverview(
    BuildContext context, {
    required CreatedTournament t,
    required int activeIndex,
    required TournamentRunStage? activeStage,
    required TimingSnapshot timing,
    required List<GroupMatch> playedMatches,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1000 && constraints.maxHeight >= 620;
        final allTournamentMatches = TournamentTiming.matches(t);
        final playedCount = allTournamentMatches
            .where((match) => match.hasPlayers && match.hasResult)
            .length;
        final totalMatchCount = t.runStages.isEmpty
            ? allTournamentMatches.where((match) => match.hasPlayers).length
            : t.runStages.fold(
                0,
                (total, stage) => total + _countMatchesForProgress(stage),
              );
        final stageMatchCounts = activeStage == null
            ? null
            : _matchesOf(activeStage);
        final stagePlayedCount = stageMatchCounts
            ?.where((match) => match.hasResult)
            .length;
        final stageTotalCount = activeStage == null
            ? null
            : _countMatchesForProgress(activeStage);

        Widget content;
        if (activeStage is KnockoutTournamentRunStage) {
          content = _buildBracketPreview(
            t,
            activeStage,
            activeIndex,
            isActiveStage: true,
          );
        } else if (!wide) {
          content = SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBoardsAndPriorityPanel(
                  context,
                  t,
                  activeIndex,
                  activeStage,
                  expand: false,
                ),
                const SizedBox(height: 16),
                _buildRecentMatchesAndEloPanel(
                  context,
                  t,
                  playedMatches,
                  expand: false,
                ),
                const SizedBox(height: 16),
                _buildStandingsAndPreviewControl(
                  context,
                  t,
                  activeIndex,
                  activeStage,
                  expand: false,
                ),
              ],
            ),
          );
        } else {
          content = Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildBoardsAndPriorityPanel(
                        context,
                        t,
                        activeIndex,
                        activeStage,
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: _buildStandingsAndPreviewControl(
                        context,
                        t,
                        activeIndex,
                        activeStage,
                        expand: true,
                        showPreviewButton: false,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 6,
                    child: _buildRecentMatchesAndEloPanel(
                      context,
                      t,
                      playedMatches,
                      expand: false,
                      maxResults: 4,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: _buildOverviewPreviewAction(
                      context,
                      t,
                      activeIndex,
                      activeStage,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Icon(Icons.timer, size: 20, color: Color(0xFF70E0BA)),
                  Text(
                    'Turnieruhr: ${_formatDuration(timing.elapsed)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '$playedCount/$totalMatchCount gespielt',
                    style: const TextStyle(
                      color: Color(0xFF70E0BA),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (stageMatchCounts != null &&
                      activeStage is KnockoutTournamentRunStage)
                    Text(
                      '${activeStage.name}: '
                      '$stagePlayedCount/$stageTotalCount',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  if (timing.forecast != null)
                    Text(
                      'Ende ca. ${_formatClockTime(timing.forecast!)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  Widget _buildStandingsAndPreviewControl(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? stage, {
    bool expand = true,
    bool showPreviewButton = true,
  }) {
    final hasNextKnockout = _nextKnockoutStage(t, activeIndex, stage) != null;
    final showInlinePreview = _showInlineNextStagePreview && hasNextKnockout;
    final standings = _buildStandingsPanel(
      context,
      t,
      stage,
      full: true,
      expand: false,
    );
    final panel = _showPrognosis
        ? _buildKoPrognosisPanel(context, t, activeIndex, stage, expand: false)
        : standings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('Tabellen & Zwischenstände'),
              icon: Icon(Icons.table_chart_outlined),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Siegprognose & Weiterkommen'),
              icon: Icon(Icons.account_tree_outlined),
            ),
          ],
          selected: {_showPrognosis},
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) {
              setState(() => _showPrognosis = selected.first);
            }
          },
        ),
        const SizedBox(height: 8),
        if (expand)
          Expanded(
            child: showInlinePreview
                ? _buildInlineNextStagePreview(context, t, activeIndex, stage)
                : SingleChildScrollView(child: panel),
          )
        else
          panel,
        if (hasNextKnockout && !showInlinePreview && showPreviewButton) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => setState(() => _showInlineNextStagePreview = true),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Vorschau für die nächste Etappe'),
          ),
        ],
        if (!expand && showInlinePreview)
          SizedBox(
            height: 620,
            child: _buildInlineNextStagePreview(context, t, activeIndex, stage),
          ),
      ],
    );
  }

  Widget _buildOverviewPreviewAction(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex,
    TournamentRunStage? stage,
  ) {
    final hasNextKnockout =
        _nextKnockoutStage(tournament, activeIndex, stage) != null;
    if (!hasNextKnockout || _showInlineNextStagePreview) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: () => setState(
          () => _showInlineNextStagePreview = !_showInlineNextStagePreview,
        ),
        icon: Icon(
          _showInlineNextStagePreview ? Icons.expand_less : Icons.account_tree,
        ),
        label: Text(
          _showInlineNextStagePreview
              ? 'Vorschau schließen'
              : 'Vorschau für die nächste Etappe',
        ),
      ),
    );
  }

  KnockoutTournamentRunStage? _nextKnockoutStage(
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? activeStage,
  ) {
    if (activeStage is KnockoutTournamentRunStage) return null;
    for (var index = activeIndex + 1; index < t.runStages.length; index++) {
      final stage = t.runStages[index];
      if (stage is KnockoutTournamentRunStage) return stage;
    }
    return null;
  }

  int? _nextKnockoutStageIndex(
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? activeStage,
  ) {
    if (activeStage is KnockoutTournamentRunStage) return null;
    for (var index = activeIndex + 1; index < t.runStages.length; index++) {
      if (t.runStages[index] is KnockoutTournamentRunStage) return index;
    }
    return null;
  }

  Widget _buildNextStagePreview(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? activeStage,
  ) {
    final isViewingKnockout = activeStage is KnockoutTournamentRunStage;
    final stage =
        _nextKnockoutStage(t, activeIndex, activeStage) ??
        (isViewingKnockout ? activeStage : null);
    final stageIndex = _nextKnockoutStageIndex(t, activeIndex, activeStage);
    if (stage == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: Center(
              child: Text(
                'Keine K.-o.-Etappe als Nächstes geplant.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _returnFromPreview,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Zur Übersichtsansicht zurückkehren'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildBracketPreview(
            t,
            stage,
            stageIndex,
            isActiveStage: isViewingKnockout,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _returnFromPreview,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Zur Übersichtsansicht zurückkehren'),
        ),
      ],
    );
  }

  Widget _buildInlineNextStagePreview(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? activeStage,
  ) {
    final stage = _nextKnockoutStage(t, activeIndex, activeStage);
    final stageIndex = _nextKnockoutStageIndex(t, activeIndex, activeStage);
    if (stage == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildBracketPreview(t, stage, stageIndex)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => setState(() => _showInlineNextStagePreview = false),
          icon: const Icon(Icons.expand_less),
          label: const Text('Vorschau schließen'),
        ),
      ],
    );
  }

  Widget _buildBracketPreview(
    CreatedTournament t,
    KnockoutTournamentRunStage stage,
    int? stageIndex, {
    bool isActiveStage = false,
  }) {
    final groupStage =
        !isActiveStage &&
            stageIndex != null &&
            stageIndex > 0 &&
            t.runStages[stageIndex - 1] is GroupTournamentRunStage
        ? t.runStages[stageIndex - 1] as GroupTournamentRunStage
        : null;
    var previewStage = stage;
    if (groupStage != null &&
        stageIndex != null &&
        stageIndex >= 0 &&
        stageIndex < t.stages.length) {
      final runtime = ProductionTournamentRuntime(t);
      final projectedPlayers = runtime.qualifiers(groupStage);
      final presentedPlayers = const GroupStagePreviewService()
          .presentProjectedPlayers(
            stage: groupStage,
            projectedPlayers: projectedPlayers,
            tournament: t,
          );
      final rebuiltStage = runtime.build(
        t.stages[stageIndex],
        presentedPlayers,
      );
      if (rebuiltStage is KnockoutTournamentRunStage) {
        previewStage = rebuiltStage;
      }
    }
    final groupStageIsSet =
        groupStage != null &&
        const GroupStagePreviewService().isStageSet(groupStage);

    final hasGroupStageResults =
        groupStage != null &&
        groupStage.groups.any(
          (group) => group.matches.any((match) => match.countsForStatistics),
        );

    String playerLabel(
      TournamentPlayer? player,
      int roundIndex,
      int matchIndex, {
      required bool home,
    }) {
      if (isActiveStage) {
        if (player != null && !player.name.startsWith('Qualifikant ')) {
          return player.shortDisplayName;
        }
        if (roundIndex == 0) return 'Offen';
        final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
        return 'Gewinner Spiel $sourceMatchNumber';
      }
      if (!hasGroupStageResults) {
        if (roundIndex == 0) {
          return 'Qualifikant offen';
        }
        if (roundIndex > 0) {
          final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
          if (player == null || player.name.startsWith('Qualifikant ')) {
            return 'Gewinner Spiel $sourceMatchNumber';
          }
          return player.name;
        }
        if (player == null || player.name.startsWith('Qualifikant ')) {
          return 'Qualifikant offen';
        }
        return player.name;
      }
      if (roundIndex > 0) {
        final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
        return player?.name ?? 'Gewinner Spiel $sourceMatchNumber';
      }
      if (player == null || player.name.startsWith('Qualifikant ')) {
        return 'Qualifikant offen';
      }
      return player.name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isActiveStage
                    ? '${previewStage.name} · Turnierbaum'
                    : '${previewStage.name} · Turnierbaum-Vorschau',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            if (!widget.showNextStagePreviewInitially)
              IconButton(
                tooltip: 'KO-Vorschau im Vollbild öffnen',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog.fullscreen(
                    child: TournamentSecondScreenView(
                      tournament: t,
                      isStandaloneWindow: true,
                      showNextStagePreviewInitially: true,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                icon: const Icon(Icons.fullscreen, color: Color(0xFF70E0BA)),
              ),
          ],
        ),
        if (groupStage != null &&
            groupStage.groups.any(
              (group) =>
                  group.matches.any((match) => match.countsForStatistics),
            ))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              groupStageIsSet
                  ? 'Die Setzplätze der Etappe stehen fest.'
                  : 'Die angezeigten Plätze entsprechen dem aktuellen Tabellenstand und sind vorläufig.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: previewStage.rounds.isEmpty
              ? const Center(
                  child: Text(
                    'Für diese Etappe ist noch kein Turnierbaum vorhanden.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final rounds = previewStage.rounds;
                    const roundWidth = 280.0;
                    const roundGap = 28.0;
                    const roundHeaderHeight = 42.0;
                    final boardWidth =
                        rounds.length * roundWidth +
                        (rounds.length - 1) * roundGap;
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final minimumBoardHeight =
                        rounds.first.length * 88 * scale + roundHeaderHeight;
                    final boardHeight = max(
                      constraints.maxHeight + 1,
                      minimumBoardHeight,
                    );

                    return Scrollbar(
                      controller: _previewVerticalController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const ValueKey('knockout-preview-vertical-scroll'),
                        controller: _previewVerticalController,
                        child: SizedBox(
                          height: boardHeight,
                          child: Scrollbar(
                            controller: _previewHorizontalController,
                            thumbVisibility: true,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              key: const ValueKey(
                                'knockout-preview-horizontal-scroll',
                              ),
                              controller: _previewHorizontalController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: boardWidth,
                                height: boardHeight,
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter:
                                            _KnockoutPreviewConnectorPainter(
                                              roundCounts: [
                                                for (final round in rounds)
                                                  round.length,
                                              ],
                                              roundWidth: roundWidth,
                                              roundGap: roundGap,
                                              topOffset: roundHeaderHeight,
                                            ),
                                      ),
                                    ),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (
                                          var roundIndex = 0;
                                          roundIndex < rounds.length;
                                          roundIndex++
                                        )
                                          Container(
                                            width: roundWidth,
                                            margin: EdgeInsets.only(
                                              right:
                                                  roundIndex < rounds.length - 1
                                                  ? roundGap
                                                  : 0,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                SizedBox(
                                                  height: roundHeaderHeight,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.topLeft,
                                                    child: Text(
                                                      knockoutRoundName(
                                                        roundIndex,
                                                        rounds.length,
                                                      ),
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF70E0BA,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceEvenly,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      for (
                                                        var matchIndex = 0;
                                                        matchIndex <
                                                            rounds[roundIndex]
                                                                .length;
                                                        matchIndex++
                                                      )
                                                        _buildBracketMatchPreview(
                                                          rounds[roundIndex][matchIndex],
                                                          roundIndex:
                                                              roundIndex,
                                                          matchIndex:
                                                              matchIndex,
                                                          homeLabel: playerLabel(
                                                            rounds[roundIndex][matchIndex]
                                                                .homePlayer,
                                                            roundIndex,
                                                            matchIndex,
                                                            home: true,
                                                          ),
                                                          awayLabel: playerLabel(
                                                            rounds[roundIndex][matchIndex]
                                                                .awayPlayer,
                                                            roundIndex,
                                                            matchIndex,
                                                            home: false,
                                                          ),
                                                          matchNumber:
                                                              matchIndex + 1,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBracketMatchPreview(
    GroupMatch match, {
    required int roundIndex,
    required int matchIndex,
    required String homeLabel,
    required String awayLabel,
    required int matchNumber,
  }) {
    final homeIsCertain =
        homeLabel.contains('vorläufig') || homeLabel.contains('gesetzt');
    final awayIsCertain =
        awayLabel.contains('vorläufig') || awayLabel.contains('gesetzt');
    return Container(
      key: ValueKey('knockout-preview-match-$roundIndex-$matchIndex'),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFF14202B),
        border: Border.all(color: const Color(0xFF263D52)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            match.label ?? 'Spiel $matchNumber',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 3),
          _buildBracketParticipant(homeLabel, isCertain: homeIsCertain),
          const Divider(color: Color(0xFF263D52), height: 8),
          _buildBracketParticipant(awayLabel, isCertain: awayIsCertain),
        ],
      ),
    );
  }

  Widget _buildBracketParticipant(String label, {required bool isCertain}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isCertain ? const Color(0xFF86EFAC) : Colors.white70,
              fontWeight: isCertain ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------
  // HELPER: Standings Panel (Vollansicht)
  // ------------------------------------------
  Widget _buildStandingsPanel(
    BuildContext context,
    CreatedTournament t,
    TournamentRunStage? stage, {
    bool full = false,
    bool expand = true,
  }) {
    if (stage == null) {
      return const Center(
        child: Text(
          'Keine aktive Etappe vorhanden',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    if (stage is GroupTournamentRunStage) {
      final cards = [
        for (var i = 0; i < stage.groups.length; i++)
          _buildGroupStandingsCard(
            context,
            stage.groups[i],
            groupNumber: i + 1,
            qualificationPlan: stage.qualificationPlan,
            tieBreakers: stage.tieBreakers,
            full: full,
          ),
      ];
      final wrapContent = full
          ? LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 572 ? 2 : 1;
                final cardWidth =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final card in cards)
                      SizedBox(width: cardWidth, child: card),
                  ],
                );
              },
            )
          : Wrap(spacing: 12, runSpacing: 12, children: cards);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard, size: 20, color: Color(0xFF70E0BA)),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Tabellen & Zwischenstände',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (expand)
            Expanded(child: SingleChildScrollView(child: wrapContent))
          else
            wrapContent,
        ],
      );
    }

    return Card(
      color: const Color(0xFF16202A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'K.-o.-Runde: ${stage.name}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aktuelle Spiele und Paarungen siehe Spielansetzungen.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupStandingsCard(
    BuildContext context,
    TournamentGroup group, {
    required int groupNumber,
    required QualificationPlan? qualificationPlan,
    required List<String> tieBreakers,
    bool full = false,
  }) {
    final standings = _calculateGroupStandings(group, tieBreakers);
    final fixedPlaces = qualificationPlan == null
        ? 2
        : groupNumber - 1 < qualificationPlan.fixedByGroup.length
        ? qualificationPlan.fixedByGroup[groupNumber - 1]
        : qualificationPlan.fixedPerGroup;
    final playedMatches = group.matches
        .where((match) => match.hasPlayers && match.hasResult)
        .length;
    final totalMatches = group.matches
        .where((match) => match.hasPlayers)
        .length;

    return Container(
      constraints: BoxConstraints(
        minWidth: full ? 280 : 220,
        maxWidth: full ? double.infinity : 340,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF14202B),
        border: Border.all(color: const Color(0xFF263D52)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                group.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF70E0BA),
                ),
              ),
              Text(
                '$playedMatches/$totalMatches',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF70E0BA),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Top $fixedPlaces weiter',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
          const Divider(color: Color(0xFF263D52), height: 12),
          StandingsTable(
            standings: standings,
            group: group,
            groupNumber: groupNumber,
            qualificationPlan: qualificationPlan,
            tieBreakers: tieBreakers,
            compact: full,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------
  // SLIDE 1 PROGNOSIS: KO-Prognose (Turnierbaum-Vorschau)
  // ------------------------------------------
  Widget _buildKoPrognosisPanel(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? currentStage, {
    bool expand = true,
  }) {
    // Find upcoming or current KO stage
    KnockoutTournamentRunStage? koStage;
    if (currentStage is KnockoutTournamentRunStage) {
      koStage = currentStage;
    } else {
      for (var i = activeIndex + 1; i < t.runStages.length; i++) {
        if (t.runStages[i] is KnockoutTournamentRunStage) {
          koStage = t.runStages[i] as KnockoutTournamentRunStage;
          break;
        }
      }
    }

    final hasPrognosis =
        currentStage is GroupTournamentRunStage && koStage != null;
    final prognosisContent = hasPrognosis
        ? _buildContenderPrognosisList(context, currentStage)
        : (koStage != null
              ? _buildKnockoutRoundsPreview(context, koStage)
              : const Center(
                  child: Text(
                    'Keine K.-o.-Phase im aktuellen Turnier geplant.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF14202B),
        border: Border.all(color: const Color(0xFF263D52)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                size: 20,
                color: Color(0xFF70E0BA),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hasPrognosis
                      ? 'KO-Prognose & Weiterkommen'
                      : 'Turnierbaum Vorschau',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasPrognosis
                ? 'Vorschau der K.-o.-Paarungen basierend auf aktuellen Tabellenständen und Siegesraten:'
                : 'Turnierbaum der finalen Phase:',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 12),
          if (expand)
            Expanded(child: SingleChildScrollView(child: prognosisContent))
          else
            prognosisContent,
        ],
      ),
    );
  }

  Widget _buildContenderPrognosisList(
    BuildContext context,
    GroupTournamentRunStage groupStage,
  ) {
    return FutureBuilder<Map<String, AdvancementChance>>(
      future: _forecastFor(groupStage),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Siegprognose konnte nicht berechnet werden: ${snapshot.error}',
            style: const TextStyle(color: Colors.redAccent),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final forecast = snapshot.data!;
        final plan = groupStage.qualificationPlan;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (
              var groupIndex = 0;
              groupIndex < groupStage.groups.length;
              groupIndex++
            )
              Builder(
                builder: (context) {
                  final group = groupStage.groups[groupIndex];
                  final standings = _calculateGroupStandings(
                    group,
                    groupStage.tieBreakers,
                  );
                  final fixedPlaces = plan == null
                      ? 0
                      : groupIndex < plan.fixedByGroup.length
                      ? plan.fixedByGroup[groupIndex]
                      : plan.fixedPerGroup;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101922),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF70E0BA),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (var rank = 0; rank < standings.length; rank++)
                          Builder(
                            builder: (context) {
                              final standing = standings[rank];
                              final chance =
                                  forecast[standing.player.profileId ??
                                      standing.player.name] ??
                                  const AdvancementChance(
                                    groupWinProbability: 0,
                                    advancementProbability: 0,
                                  );
                              final isCertain = const QualificationCertainty()
                                  .isCertain(
                                    standing: standing,
                                    place: rank + 1,
                                    fixedPlaces: fixedPlaces,
                                    standings: standings,
                                    matches: group.matches,
                                    tieBreakers: groupStage.tieBreakers,
                                  );
                              final label =
                                  '${chance.groupWinProbability.toStringAsFixed(1)} % Sieg · '
                                  '${chance.advancementProbability.toStringAsFixed(1)} % weiter';
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '${rank + 1}. ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isCertain
                                            ? const Color(0xFF86EFAC)
                                            : Colors.white70,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        standing.player.name,
                                        style: TextStyle(
                                          fontWeight: isCertain
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message:
                                          'Siegchance: ${chance.groupWinProbability.toStringAsFixed(1)} %\n'
                                          'Weiterkommen: ${chance.advancementProbability.toStringAsFixed(1)} %',
                                      child: Text(
                                        label,
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isCertain
                                              ? const Color(0xFF86EFAC)
                                              : Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildKnockoutRoundsPreview(
    BuildContext context,
    KnockoutTournamentRunStage koStage,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < koStage.rounds.length; i++) ...[
          Text(
            knockoutRoundName(i, koStage.rounds.length),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF70E0BA),
            ),
          ),
          const SizedBox(height: 4),
          for (final m in koStage.rounds[i])
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF101922),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${m.homePlayer?.name ?? "Offen"} vs. ${m.awayPlayer?.name ?? "Offen"}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  if (m.hasResult)
                    Text(
                      '${m.homeScore} : ${m.awayScore}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF70E0BA),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ------------------------------------------
  // SLIDE 2 HELPER: Boards & Priorisierte Partien
  // ------------------------------------------
  Widget _buildBoardsAndPriorityPanel(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? stage, {
    bool expand = true,
  }) {
    final flowPriority = TournamentFlowPriority.forStage(
      stage,
      settings: _prioritySettings,
    );
    final recommendedGroups = stage is GroupTournamentRunStage
        ? [
            for (final group in stage.groups)
              RecommendedMatchGroup(
                name: group.name,
                matches: _matchesOfGroup(group),
                isDelayed: flowPriority.delayedGroups.contains(group.name),
                playedMatches: _matchesOfGroup(
                  group,
                ).where((match) => match.hasPlayers && match.hasResult).length,
                totalMatches: _matchesOfGroup(
                  group,
                ).where((match) => match.hasPlayers).length,
              ),
          ]
        : [
            if (stage != null)
              RecommendedMatchGroup(
                name: stage.name,
                matches: _matchesOf(stage),
                playedMatches: _matchesOf(
                  stage,
                ).where((match) => match.hasResult).length,
                totalMatches: _countMatchesForProgress(stage),
              ),
          ];
    final hasOpenMatches = recommendedGroups.any(
      (group) =>
          group.matches.any((match) => match.hasPlayers && !match.isResolved),
    );
    final recommendedContent = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final notice in flowPriority.notices)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: TournamentDisplayPalette.cardEmphasis,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TournamentDisplayPalette.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.priority_high,
                    size: 18,
                    color: TournamentDisplayPalette.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      notice,
                      style: const TextStyle(
                        color: TournamentDisplayPalette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_prioritySettingsError case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error, style: const TextStyle(color: Colors.amber)),
            ),
          RecommendedMatchesTable(
            groups: recommendedGroups,
            prioritizedMatches: flowPriority.prioritizedMatches,
            deprioritizedMatches: flowPriority.deprioritizedMatches,
            emptyMessage: 'Keine offenen Partien in dieser Etappe.',
            dense: true,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Spielplan',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        if (expand)
          Expanded(child: recommendedContent)
        else
          SizedBox(height: 240, child: recommendedContent),
        if (!hasOpenMatches && expand)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Keine offenen Partien in dieser Etappe.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------
  // SLIDE 3 HELPER: Zuletzt beendet + Live Elo
  // ------------------------------------------
  Widget _buildRecentMatchesAndEloPanel(
    BuildContext context,
    CreatedTournament t,
    List<GroupMatch> playedMatches, {
    bool expand = true,
    int maxResults = 2,
  }) {
    final enteredOrder = {
      for (var index = 0; index < playedMatches.length; index++)
        playedMatches[index]: index,
    };
    final recent = playedMatches.toList()
      ..sort((left, right) {
        final leftDate =
            left.finishedAt ?? left.startedAt ?? t.startedAt ?? t.createdAt;
        final rightDate =
            right.finishedAt ?? right.startedAt ?? t.startedAt ?? t.createdAt;
        final dateComparison = rightDate.compareTo(leftDate);
        if (dateComparison != 0) return dateComparison;
        return (enteredOrder[right] ?? 0).compareTo(enteredOrder[left] ?? 0);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.history, size: 20, color: Color(0xFF70E0BA)),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Zuletzt beendete Matches',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final displayedRecent = recent.take(maxResults).toList();
            final recentList =
                FutureBuilder<Map<String, List<TournamentMatchEloChange>>>(
                  future: _eloChanges,
                  builder: (context, snapshot) {
                    final itemExtent =
                        66 * MediaQuery.textScalerOf(context).scale(1);
                    return SizedBox(
                      key: const ValueKey('recent-results-scroll'),
                      height: displayedRecent.isEmpty
                          ? itemExtent
                          : itemExtent * displayedRecent.length,
                      child: snapshot.hasError
                          ? const Center(
                              child: Text(
                                'Ranglistenänderungen konnten nicht geladen werden.',
                                style: TextStyle(color: Colors.amber),
                              ),
                            )
                          : displayedRecent.isEmpty
                          ? const Center(
                              child: Text(
                                'Noch keine beendeten Partien vorhanden.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            )
                          : Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < displayedRecent.length;
                                  index++
                                ) ...[
                                  if (index > 0)
                                    const Divider(
                                      height: 1,
                                      color: TournamentDisplayPalette.border,
                                    ),
                                  _buildRecentMatchRow(
                                    context,
                                    t,
                                    displayedRecent[index],
                                    _changesForMatch(
                                      t,
                                      displayedRecent[index],
                                      snapshot.data,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    );
                  },
                );
            return expand
                ? Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: recentList,
                    ),
                  )
                : recentList;
          },
        ),
      ],
    );
  }

  List<TournamentMatchEloChange> _changesForMatch(
    CreatedTournament tournament,
    GroupMatch match,
    Map<String, List<TournamentMatchEloChange>>? changes,
  ) {
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return const [];
    }
    final key = const LocalEloCalculator().matchKey(tournament, match);
    return key == null ? const [] : changes?[key] ?? const [];
  }

  Widget _buildRecentMatchRow(
    BuildContext context,
    CreatedTournament tournament,
    GroupMatch m,
    List<TournamentMatchEloChange> eloChanges,
  ) => RecentMatchResultLogEntry(
    tournament: tournament,
    match: m,
    eloChanges: eloChanges,
  );

  List<PlayerStanding> _calculateGroupStandings(
    TournamentGroup group,
    List<String> tieBreakers,
  ) => const GroupStandingsEngine().calculate(
    group,
    tieBreakers,
    tournament: widget.tournament,
  );
}

class _KnockoutPreviewConnectorPainter extends CustomPainter {
  const _KnockoutPreviewConnectorPainter({
    required this.roundCounts,
    required this.roundWidth,
    required this.roundGap,
    required this.topOffset,
  });

  final List<int> roundCounts;
  final double roundWidth;
  final double roundGap;
  final double topOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF466075)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final contentHeight = size.height - topOffset;

    for (
      var roundIndex = 0;
      roundIndex < roundCounts.length - 1;
      roundIndex++
    ) {
      final currentCount = roundCounts[roundIndex];
      final nextCount = roundCounts[roundIndex + 1];
      if (currentCount == 0 || nextCount == 0) continue;

      final left = roundIndex * (roundWidth + roundGap) + roundWidth;
      final middle = left + roundGap / 2;
      final right = left + roundGap;
      for (var matchIndex = 0; matchIndex < currentCount; matchIndex++) {
        final nextIndex = ((matchIndex + 0.5) * nextCount / currentCount)
            .floor()
            .clamp(0, nextCount - 1);
        final startY =
            topOffset + contentHeight * (matchIndex + 0.5) / currentCount;
        final endY = topOffset + contentHeight * (nextIndex + 0.5) / nextCount;
        canvas.drawPath(
          Path()
            ..moveTo(left, startY)
            ..lineTo(middle, startY)
            ..lineTo(middle, endY)
            ..lineTo(right, endY),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KnockoutPreviewConnectorPainter oldDelegate) =>
      true;
}
