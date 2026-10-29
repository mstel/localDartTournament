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
import '../../../application/player_withdrawal_service.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../application/tournament_flow_priority_preferences.dart';
import '../../../application/tournament_timing.dart';
import '../../../application/group_advancement_forecast_service.dart';
import '../../../domain/engines/group_advancement_forecast_engine.dart';
import 'standings_table.dart';
import 'recommended_matches_table.dart';
import '../../../../statistics/domain/best_performance.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../../rankings/domain/local_elo_calculator.dart';

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
      return stage.groups.expand((g) => g.matches).toList();
    } else if (stage is KnockoutTournamentRunStage) {
      return [...stage.rounds.expand((r) => r), ...stage.placementMatches];
    }
    return [];
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
        if (!wide) {
          return SingleChildScrollView(
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
                _buildProgressAndBestPerformancesPanel(
                  context: context,
                  t: t,
                  expand: false,
                ),
                const SizedBox(height: 16),
                _buildStandingsAndPreviewControl(
                  context,
                  t,
                  activeIndex,
                  activeStage,
                  timing: timing,
                  expand: false,
                ),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildBoardsAndPriorityPanel(
                      context,
                      t,
                      activeIndex,
                      activeStage,
                      expand: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 4,
                    child: _buildRecentMatchesAndEloPanel(
                      context,
                      t,
                      playedMatches,
                      expand: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 5,
                    child: _buildProgressAndBestPerformancesPanel(
                      context: context,
                      t: t,
                      expand: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildStandingsAndPreviewControl(
                      context,
                      t,
                      activeIndex,
                      activeStage,
                      timing: timing,
                      expand: true,
                    ),
                  ),
                ],
              ),
            ),
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
    required TimingSnapshot timing,
    bool expand = true,
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
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Icon(Icons.timer, size: 20, color: Color(0xFF70E0BA)),
              Text(
                'Turnieruhr: ${_formatDuration(timing.elapsed)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (timing.forecast != null)
                Text(
                  'Voraussichtliches Ende: ${_formatClockTime(timing.forecast!)}',
                  style: const TextStyle(color: Colors.white),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
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
        if (hasNextKnockout && !showInlinePreview) ...[
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
        Expanded(child: _buildBracketPreview(t, stage, stageIndex)),
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
    int? stageIndex,
  ) {
    final groupStage =
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
                '${previewStage.name} · Turnierbaum-Vorschau',
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
                        rounds.first.length * 96 * scale + roundHeaderHeight;
                    final boardHeight = max(
                      constraints.maxHeight + 180,
                      minimumBoardHeight,
                    );

                    return Scrollbar(
                      controller: _previewVerticalController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        key: const ValueKey('knockout-preview-vertical-scroll'),
                        controller: _previewVerticalController,
                        child: SizedBox(
                          width: boardWidth,
                          height: boardHeight,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _KnockoutPreviewConnectorPainter(
                                    roundCounts: [
                                      for (final round in rounds) round.length,
                                    ],
                                    roundWidth: roundWidth,
                                    roundGap: roundGap,
                                    topOffset: roundHeaderHeight,
                                  ),
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var roundIndex = 0;
                                    roundIndex < rounds.length;
                                    roundIndex++
                                  )
                                    Container(
                                      width: roundWidth,
                                      margin: EdgeInsets.only(
                                        right: roundIndex < rounds.length - 1
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
                                              alignment: Alignment.topLeft,
                                              child: Text(
                                                knockoutRoundName(
                                                  roundIndex,
                                                  rounds.length,
                                                ),
                                                style: const TextStyle(
                                                  color: Color(0xFF70E0BA),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                for (
                                                  var matchIndex = 0;
                                                  matchIndex <
                                                      rounds[roundIndex].length;
                                                  matchIndex++
                                                )
                                                  _buildBracketMatchPreview(
                                                    rounds[roundIndex][matchIndex],
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
                                                    matchNumber: matchIndex + 1,
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
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBracketMatchPreview(
    GroupMatch match, {
    required String homeLabel,
    required String awayLabel,
    required int matchNumber,
  }) {
    final homeIsCertain =
        homeLabel.contains('vorläufig') || homeLabel.contains('gesetzt');
    final awayIsCertain =
        awayLabel.contains('vorläufig') || awayLabel.contains('gesetzt');
    return Container(
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
        maxWidth: full ? 420 : 340,
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
                '$playedMatches/$totalMatches gespielt',
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
                matches: group.matches,
                isDelayed: flowPriority.delayedGroups.contains(group.name),
              ),
          ]
        : [
            RecommendedMatchGroup(
              name: stage?.name ?? 'Partien',
              matches: _matchesOf(stage),
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
            emptyMessage: 'Keine offenen Partien in dieser Etappe.',
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(
              Icons.sports_esports,
              size: 20,
              color: TournamentDisplayPalette.accent,
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Empfohlene Partien',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
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
            final recentList =
                FutureBuilder<Map<String, List<TournamentMatchEloChange>>>(
                  future: _eloChanges,
                  builder: (context, snapshot) {
                    final itemExtent =
                        96 * MediaQuery.textScalerOf(context).scale(1);
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 560 ? 2 : 1;
                        return SizedBox(
                          height: itemExtent * 2 + 8,
                          child: snapshot.hasError
                              ? const Center(
                                  child: Text(
                                    'Ranglistenänderungen konnten nicht geladen werden.',
                                    style: TextStyle(color: Colors.amber),
                                  ),
                                )
                              : recent.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Noch keine beendeten Partien vorhanden.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : GridView.builder(
                                  key: const ValueKey('recent-results-scroll'),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisExtent: itemExtent,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                      ),
                                  itemCount: recent.length,
                                  itemBuilder: (context, index) =>
                                      _buildRecentMatchRow(
                                        context,
                                        t,
                                        recent[index],
                                        _changesForMatch(
                                          t,
                                          recent[index],
                                          snapshot.data,
                                        ),
                                      ),
                                ),
                        );
                      },
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
  ) {
    return Container(
      key: ValueKey(
        'recent-result-${m.round}-'
        '${m.homePlayer?.profileId ?? m.homePlayer?.name}-'
        '${m.awayPlayer?.profileId ?? m.awayPlayer?.name}',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TournamentDisplayPalette.card,
        border: Border.all(
          color: TournamentDisplayPalette.border.withAlpha(150),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _recentPlayerLabel(
                  tournament,
                  m,
                  m.homePlayer,
                  textAlign: TextAlign.start,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: TournamentDisplayPalette.cardEmphasis,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: TournamentDisplayPalette.border),
                ),
                child: Text(
                  '${m.homeScore ?? 0} : ${m.awayScore ?? 0}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: TournamentDisplayPalette.accent,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: _recentPlayerLabel(
                  tournament,
                  m,
                  m.awayPlayer,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final change in eloChanges)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: TournamentDisplayPalette.cardEmphasis,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: TournamentDisplayPalette.border.withAlpha(150),
                      ),
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${change.rankingName}: '),
                          _eloDeltaSpan(change.homeDelta),
                          const TextSpan(text: ' / '),
                          _eloDeltaSpan(change.awayDelta),
                          const TextSpan(text: ' Elo'),
                        ],
                      ),
                      style: TextStyle(
                        color: TournamentDisplayPalette.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

  Widget _recentPlayerLabel(
    CreatedTournament tournament,
    GroupMatch match,
    TournamentPlayer? player, {
    required TextAlign textAlign,
  }) {
    if (player == null) {
      return const Text(
        '?',
        style: TextStyle(color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }
    final isWinner = match.winner == player;
    final isLoser = match.loser == player;
    final status = _recentPlayerStatus(tournament, match, player);
    final statusColor = status == 'Ausgeschieden'
        ? const Color(0xFFEF9A9A)
        : const Color(0xFF86EFAC);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          player.shortDisplayName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isWinner
                ? const Color(0xFF86EFAC)
                : isLoser
                ? const Color(0xFFEF9A9A)
                : Colors.white,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
        if (status != null)
          Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
          ),
      ],
    );
  }

  String? _recentPlayerStatus(
    CreatedTournament tournament,
    GroupMatch match,
    TournamentPlayer player,
  ) {
    if (PlayerWithdrawalService.policy(tournament, player) != null) {
      return 'Ausgeschieden';
    }
    for (final stage in tournament.runStages) {
      if (stage is GroupTournamentRunStage) {
        final groupIndex = stage.groups.indexWhere(
          (group) => group.matches.contains(match),
        );
        if (groupIndex < 0) continue;
        final group = stage.groups[groupIndex];
        final standings = _calculateGroupStandings(group, stage.tieBreakers);
        final place = standings.indexWhere(
          (standing) => standing.player == player,
        );
        if (place < 0) return null;
        final plan = stage.qualificationPlan;
        final fixedPlaces = plan == null
            ? 2
            : groupIndex < plan.fixedByGroup.length
            ? plan.fixedByGroup[groupIndex]
            : plan.fixedPerGroup;
        if (const QualificationCertainty().isCertain(
          standing: standings[place],
          place: place + 1,
          fixedPlaces: fixedPlaces,
          standings: standings,
          matches: group.matches,
          tieBreakers: stage.tieBreakers,
        )) {
          return 'Gesetzt';
        }
        final groupComplete = group.matches
            .where((item) => item.hasPlayers)
            .every((item) => item.isResolved);
        final eligibleForExtra =
            plan != null &&
            plan.extraCount > 0 &&
            plan.extraGroups.contains(groupIndex + 1) &&
            place + 1 == plan.extraRank;
        if (groupComplete && place + 1 > fixedPlaces && !eligibleForExtra) {
          return 'Ausgeschieden';
        }
        return null;
      }
      if (stage is KnockoutTournamentRunStage &&
          stage.matches.contains(match)) {
        final playerKey = PlayerWithdrawalService.key(player);
        final losses = stage.matches
            .where(
              (item) =>
                  item.hasResult &&
                  item.loser != null &&
                  PlayerWithdrawalService.key(item.loser!) == playerKey,
            )
            .length;
        if (losses >= stage.eliminationLossLimit) return 'Ausgeschieden';
        return null;
      }
    }
    return null;
  }

  String _signedDelta(int delta) => delta > 0 ? '+$delta' : '$delta';

  TextSpan _eloDeltaSpan(int? delta) {
    final color = delta == null || delta == 0
        ? const Color(0xFFB0BEC5)
        : delta > 0
        ? const Color(0xFF86EFAC)
        : const Color(0xFFEF9A9A);
    return TextSpan(
      text: delta == null ? '–' : _signedDelta(delta),
      style: TextStyle(color: color),
    );
  }

  // ------------------------------------------
  // SLIDE 4 HELPER: Etappenfortschritt & Bestleistungen
  // ------------------------------------------
  Widget _buildProgressAndBestPerformancesPanel({
    required BuildContext context,
    required CreatedTournament t,
    bool expand = true,
  }) {
    // Gather best performances from all matches
    final allPerformances = <BestPerformance>[];
    for (final stage in t.runStages) {
      for (final m in _matchesOf(stage)) {
        allPerformances.addAll(m.bestPerformances);
      }
    }

    final oneEighties = allPerformances
        .where((p) => p.type == BestPerformanceType.score180)
        .toList();
    final oneSeventies = allPerformances
        .where((p) => p.type == BestPerformanceType.score170)
        .toList();
    final highFinishes = allPerformances
        .where((p) => p.type == BestPerformanceType.highFinish)
        .toList();
    final shortLegs = allPerformances
        .where((p) => p.type == BestPerformanceType.shortLeg)
        .toList();
    final bestHighFinish = highFinishes.isEmpty
        ? null
        : highFinishes.reduce(
            (left, right) =>
                (left.value ?? 0) >= (right.value ?? 0) ? left : right,
          );
    final bestShortLeg = shortLegs.isEmpty
        ? null
        : shortLegs.reduce(
            (left, right) =>
                (left.value ?? 99) <= (right.value ?? 99) ? left : right,
          );
    String namesFor(List<BestPerformance> performances) => performances
        .map((performance) => performance.playerName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .take(3)
        .join(', ');

    final breakdownContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fortschritt nach Etappen',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < t.runStages.length; i++)
          ..._buildStageProgressItems(t.runStages[i], i),

        const SizedBox(height: 10),
        // Best Performances section
        const Text(
          'Bestleistungen & Highlights:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF14202B),
            border: Border.all(color: const Color(0xFF263D52)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.spaceAround,
                spacing: 16,
                runSpacing: 12,
                children: [
                  _buildHighlightItem(
                    '170+',
                    '${oneSeventies.length}x geworfen',
                    player: namesFor(oneSeventies),
                  ),
                  _buildHighlightItem(
                    '180er',
                    '${oneEighties.length}x geworfen',
                    player: namesFor(oneEighties),
                  ),
                  _buildHighlightItem(
                    'High Finish',
                    bestHighFinish == null
                        ? '–'
                        : '${bestHighFinish.value ?? 100} Punkte',
                    player: bestHighFinish?.playerName,
                  ),
                  _buildHighlightItem(
                    'Bestes Shortleg',
                    bestShortLeg == null
                        ? '–'
                        : '${bestShortLeg.value ?? 18} Darts',
                    player: bestShortLeg?.playerName,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stages breakdown
        if (expand)
          Expanded(child: SingleChildScrollView(child: breakdownContent))
        else
          breakdownContent,
      ],
    );
  }

  List<Widget> _buildStageProgressItems(TournamentRunStage stage, int index) {
    return [
      Builder(
        builder: (context) {
          final matches = _matchesOf(
            stage,
          ).where((match) => match.hasPlayers).toList();
          final played = matches.where((match) => match.hasResult).length;
          final total = matches.length;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF142B40),
              border: Border.all(color: const Color(0xFF244B6B)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}. ${stage.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0
                              ? (played / total).clamp(0.0, 1.0)
                              : 0.0,
                          minHeight: 6,
                          backgroundColor: const Color(0xFF20384D),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFC4A96F),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$played/$total gespielt',
                      style: const TextStyle(
                        color: Color(0xFFC4A96F),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ];
  }

  Widget _buildHighlightItem(String label, String value, {String? player}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF70E0BA),
          ),
        ),
        if (player != null && player.trim().isNotEmpty)
          Text(
            player,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
      ],
    );
  }

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
