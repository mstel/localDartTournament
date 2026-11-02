import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../../shared/theme/tournament_display_palette.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/second_screen_widget_placement.dart';
import '../../../application/tournament_director_snapshot.dart';
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
import '../../../data/app_database.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../../rankings/application/local_ranking_elo_service.dart';
import '../../../../rankings/domain/local_elo_calculator.dart';
import '../../../../rankings/domain/local_ranking.dart';
import '../../../data/tournament_storage.dart';
import 'recent_match_result_card.dart';

const Map<String, String> _monitorWidgetTitles = {
  'standings': 'Tabellen & Zwischenstände',
  'forecast': 'Siegprognose & Weiterkommen',
  'combined': 'Tabellen & Prognose (Umschalter)',
  'recent': 'Zuletzt beendete Matches',
  'boards': 'Boards & nächste Begegnungen',
  'liveBoard': 'Live Board Ansicht',
  'stageProgress': 'Fortschritt nach Etappen',
  'highlights': 'Bestleistungen & Highlights',
  'ranking': 'Rangliste',
};

enum _StandingsDisplayMode { standings, forecast }

enum _MonitorLayoutAction { add, save, load, reset, standard }

const String _standardMonitorLayoutName = 'Standard';

const List<SecondScreenWidgetPlacement> _defaultMonitorLayout = [
  SecondScreenWidgetPlacement(
    widgetId: 'boards',
    widthUnits: 2,
    heightUnits: 2,
    columnIndex: 0,
  ),
  SecondScreenWidgetPlacement(
    widgetId: 'standings',
    widthUnits: 2,
    heightUnits: 2,
    columnIndex: 1,
  ),
  SecondScreenWidgetPlacement(
    widgetId: 'recent',
    widthUnits: 2,
    columnIndex: 0,
  ),
  SecondScreenWidgetPlacement(widgetId: 'stageProgress', columnIndex: 1),
];

/// Feste, responsive Info-Tafel für den Vereinsheim-TV (2. Bildschirm).
class TournamentSecondScreenView extends StatefulWidget {
  const TournamentSecondScreenView({
    super.key,
    required this.tournament,
    this.isStandaloneWindow = false,
    this.onClose,
    this.showNextStagePreviewInitially = false,
    this.forecastService,
    this.storage,
    this.database,
  });

  final CreatedTournament tournament;
  final bool isStandaloneWindow;
  final VoidCallback? onClose;
  final bool showNextStagePreviewInitially;
  final GroupAdvancementForecastService? forecastService;
  final TournamentStorage? storage;
  final LocalAppDatabase? database;

  @override
  State<TournamentSecondScreenView> createState() =>
      _TournamentSecondScreenViewState();
}

class _TournamentSecondScreenViewState
    extends State<TournamentSecondScreenView> {
  bool _showNextStagePreview = false;
  bool _showInlineNextStagePreview = false;
  _StandingsDisplayMode _standingsDisplayMode = _StandingsDisplayMode.standings;
  Timer? _clockTimer;
  final _previewVerticalController = ScrollController();
  final _previewHorizontalController = ScrollController();
  final _recentResultsController = ScrollController();
  TournamentFlowPrioritySettings _prioritySettings =
      TournamentFlowPriority.defaultSettings;
  String? _prioritySettingsError;
  late Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges;
  late String _eloInputFingerprint;
  late Future<List<({String rankingName, List<LocalEloPlayer> entries})>>
  _rankingStandings;
  Future<Map<String, AdvancementChance>>? _advancementForecast;
  late String _forecastFingerprint;
  late List<SecondScreenWidgetPlacement> _monitorPlacements;
  String? _loadedLayoutName;
  bool _useCustomLayout = false;
  bool _isEditingLayout = false;
  bool _customLayoutBeforeEditing = false;
  List<SecondScreenWidgetPlacement>? _placementsBeforeEditing;
  String? _dragTargetWidgetId;
  int? _dragTargetEdge;
  final Map<String, GlobalKey> _monitorDropTargetKeys = {};

  TournamentStorage get _storage => widget.storage ?? TournamentStorage();
  LocalAppDatabase get _database => widget.database ?? LocalAppDatabase();

  @override
  void initState() {
    super.initState();
    _showNextStagePreview = widget.showNextStagePreviewInitially;
    _loadedLayoutName = widget.tournament.secondScreenActiveLayout;
    _useCustomLayout = _loadedLayoutName != null;
    _monitorPlacements = _savedLayoutOrDefault();
    unawaited(_loadPrioritySettings());
    _refreshEloChanges();
    _refreshRankingStandings();
    _refreshAdvancementForecast();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  List<SecondScreenWidgetPlacement> _savedLayoutOrDefault() {
    final activeName = widget.tournament.secondScreenActiveLayout;
    final saved = activeName == null
        ? null
        : widget.tournament.secondScreenLayouts[activeName];
    return _withIndependentColumns(saved ?? _defaultMonitorLayout);
  }

  List<SecondScreenWidgetPlacement> _withIndependentColumns(
    List<SecondScreenWidgetPlacement> placements,
  ) {
    if (placements.any((placement) => placement.widthUnits > 2)) {
      return List.of(placements);
    }
    return [
      for (var index = 0; index < placements.length; index++)
        placements[index].columnIndex == null
            ? SecondScreenWidgetPlacement(
                widgetId: placements[index].widgetId,
                widthUnits: placements[index].widthUnits,
                heightUnits: placements[index].heightUnits,
                startsNewRow: placements[index].startsNewRow,
                columnIndex: index.isEven ? 0 : 1,
              )
            : placements[index],
    ];
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
      _refreshRankingStandings();
    }
    if (fingerprint != _forecastFingerprint) {
      _refreshAdvancementForecast(fingerprint: fingerprint);
    }
  }

  void _refreshEloChanges({String? fingerprint}) {
    _eloInputFingerprint =
        fingerprint ?? jsonEncode(widget.tournament.toJson());
    _eloChanges = TournamentMatchEloService(
      database: _database,
      tournamentStorage: _storage,
    ).calculate(widget.tournament);
  }

  void _refreshRankingStandings() {
    _rankingStandings = _loadRankingStandings(widget.tournament);
  }

  Future<List<({String rankingName, List<LocalEloPlayer> entries})>>
  _loadRankingStandings(CreatedTournament tournament) async {
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return const [];
    }
    final selectedRankings = (await _database.loadLocalRankings())
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              tournament.rankingIds.contains(ranking.id),
        )
        .toList();
    final tournaments = await _storage.loadTournaments();
    final rankingTournaments = [
      ...tournaments.where((entry) => entry.id != tournament.id),
      tournament,
    ];
    final service = LocalRankingEloService(database: _database);
    return [
      for (final ranking in selectedRankings)
        (
          rankingName: ranking.name,
          entries: (await service.calculate(
            ranking,
            tournaments: rankingTournaments,
          )).entries,
        ),
    ];
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
    _recentResultsController.dispose();
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
                : widget.isStandaloneWindow && _useCustomLayout
                ? _buildCustomOverview(
                    context,
                    t: t,
                    activeIndex: activeIndex,
                    activeStage: activeStage,
                    playedMatches: playedMatches,
                    timing: timing,
                  )
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
                  if (widget.isStandaloneWindow) ...[
                    OutlinedButton.icon(
                      onPressed: _startMonitorLayoutEditing,
                      icon: const Icon(Icons.dashboard_customize),
                      label: const Text('Layout anpassen'),
                    ),
                    if (t.secondScreenLayouts.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _loadMonitorLayout,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Layout laden'),
                      ),
                  ],
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

  Widget _buildCustomOverview(
    BuildContext context, {
    required CreatedTournament t,
    required int activeIndex,
    required TournamentRunStage? activeStage,
    required List<GroupMatch> playedMatches,
    required TimingSnapshot timing,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        final spacing = 12.0;
        final unitWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final minimumUnitHeight =
            220 * MediaQuery.textScalerOf(context).scale(1);
        final unitHeight = (max(
          constraints.maxHeight / 2.4,
          minimumUnitHeight,
        )).clamp(220.0, 360.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCustomLayoutStatusBar(t, activeStage, timing),
            LayoutBuilder(
              builder: (context, toolbarConstraints) =>
                  _buildCustomLayoutToolbar(
                    context,
                    t,
                    toolbarConstraints.maxWidth,
                  ),
            ),
            if (_loadedLayoutName != null)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Layout: $_loadedLayoutName',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildMonitorLayoutRows(
                    context,
                    t,
                    activeIndex,
                    activeStage,
                    playedMatches,
                    columns,
                    unitWidth,
                    unitHeight,
                    spacing,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomLayoutStatusBar(
    CreatedTournament tournament,
    TournamentRunStage? activeStage,
    TimingSnapshot timing,
  ) {
    final matches = TournamentTiming.matches(tournament);
    final playedCount = matches
        .where((match) => match.hasPlayers && match.hasResult)
        .length;
    final totalMatchCount = tournament.runStages.isEmpty
        ? matches.where((match) => match.hasPlayers).length
        : tournament.runStages.fold(
            0,
            (total, stage) => total + _countMatchesForProgress(stage),
          );
    final knockoutStage = activeStage is KnockoutTournamentRunStage
        ? activeStage
        : null;
    return Align(
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
          if (knockoutStage != null)
            Text(
              '${knockoutStage.name}: '
              '${_matchesOf(knockoutStage).where((match) => match.hasResult).length}/'
              '${_countMatchesForProgress(knockoutStage)}',
              style: const TextStyle(color: Colors.white70),
            ),
          if (timing.forecast != null)
            Text(
              'Ende ca. ${_formatClockTime(timing.forecast!)}',
              style: const TextStyle(color: Colors.white),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildMonitorLayoutRows(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex,
    TournamentRunStage? activeStage,
    List<GroupMatch> playedMatches,
    int columns,
    double unitWidth,
    double unitHeight,
    double spacing,
  ) {
    if (columns >= 4 &&
        _monitorPlacements.every(
          (placement) => placement.columnIndex != null,
        )) {
      return [
        _buildMonitorLayoutColumns(
          context,
          tournament,
          activeIndex,
          activeStage,
          playedMatches,
          unitWidth,
          unitHeight,
          spacing,
        ),
      ];
    }

    final rows = <List<int>>[[]];
    for (var index = 0; index < _monitorPlacements.length; index++) {
      if (index > 0 && _monitorPlacements[index].startsNewRow) {
        rows.add([]);
      }
      rows.last.add(index);
    }

    return [
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
        if (rowIndex > 0) SizedBox(height: spacing),
        Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final index in rows[rowIndex])
              Builder(
                builder: (context) {
                  final placement = _monitorPlacements[index];
                  final widthUnits = placement.widthUnits.clamp(1, columns);
                  final width =
                      unitWidth * widthUnits + spacing * (widthUnits - 1);
                  final height = unitHeight * placement.heightUnits;
                  return _buildMonitorWidgetDropTarget(
                    context,
                    placement.widgetId,
                    width: width,
                    height: height,
                    child: _buildMonitorWidgetCard(
                      context,
                      placement,
                      index,
                      width: width,
                      height: height,
                      tournament: tournament,
                      activeIndex: activeIndex,
                      activeStage: activeStage,
                      playedMatches: playedMatches,
                      isEditing: _isEditingLayout,
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    ];
  }

  Widget _buildMonitorLayoutColumns(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex,
    TournamentRunStage? activeStage,
    List<GroupMatch> playedMatches,
    double unitWidth,
    double unitHeight,
    double spacing,
  ) {
    final columns = [
      for (var column = 0; column < 2; column++)
        _buildMonitorLayoutColumn(
          context,
          tournament,
          activeIndex,
          activeStage,
          playedMatches,
          column,
          unitWidth,
          unitHeight,
          spacing,
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var column = 0; column < columns.length; column++) ...[
          if (column > 0) SizedBox(width: spacing),
          columns[column],
        ],
      ],
    );
  }

  Widget _buildMonitorLayoutColumn(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex,
    TournamentRunStage? activeStage,
    List<GroupMatch> playedMatches,
    int column,
    double unitWidth,
    double unitHeight,
    double spacing,
  ) {
    final indexes = [
      for (var index = 0; index < _monitorPlacements.length; index++)
        if (_monitorPlacements[index].columnIndex == column) index,
    ];
    return SizedBox(
      width: unitWidth * 2 + spacing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var itemIndex = 0; itemIndex < indexes.length; itemIndex++) ...[
            if (itemIndex > 0) SizedBox(height: spacing),
            Builder(
              builder: (context) {
                final index = indexes[itemIndex];
                final placement = _monitorPlacements[index];
                final widthUnits = placement.widthUnits.clamp(1, 2);
                final width =
                    unitWidth * widthUnits + spacing * (widthUnits - 1);
                final height = unitHeight * placement.heightUnits;
                return _buildMonitorWidgetDropTarget(
                  context,
                  placement.widgetId,
                  width: width,
                  height: height,
                  columnLayout: true,
                  child: _buildMonitorWidgetCard(
                    context,
                    placement,
                    index,
                    width: width,
                    height: height,
                    tournament: tournament,
                    activeIndex: activeIndex,
                    activeStage: activeStage,
                    playedMatches: playedMatches,
                    isEditing: _isEditingLayout,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _startMonitorLayoutEditing() {
    setState(() {
      _customLayoutBeforeEditing = _useCustomLayout;
      _placementsBeforeEditing = List.of(_monitorPlacements);
      _useCustomLayout = true;
      _isEditingLayout = true;
    });
  }

  Widget _buildCustomLayoutToolbar(
    BuildContext context,
    CreatedTournament tournament,
    double width,
  ) {
    final compact =
        width < 640 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
    if (compact) {
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [
          if (_isEditingLayout)
            FilledButton.icon(
              onPressed: _applyMonitorLayout,
              icon: const Icon(Icons.check),
              label: const Text('Layout anwenden'),
            )
          else
            OutlinedButton.icon(
              onPressed: _startMonitorLayoutEditing,
              icon: const Icon(Icons.dashboard_customize),
              label: const Text('Layout anpassen'),
            ),
          PopupMenuButton<_MonitorLayoutAction>(
            tooltip: 'Weitere Layout-Aktionen',
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              if (_isEditingLayout) ...[
                const PopupMenuItem(
                  value: _MonitorLayoutAction.add,
                  child: Text('Widget hinzufügen'),
                ),
                const PopupMenuItem(
                  value: _MonitorLayoutAction.save,
                  child: Text('Layout speichern'),
                ),
                const PopupMenuItem(
                  value: _MonitorLayoutAction.reset,
                  child: Text('Layout zurücksetzen'),
                ),
              ],
              if (tournament.secondScreenLayouts.isNotEmpty)
                const PopupMenuItem(
                  value: _MonitorLayoutAction.load,
                  child: Text('Layout laden'),
                ),
              const PopupMenuItem(
                value: _MonitorLayoutAction.standard,
                child: Text('Standardansicht'),
              ),
            ],
            onSelected: _handleMonitorLayoutAction,
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        if (_isEditingLayout) ...[
          OutlinedButton.icon(
            onPressed: _addMonitorWidget,
            icon: const Icon(Icons.add),
            label: const Text('Widget hinzufügen'),
          ),
          OutlinedButton.icon(
            onPressed: _saveMonitorLayout,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Layout speichern'),
          ),
          OutlinedButton.icon(
            onPressed: _resetMonitorLayout,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Layout zurücksetzen'),
          ),
          FilledButton.icon(
            onPressed: _applyMonitorLayout,
            icon: const Icon(Icons.check),
            label: const Text('Layout anwenden'),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _startMonitorLayoutEditing,
            icon: const Icon(Icons.dashboard_customize),
            label: const Text('Layout anpassen'),
          ),
        if (tournament.secondScreenLayouts.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _loadMonitorLayout,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Layout laden'),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _useCustomLayout = false;
            _isEditingLayout = false;
          }),
          icon: const Icon(Icons.tv),
          label: const Text('Standardansicht'),
        ),
      ],
    );
  }

  void _handleMonitorLayoutAction(_MonitorLayoutAction action) {
    switch (action) {
      case _MonitorLayoutAction.add:
        _addMonitorWidget();
      case _MonitorLayoutAction.save:
        _saveMonitorLayout();
      case _MonitorLayoutAction.load:
        _loadMonitorLayout();
      case _MonitorLayoutAction.reset:
        _resetMonitorLayout();
      case _MonitorLayoutAction.standard:
        setState(() {
          _useCustomLayout = false;
          _isEditingLayout = false;
        });
    }
  }

  Widget _buildMonitorWidgetDropTarget(
    BuildContext context,
    String targetWidgetId, {
    required double width,
    required double height,
    bool columnLayout = false,
    required Widget child,
  }) {
    if (!_isEditingLayout) return child;
    final targetKey = _monitorDropTargetKeys.putIfAbsent(
      targetWidgetId,
      GlobalKey.new,
    );
    return SizedBox(
      key: targetKey,
      child: DragTarget<String>(
        key: ValueKey('monitor-widget-drop-target-$targetWidgetId'),
        onWillAcceptWithDetails: (details) =>
            details.data != targetWidgetId &&
            _monitorPlacements.any(
              (placement) => placement.widgetId == details.data,
            ),
        onMove: (details) {
          final box = targetKey.currentContext?.findRenderObject();
          if (box is! RenderBox) return;
          final edge = _nearestDropEdge(box, details.offset);
          if (_dragTargetWidgetId == targetWidgetId &&
              _dragTargetEdge == edge) {
            return;
          }
          setState(() {
            _dragTargetWidgetId = targetWidgetId;
            _dragTargetEdge = edge;
          });
        },
        onLeave: (_) {
          if (_dragTargetWidgetId == targetWidgetId) {
            setState(() {
              _dragTargetWidgetId = null;
              _dragTargetEdge = null;
            });
          }
        },
        onAcceptWithDetails: (details) {
          final box = targetKey.currentContext?.findRenderObject();
          if (box is! RenderBox) {
            return;
          }
          final targetIndex = _monitorPlacements.indexWhere(
            (placement) => placement.widgetId == targetWidgetId,
          );
          final fromIndex = _monitorPlacements.indexWhere(
            (placement) => placement.widgetId == details.data,
          );
          if (targetIndex < 0 || fromIndex < 0) return;
          final edge = _nearestDropEdge(box, details.offset);
          setState(() {
            _dragTargetWidgetId = null;
            _dragTargetEdge = null;
          });
          _moveMonitorWidget(
            fromIndex,
            targetIndex,
            edge: edge,
            columnLayout: columnLayout,
          );
        },
        builder: (context, candidates, rejected) => Draggable<String>(
          key: ValueKey('monitor-widget-drag-$targetWidgetId'),
          data: targetWidgetId,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: SizedBox(
            width: width,
            height: height,
            child: Material(
              color: Colors.transparent,
              child: Opacity(opacity: 0.85, child: child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: candidates.isEmpty
                ? null
                : BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: _dragTargetEdge == 0
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 5,
                      ),
                      right: BorderSide(
                        color: _dragTargetEdge == 1
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 5,
                      ),
                      top: BorderSide(
                        color: _dragTargetEdge == 2
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 5,
                      ),
                      bottom: BorderSide(
                        color: _dragTargetEdge == 3
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 5,
                      ),
                    ),
                  ),
            child: child,
          ),
        ),
      ),
    );
  }

  int _nearestDropEdge(RenderBox box, Offset globalOffset) {
    final localPosition = box.globalToLocal(globalOffset);
    final size = box.size;
    final edgeDistances = [
      localPosition.dx,
      size.width - localPosition.dx,
      localPosition.dy,
      size.height - localPosition.dy,
    ];
    final nearestEdge = edgeDistances.indexOf(edgeDistances.reduce(min));
    return nearestEdge;
  }

  Widget _buildMonitorWidgetCard(
    BuildContext context,
    SecondScreenWidgetPlacement placement,
    int index, {
    required double width,
    required double height,
    required CreatedTournament tournament,
    required int activeIndex,
    required TournamentRunStage? activeStage,
    required List<GroupMatch> playedMatches,
    required bool isEditing,
  }) {
    final title = _monitorWidgetTitles[placement.widgetId];
    if (title == null) return const SizedBox.shrink();
    final widgetContent = _buildMonitorWidgetContent(
      context,
      placement.widgetId,
      tournament,
      activeIndex,
      activeStage,
      playedMatches,
    );
    if (!isEditing) {
      return SizedBox(
        key: ValueKey('monitor-widget-${placement.widgetId}'),
        width: width,
        height: height,
        child: ClipRect(child: widgetContent),
      );
    }

    final maxWidthUnits = placement.columnIndex == null ? 4 : 2;
    final titleWidget = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
    final dragHandle = const Tooltip(
      message: 'Ziehen, um das Widget anders anzuordnen',
      child: Icon(Icons.drag_indicator, size: 20),
    );
    final editControls = [
      IconButton(
        tooltip: 'Breite verkleinern',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: placement.widthUnits <= 1
            ? null
            : () => _resizeMonitorWidget(
                index,
                widthUnits: placement.widthUnits - 1,
              ),
        icon: const Icon(Icons.remove),
      ),
      IconButton(
        tooltip: 'Breite vergrößern',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: placement.widthUnits >= maxWidthUnits
            ? null
            : () => _resizeMonitorWidget(
                index,
                widthUnits: placement.widthUnits + 1,
              ),
        icon: const Icon(Icons.add),
      ),
      IconButton(
        tooltip: 'Höhe verkleinern',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: placement.heightUnits <= 0.5
            ? null
            : () => _resizeMonitorWidget(
                index,
                heightUnits: placement.heightUnits - 0.5,
              ),
        icon: const Icon(Icons.height, size: 19),
      ),
      IconButton(
        tooltip: 'Höhe vergrößern',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: placement.heightUnits >= 3
            ? null
            : () => _resizeMonitorWidget(
                index,
                heightUnits: placement.heightUnits + 0.5,
              ),
        icon: const Icon(Icons.unfold_more),
      ),
      IconButton(
        tooltip: 'Widget entfernen',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: () => _removeMonitorWidget(index),
        icon: const Icon(Icons.close),
      ),
    ];
    return SizedBox(
      key: ValueKey('monitor-widget-${placement.widgetId}'),
      width: width,
      height: height,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 560 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                    return Row(
                      children: [
                        Expanded(child: titleWidget),
                        dragHandle,
                        PopupMenuButton<String>(
                          tooltip: 'Widgetgröße und Position ändern',
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'width-smaller',
                              enabled: placement.widthUnits > 1,
                              child: const Text('Breite verkleinern'),
                            ),
                            PopupMenuItem(
                              value: 'width-larger',
                              enabled: placement.widthUnits < maxWidthUnits,
                              child: const Text('Breite vergrößern'),
                            ),
                            PopupMenuItem(
                              value: 'height-smaller',
                              enabled: placement.heightUnits > 0.5,
                              child: const Text('Höhe verkleinern'),
                            ),
                            PopupMenuItem(
                              value: 'height-larger',
                              enabled: placement.heightUnits < 3,
                              child: const Text('Höhe vergrößern'),
                            ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Widget entfernen'),
                            ),
                          ],
                          onSelected: (action) =>
                              _handleMonitorWidgetAction(index, action),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: titleWidget),
                      dragHandle,
                      ...editControls,
                    ],
                  );
                },
              ),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Expanded(child: ClipRect(child: widgetContent)),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMonitorWidgetAction(int index, String action) {
    final placement = _monitorPlacements[index];
    switch (action) {
      case 'width-smaller':
        _resizeMonitorWidget(index, widthUnits: placement.widthUnits - 1);
      case 'width-larger':
        _resizeMonitorWidget(index, widthUnits: placement.widthUnits + 1);
      case 'height-smaller':
        _resizeMonitorWidget(index, heightUnits: placement.heightUnits - 0.5);
      case 'height-larger':
        _resizeMonitorWidget(index, heightUnits: placement.heightUnits + 0.5);
      case 'remove':
        _removeMonitorWidget(index);
    }
  }

  Widget _buildMonitorWidgetContent(
    BuildContext context,
    String widgetId,
    CreatedTournament tournament,
    int activeIndex,
    TournamentRunStage? activeStage,
    List<GroupMatch> playedMatches,
  ) {
    switch (widgetId) {
      case 'boards':
        return _buildBoardsAndPriorityPanel(
          context,
          tournament,
          activeIndex,
          activeStage,
          expand: true,
        );
      case 'standings':
        return _buildStandingsPanel(
          context,
          tournament,
          activeStage,
          full: true,
          expand: true,
        );
      case 'forecast':
        return _buildKoPrognosisPanel(
          context,
          tournament,
          activeIndex,
          activeStage,
          expand: true,
        );
      case 'combined':
        return _buildStandingsAndForecastWidget(
          context,
          tournament,
          activeIndex,
          activeStage,
        );
      case 'recent':
        return _buildRecentMatchesAndEloPanel(
          context,
          tournament,
          playedMatches,
          expand: true,
        );
      case 'liveBoard':
        return SingleChildScrollView(
          child: _buildLiveBoardsPanel(context, tournament),
        );
      case 'stageProgress':
        return SingleChildScrollView(
          child: _buildStageProgressPanel(context, tournament),
        );
      case 'highlights':
        return SingleChildScrollView(
          child: _buildHighlightsPanel(context, tournament),
        );
      case 'ranking':
        return SingleChildScrollView(
          child: _buildRankingPanel(context, tournament),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _moveMonitorWidget(
    int fromIndex,
    int targetIndex, {
    required int edge,
    bool columnLayout = false,
  }) {
    if (fromIndex < 0 ||
        fromIndex >= _monitorPlacements.length ||
        targetIndex < 0 ||
        targetIndex >= _monitorPlacements.length ||
        fromIndex == targetIndex) {
      return;
    }
    if (columnLayout) {
      _moveMonitorWidgetBetweenColumns(fromIndex, targetIndex, edge);
      return;
    }
    setState(() {
      final target = _monitorPlacements[targetIndex];
      final moving = _monitorPlacements.removeAt(fromIndex);
      if (moving.startsNewRow &&
          fromIndex > 0 &&
          fromIndex < _monitorPlacements.length) {
        final next = _monitorPlacements[fromIndex];
        if (!next.startsNewRow) {
          _monitorPlacements[fromIndex] = SecondScreenWidgetPlacement(
            widgetId: next.widgetId,
            widthUnits: next.widthUnits,
            heightUnits: next.heightUnits,
            startsNewRow: true,
            columnIndex: next.columnIndex,
          );
        }
      }
      final adjustedTargetIndex = _monitorPlacements.indexWhere(
        (placement) => placement.widgetId == target.widgetId,
      );
      final insertBefore = edge == 0 || edge == 2;
      final destination = adjustedTargetIndex + (insertBefore ? 0 : 1);
      final startsNewRow = switch (edge) {
        0 => target.startsNewRow,
        1 => false,
        2 => true,
        3 => true,
        _ => false,
      };
      final movedPlacement = SecondScreenWidgetPlacement(
        widgetId: moving.widgetId,
        widthUnits: moving.widthUnits,
        heightUnits: moving.heightUnits,
        startsNewRow: startsNewRow,
        columnIndex: moving.columnIndex,
      );
      _monitorPlacements.insert(destination, movedPlacement);

      if (edge == 0 || edge == 2) {
        final updatedTargetIndex = _monitorPlacements.indexWhere(
          (placement) => placement.widgetId == target.widgetId,
        );
        final currentTarget = _monitorPlacements[updatedTargetIndex];
        _monitorPlacements[updatedTargetIndex] = SecondScreenWidgetPlacement(
          widgetId: currentTarget.widgetId,
          widthUnits: currentTarget.widthUnits,
          heightUnits: currentTarget.heightUnits,
          startsNewRow: edge == 2,
          columnIndex: currentTarget.columnIndex,
        );
      }
    });
  }

  void _moveMonitorWidgetBetweenColumns(
    int fromIndex,
    int targetIndex,
    int edge,
  ) {
    setState(() {
      for (var index = 0; index < _monitorPlacements.length; index++) {
        final placement = _monitorPlacements[index];
        if (placement.columnIndex == null) {
          _monitorPlacements[index] = SecondScreenWidgetPlacement(
            widgetId: placement.widgetId,
            widthUnits: placement.widthUnits,
            heightUnits: placement.heightUnits,
            startsNewRow: placement.startsNewRow,
            columnIndex: index.isEven ? 0 : 1,
          );
        }
      }

      final targetId = _monitorPlacements[targetIndex].widgetId;
      final moving = _monitorPlacements.removeAt(fromIndex);
      final updatedTargetIndex = _monitorPlacements.indexWhere(
        (placement) => placement.widgetId == targetId,
      );
      final target = _monitorPlacements[updatedTargetIndex];
      final destination = updatedTargetIndex + (edge == 0 || edge == 2 ? 0 : 1);
      final columnIndex = edge == 0
          ? 0
          : edge == 1
          ? 1
          : target.columnIndex!;
      _monitorPlacements.insert(
        destination,
        SecondScreenWidgetPlacement(
          widgetId: moving.widgetId,
          widthUnits: moving.widthUnits.clamp(1, 2),
          heightUnits: moving.heightUnits,
          startsNewRow: edge == 2 || edge == 3,
          columnIndex: columnIndex,
        ),
      );
    });
  }

  void _resizeMonitorWidget(int index, {int? widthUnits, double? heightUnits}) {
    setState(() {
      final current = _monitorPlacements[index];
      _monitorPlacements[index] = SecondScreenWidgetPlacement(
        widgetId: current.widgetId,
        widthUnits: (widthUnits ?? current.widthUnits).clamp(
          1,
          current.columnIndex == null ? 4 : 2,
        ),
        heightUnits: heightUnits ?? current.heightUnits,
        startsNewRow: current.startsNewRow,
        columnIndex: current.columnIndex,
      );
    });
  }

  void _removeMonitorWidget(int index) {
    setState(() {
      final removed = _monitorPlacements.removeAt(index);
      if (removed.startsNewRow &&
          index > 0 &&
          index < _monitorPlacements.length) {
        final next = _monitorPlacements[index];
        if (!next.startsNewRow) {
          _monitorPlacements[index] = SecondScreenWidgetPlacement(
            widgetId: next.widgetId,
            widthUnits: next.widthUnits,
            heightUnits: next.heightUnits,
            startsNewRow: true,
            columnIndex: next.columnIndex,
          );
        }
      }
    });
  }

  Future<void> _addMonitorWidget() async {
    final available = _monitorWidgetTitles.keys
        .where(
          (id) =>
              !_monitorPlacements.any(
                (placement) => placement.widgetId == id,
              ) &&
              (id != 'ranking' ||
                  (widget.tournament.countsForRanking &&
                      widget.tournament.rankingIds.isNotEmpty)),
        )
        .toList();
    if (available.isEmpty) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Widget hinzufügen'),
        children: [
          for (final id in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, id),
              child: Text(_monitorWidgetTitles[id]!),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final columnHeights = [0.0, 0.0];
    final hasIndependentColumns =
        _monitorPlacements.isNotEmpty &&
        _monitorPlacements.every((placement) => placement.columnIndex != null);
    if (hasIndependentColumns) {
      for (final placement in _monitorPlacements) {
        columnHeights[placement.columnIndex!] += placement.heightUnits;
      }
    }
    setState(
      () => _monitorPlacements.add(
        SecondScreenWidgetPlacement(
          widgetId: selected,
          columnIndex: hasIndependentColumns
              ? columnHeights[0] <= columnHeights[1]
                    ? 0
                    : 1
              : null,
        ),
      ),
    );
  }

  Future<void> _saveMonitorLayout() async {
    final controller = TextEditingController(text: _loadedLayoutName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Layout speichern'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Layoutname',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final saved = await _persistMonitorLayout(name);
    if (saved) {
      _customLayoutBeforeEditing = true;
      _placementsBeforeEditing = List.of(_monitorPlacements);
    }
  }

  Future<void> _applyMonitorLayout() async {
    final unchanged = _placementsMatch(
      _monitorPlacements,
      _placementsBeforeEditing,
    );
    if (unchanged) {
      setState(() {
        _isEditingLayout = false;
        _useCustomLayout = _customLayoutBeforeEditing;
        _placementsBeforeEditing = null;
      });
      return;
    }
    final applied = await _persistMonitorLayout(
      _loadedLayoutName ?? _standardMonitorLayoutName,
    );
    if (applied && mounted) {
      setState(() {
        _isEditingLayout = false;
        _useCustomLayout = true;
        _placementsBeforeEditing = null;
      });
    }
  }

  bool _placementsMatch(
    List<SecondScreenWidgetPlacement> current,
    List<SecondScreenWidgetPlacement>? previous,
  ) {
    if (previous == null || current.length != previous.length) return false;
    for (var index = 0; index < current.length; index++) {
      final currentPlacement = current[index];
      final previousPlacement = previous[index];
      if (currentPlacement.widgetId != previousPlacement.widgetId ||
          currentPlacement.widthUnits != previousPlacement.widthUnits ||
          currentPlacement.heightUnits != previousPlacement.heightUnits ||
          currentPlacement.startsNewRow != previousPlacement.startsNewRow ||
          currentPlacement.columnIndex != previousPlacement.columnIndex) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _persistMonitorLayout(String name) async {
    try {
      await _storage.saveSecondScreenLayout(
        tournament: widget.tournament,
        name: name,
        placements: _monitorPlacements,
        activate: true,
      );
      if (mounted) {
        setState(() {
          _loadedLayoutName = name;
          _useCustomLayout = true;
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Layout konnte nicht gespeichert werden: $error'),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _loadMonitorLayout() async {
    final names = widget.tournament.secondScreenLayouts.keys.toList()..sort();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => SimpleDialog(
          title: const Text('Layout laden'),
          children: [
            for (final name in names.where(
              widget.tournament.secondScreenLayouts.containsKey,
            ))
              Row(
                children: [
                  Expanded(
                    child: SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, name),
                      child: Text(name),
                    ),
                  ),
                  if (!_isStandardMonitorLayout(name))
                    IconButton(
                      tooltip: 'Layout "$name" löschen',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Layout löschen?'),
                            content: Text('„$name“ wird dauerhaft gelöscht.'),
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
                        if (confirmed != true || !mounted) return;
                        final deleted = await _deleteMonitorLayout(name);
                        if (deleted) updateDialog(() {});
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final layout = widget.tournament.secondScreenLayouts[selected];
    if (layout == null) return;
    try {
      await _storage.saveSecondScreenLayout(
        tournament: widget.tournament,
        name: selected,
        placements: layout,
        activate: true,
      );
      if (!mounted) return;
      setState(() {
        _monitorPlacements = _withIndependentColumns(layout);
        _loadedLayoutName = selected;
        _useCustomLayout = true;
        _isEditingLayout = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Layout konnte nicht geladen werden: $error')),
        );
      }
    }
  }

  Future<bool> _deleteMonitorLayout(String name) async {
    if (_isStandardMonitorLayout(name) ||
        !widget.tournament.secondScreenLayouts.containsKey(name)) {
      return false;
    }
    final previousActiveLayout = widget.tournament.secondScreenActiveLayout;
    try {
      await _storage.saveSecondScreenLayout(
        tournament: widget.tournament,
        name: name,
        placements: null,
        activate: false,
      );
      if (mounted &&
          (previousActiveLayout == name || _loadedLayoutName == name)) {
        setState(() {
          _monitorPlacements = List.of(_defaultMonitorLayout);
          _loadedLayoutName = null;
          _useCustomLayout = false;
          _isEditingLayout = false;
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Layout konnte nicht gelöscht werden: $error'),
          ),
        );
      }
      return false;
    }
  }

  bool _isStandardMonitorLayout(String name) =>
      name.trim().toLowerCase() == _standardMonitorLayoutName.toLowerCase();

  Future<void> _resetMonitorLayout() async {
    try {
      await _storage.saveSecondScreenLayout(
        tournament: widget.tournament,
        name: _standardMonitorLayoutName,
        placements: _defaultMonitorLayout,
        activate: true,
      );
      if (mounted) {
        setState(() {
          _monitorPlacements = List.of(_defaultMonitorLayout);
          _loadedLayoutName = 'Standard';
          _useCustomLayout = true;
          _isEditingLayout = true;
          _customLayoutBeforeEditing = true;
          _placementsBeforeEditing = List.of(_defaultMonitorLayout);
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Layout konnte nicht zurückgesetzt werden: $error'),
          ),
        );
      }
    }
  }

  Widget _buildStageProgressPanel(
    BuildContext context,
    CreatedTournament tournament,
  ) {
    final stages = tournament.runStages;
    final matches = TournamentTiming.matches(tournament);
    final allWithPlayers = stages.isEmpty
        ? matches.where((match) => match.hasPlayers).length
        : stages.fold<int>(
            0,
            (total, stage) => total + _countMatchesForProgress(stage),
          );
    final played = stages.isEmpty
        ? matches.where((match) => match.hasPlayers && match.hasResult).length
        : stages.fold<int>(
            0,
            (total, stage) =>
                total +
                _matchesOf(stage).where((match) => match.hasResult).length,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$played von $allWithPlayers Partien abgeschlossen'),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: allWithPlayers == 0 ? 0 : played / allWithPlayers,
          color: const Color(0xFF70E0BA),
          backgroundColor: Colors.white24,
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < stages.length; index++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(stages[index].name),
            subtitle: Text(
              '${_matchesOf(stages[index]).where((match) => match.hasResult).length} / '
              '${_countMatchesForProgress(stages[index])} Partien',
            ),
            trailing: Icon(
              tournament.completedStageIndexes.contains(index)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: tournament.completedStageIndexes.contains(index)
                  ? const Color(0xFF70E0BA)
                  : Colors.white54,
            ),
          ),
      ],
    );
  }

  Widget _buildHighlightsPanel(
    BuildContext context,
    CreatedTournament tournament,
  ) {
    final highlights = [
      for (final match in TournamentTiming.matches(tournament))
        for (final performance in match.bestPerformances)
          (match: match, performance: performance),
    ];
    if (highlights.isEmpty) {
      return const Center(
        child: Text(
          'Noch keine Bestleistungen erfasst.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in highlights.reversed.take(20))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.stars_outlined, color: Color(0xFF70E0BA)),
            title: Text(item.performance.label),
            subtitle: Text(item.performance.playerName),
          ),
      ],
    );
  }

  Widget _buildRankingPanel(
    BuildContext context,
    CreatedTournament tournament,
  ) {
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return const Center(
        child: Text(
          'Für dieses Turnier ist keine Rangliste ausgewählt.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return FutureBuilder<
      List<({String rankingName, List<LocalEloPlayer> entries})>
    >(
      future: _rankingStandings,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Die ELO-Rangliste konnte nicht geladen werden.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final standings = snapshot.data!;
        if (standings.isEmpty ||
            standings.every((ranking) => ranking.entries.isEmpty)) {
          return const Center(
            child: Text(
              'Für dieses Turnier ist keine ELO-Rangliste ausgewählt.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final ranking in standings) ...[
              Text(
                ranking.rankingName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final entry in ranking.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${entry.name} – ${entry.rating} Elo',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLiveBoardsPanel(
    BuildContext context,
    CreatedTournament tournament,
  ) {
    final boards = [
      for (var board = 1; board <= tournament.boardCount; board++)
        if (_validLiveBoardUri(tournament.directorBoardLiveUrls[board])
            case final uri?)
          (board: board, uri: uri),
    ];
    if (boards.isEmpty) {
      return const Center(
        child: Text(
          'Für kein Board ist eine gültige Live Board URL hinterlegt.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in boards)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tournament.boardDisplayName(item.board)),
                    ),
                    IconButton(
                      tooltip: 'Live Board vergrößern',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => _showExpandedLiveBoard(
                        tournament.boardDisplayName(item.board),
                        item.uri,
                      ),
                      icon: const Icon(Icons.open_in_full),
                    ),
                  ],
                ),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Tooltip(
                      message: 'Tippen, um das Live Board zu vergrößern',
                      child: GestureDetector(
                        onTap: () => _showExpandedLiveBoard(
                          tournament.boardDisplayName(item.board),
                          item.uri,
                        ),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: _liveBoardBrowser(
                            item.uri,
                            key: ValueKey(
                              'live-board-${item.board}-${item.uri}',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Uri? _validLiveBoardUri(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri;
  }

  Future<void> _showExpandedLiveBoard(String title, Uri uri) =>
      showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: IconButton(
                tooltip: 'Live Board verkleinern',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_fullscreen),
              ),
            ),
            body: SafeArea(child: _liveBoardBrowser(uri)),
          ),
        ),
      );

  Widget _liveBoardBrowser(Uri uri, {Key? key}) {
    if (Theme.of(context).platform == TargetPlatform.linux) {
      return Center(
        child: FilledButton.icon(
          onPressed: () async {
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
                mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Live Board konnte nicht geöffnet werden.'),
                ),
              );
            }
          },
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Live Board im Browser öffnen'),
        ),
      );
    }
    return InAppWebView(
      key: key,
      initialUrlRequest: URLRequest(url: WebUri(uri.toString())),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              _buildStandingsDisplaySelector(context, constraints.maxWidth),
        ),
        const SizedBox(height: 8),
        if (expand)
          Expanded(
            child: showInlinePreview
                ? _buildInlineNextStagePreview(context, t, activeIndex, stage)
                : SingleChildScrollView(
                    child: _buildStandingsDisplayPanel(
                      context,
                      t,
                      activeIndex,
                      stage,
                    ),
                  ),
          )
        else
          _buildStandingsDisplayPanel(context, t, activeIndex, stage),
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

  Widget _buildStandingsDisplaySelector(BuildContext context, double width) {
    if (width < 560) {
      return DropdownButton<_StandingsDisplayMode>(
        value: _standingsDisplayMode,
        isExpanded: true,
        items: [
          const DropdownMenuItem(
            value: _StandingsDisplayMode.standings,
            child: Text('Tabellen & Zwischenstände'),
          ),
          const DropdownMenuItem(
            value: _StandingsDisplayMode.forecast,
            child: Text('Siegprognose & Weiterkommen'),
          ),
        ],
        onChanged: (mode) {
          if (mode != null) {
            setState(() => _standingsDisplayMode = mode);
          }
        },
      );
    }
    return SegmentedButton<_StandingsDisplayMode>(
      segments: const [
        ButtonSegment(
          value: _StandingsDisplayMode.standings,
          label: Text('Tabellen & Zwischenstände'),
          icon: Icon(Icons.table_chart_outlined),
        ),
        ButtonSegment(
          value: _StandingsDisplayMode.forecast,
          label: Text('Siegprognose & Weiterkommen'),
          icon: Icon(Icons.account_tree_outlined),
        ),
      ],
      selected: {_standingsDisplayMode},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) {
          setState(() => _standingsDisplayMode = selected.first);
        }
      },
    );
  }

  Widget _buildStandingsDisplayPanel(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex,
    TournamentRunStage? stage,
  ) {
    switch (_standingsDisplayMode) {
      case _StandingsDisplayMode.standings:
        return _buildStandingsPanel(
          context,
          tournament,
          stage,
          full: true,
          expand: false,
        );
      case _StandingsDisplayMode.forecast:
        return _buildKoPrognosisPanel(
          context,
          tournament,
          activeIndex,
          stage,
          expand: false,
        );
    }
  }

  Widget _buildStandingsAndForecastWidget(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex,
    TournamentRunStage? stage,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              _buildStandingsDisplaySelector(context, constraints.maxWidth),
        ),
        const Divider(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: _buildStandingsDisplayPanel(
              context,
              tournament,
              activeIndex,
              stage,
            ),
          ),
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
            Text(
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
    final recommendedContent = widget.tournament.directorModeEnabled
        ? _buildDirectorBoardQueue(context, t, activeIndex)
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final notice in flowPriority.notices)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: TournamentDisplayPalette.cardEmphasis,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: TournamentDisplayPalette.border,
                      ),
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
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.amber),
                    ),
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
        Text(
          widget.tournament.directorModeEnabled
              ? 'Boards & nächste Begegnungen'
              : 'Spielplan',
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

  Widget _buildDirectorBoardQueue(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex,
  ) {
    final snapshot = TournamentDirectorSnapshot(tournament, activeIndex);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxColumns = tournament.boardCount < 2
            ? tournament.boardCount
            : 2;
        final columns = (constraints.maxWidth / 280).floor().clamp(
          1,
          maxColumns,
        );
        final spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (var board = 1; board <= tournament.boardCount; board++)
                    Builder(
                      builder: (context) {
                        final running = snapshot.runningOn(board);
                        final blocked = tournament.blockedBoards.contains(
                          board,
                        );
                        final upcoming = snapshot.schedule.planned
                            .where(
                              (assignment) =>
                                  assignment.entry.stageIndex == activeIndex &&
                                  assignment.board == board &&
                                  assignment.entry.match.hasPlayers,
                            )
                            .take(3)
                            .toList();
                        final groupNames = <String>{
                          ?running?.groupKey,
                          for (final assignment in upcoming)
                            ?assignment.entry.groupKey,
                        };
                        final status = running != null
                            ? 'Läuft'
                            : blocked
                            ? 'Gesperrt'
                            : upcoming.isNotEmpty
                            ? 'Frei'
                            : 'Reserve';
                        final statusColor = running != null
                            ? TournamentDisplayPalette.accent
                            : blocked
                            ? Colors.redAccent
                            : upcoming.isNotEmpty
                            ? const Color(0xFF4ED9A4)
                            : TournamentDisplayPalette.mutedText;
                        return Container(
                          key: ValueKey('second-screen-director-board-$board'),
                          width: width,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: TournamentDisplayPalette.card,
                            border: Border.all(
                              color: TournamentDisplayPalette.border.withAlpha(
                                150,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.dashboard_outlined,
                                    size: 18,
                                    color: TournamentDisplayPalette.accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      tournament.boardDisplayName(board),
                                      style: const TextStyle(
                                        color: TournamentDisplayPalette.text,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (tournament.directorSchedulingStrategy ==
                                      'group' &&
                                  groupNames.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    groupNames.join(' · '),
                                    style: const TextStyle(
                                      color: TournamentDisplayPalette.mutedText,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              if (running != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Aktuell: ${running.match.participantShortLabel}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: TournamentDisplayPalette.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (upcoming.isEmpty && running == null)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Keine nächste Begegnung zugewiesen.',
                                    style: TextStyle(
                                      color: TournamentDisplayPalette.mutedText,
                                    ),
                                  ),
                                ),
                              for (
                                var index = 0;
                                index < upcoming.length;
                                index++
                              )
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: Text(
                                          '${index + 1}.',
                                          style: const TextStyle(
                                            color:
                                                TournamentDisplayPalette.accent,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          upcoming[index]
                                              .entry
                                              .match
                                              .participantShortLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color:
                                                TournamentDisplayPalette.text,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
              _buildCompactLiveBoardFrames(context, tournament),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactLiveBoardFrames(
    BuildContext context,
    CreatedTournament tournament,
  ) {
    final boards = [
      for (var board = 1; board <= tournament.boardCount; board++)
        if (_validLiveBoardUri(tournament.directorBoardLiveUrls[board])
            case final uri?)
          (board: board, uri: uri),
    ];
    if (boards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Live Board Ansicht',
            style: TextStyle(
              color: TournamentDisplayPalette.text,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in boards)
            Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(tournament.boardDisplayName(item.board)),
                        ),
                        IconButton(
                          tooltip: 'Live Board vergrößern',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: () => _showExpandedLiveBoard(
                            tournament.boardDisplayName(item.board),
                            item.uri,
                          ),
                          icon: const Icon(Icons.open_in_full),
                        ),
                      ],
                    ),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Tooltip(
                          message: 'Tippen, um das Live Board zu vergrößern',
                          child: GestureDetector(
                            onTap: () => _showExpandedLiveBoard(
                              tournament.boardDisplayName(item.board),
                              item.uri,
                            ),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: _liveBoardBrowser(
                                item.uri,
                                key: ValueKey(
                                  'board-queue-live-${item.board}-${item.uri}',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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
                    const visibleItemCount = 2;
                    final itemExtent =
                        66 * MediaQuery.textScalerOf(context).scale(1);
                    final recentContent = snapshot.hasError
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
                        : Scrollbar(
                            controller: _recentResultsController,
                            thumbVisibility: recent.length > visibleItemCount,
                            child: ListView.separated(
                              controller: _recentResultsController,
                              padding: EdgeInsets.zero,
                              itemCount: recent.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                    height: 1,
                                    color: TournamentDisplayPalette.border,
                                  ),
                              itemBuilder: (context, index) => ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: itemExtent,
                                ),
                                child: _buildRecentMatchRow(
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
                            ),
                          );
                    return expand
                        ? recentContent
                        : SizedBox(
                            key: const ValueKey('recent-results-scroll'),
                            height: recent.isEmpty
                                ? itemExtent
                                : itemExtent *
                                      recent.length.clamp(1, visibleItemCount),
                            child: recentContent,
                          );
                  },
                );
            return expand ? Expanded(child: recentList) : recentList;
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
    showBoardNumber: tournament.directorModeEnabled,
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
