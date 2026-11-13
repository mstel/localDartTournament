import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show KnockoutBracketView, ProductionTournamentRuntime;

import '../../../../../shared/theme/tournament_display_palette.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';
import '../../utils/match_display_label.dart';
import '../../../domain/player_insight.dart';
import '../../../domain/second_screen_widget_placement.dart';
import '../../../application/tournament_director_snapshot.dart';
import '../../../domain/engines/group_standings_engine.dart';
import '../../../domain/tournament_flow_priority_settings.dart';
import '../../../domain/engines/qualification_certainty.dart';
import '../../../application/group_stage_preview_service.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../application/tournament_timing.dart';
import '../../../application/group_advancement_forecast_service.dart';
import '../../../application/player_insights_service.dart';
import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../domain/engines/group_advancement_forecast_engine.dart';
import 'standings_table.dart';
import 'recommended_matches_table.dart';
import 'player_insight_badges.dart';
import '../../../data/app_database.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../../rankings/application/local_ranking_elo_service.dart';
import '../../../../rankings/application/tournament_ranking_changes_service.dart';
import '../../../../rankings/domain/local_elo_calculator.dart';
import '../../../../rankings/domain/local_ranking.dart';
import '../../../data/tournament_storage.dart';
import 'recent_match_result_card.dart';
import '../../../../league/presentation/league_overview.dart';

const Map<String, String> _monitorWidgetTitles = {
  'combined': 'Tabellen/Siegprognose mit Umschalter',
  'knockoutBracket': 'K.-o.-Turnierbaum',
  'recent': 'Zuletzt beendete Matches',
  'boards': 'Nächste Begegnungen',
  'stageProgress': 'Fortschritt nach Phasen',
  'hints': 'Hinweise & Empfehlungen',
  'highlights': 'Bestleistungen & Highlights',
  'ranking': 'Rangliste',
  'teamComparison': 'Mannschaftsvergleich',
  'kratzerLives': 'Leben-Übersicht',
  'kratzerHandicaps': 'Handicaps',
};

enum _StandingsDisplayMode { standings, forecast }

const String _standardMonitorLayoutName = 'Standard';

typedef _RankingStandings = ({
  String rankingName,
  List<LocalEloPlayer> entries,
  Map<String, int> deltas,
  Map<String, int?> previousPositions,
});

const List<SecondScreenWidgetPlacement> _defaultMonitorLayout = [
  SecondScreenWidgetPlacement(
    widgetId: 'boards',
    widthUnits: 2,
    heightUnits: 2,
    columnIndex: 0,
  ),
  SecondScreenWidgetPlacement(
    widgetId: 'combined',
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

/// Feste, responsive Info-Tafel für den Vereinsheim-TV (Zweitbildschirm-Modus).
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
  bool _showOnlyRankingParticipants = false;
  _StandingsDisplayMode _standingsDisplayMode = _StandingsDisplayMode.standings;
  final _previewVerticalController = ScrollController();
  final _previewHorizontalController = ScrollController();
  final _recentResultsController = ScrollController();
  TournamentFlowPrioritySettings get _prioritySettings {
    final settings = widget.tournament.tournamentSettings;
    return TournamentFlowPrioritySettings(
      playerMatchDeficitThreshold: settings.playerMatchDeficitThreshold,
      groupMatchDeficitThreshold: settings.groupMatchDeficitThreshold,
      usePercentageForGroups: settings.usePercentageForGroups,
    );
  }

  String? _prioritySettingsError;
  late Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges;
  late Future<Map<String, List<PlayerInsight>>> _playerInsights;
  late String _eloInputFingerprint;
  late Future<List<_RankingStandings>> _rankingStandings;
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
    unawaited(_removeUnavailableRankingWidgets());
    _refreshEloChanges();
    _refreshPlayerInsights();
    _refreshRankingStandings();
    _refreshAdvancementForecast();
  }

  List<SecondScreenWidgetPlacement> _savedLayoutOrDefault() {
    final activeName = widget.tournament.secondScreenActiveLayout;
    final saved = activeName == null
        ? null
        : widget.tournament.secondScreenLayouts[activeName];
    final placements = saved ?? _defaultMonitorLayout;
    final normalized = <SecondScreenWidgetPlacement>[];
    for (final placement in placements) {
      if (placement.widgetId == 'liveBoard' ||
          placement.widgetId == 'nextStagePreview') {
        continue;
      }
      final widgetId = switch (placement.widgetId) {
        'forecast' || 'standings' => 'combined',
        _ => placement.widgetId,
      };
      if (widgetId == 'combined' &&
          normalized.any((item) => item.widgetId == 'combined')) {
        continue;
      }
      normalized.add(
        widgetId == placement.widgetId
            ? placement
            : SecondScreenWidgetPlacement(
                widgetId: widgetId,
                widthUnits: placement.widthUnits,
                heightUnits: placement.heightUnits,
                startsNewRow: placement.startsNewRow,
                columnIndex: placement.columnIndex,
              ),
      );
    }
    return _withIndependentColumns(
      normalized.where(_isMonitorWidgetAvailable).toList(),
    );
  }

  bool _isMonitorWidgetAvailable(SecondScreenWidgetPlacement placement) {
    if (placement.widgetId == 'standings' ||
        placement.widgetId == 'liveBoard' ||
        placement.widgetId == 'nextStagePreview') {
      return false;
    }
    if (placement.widgetId == 'ranking') {
      return widget.tournament.leagueMatch == null &&
          widget.tournament.countsForRanking &&
          widget.tournament.rankingIds.isNotEmpty;
    }
    if (placement.widgetId == 'teamComparison') {
      return widget.tournament.leagueMatch != null;
    }
    if (placement.widgetId == 'kratzerLives') {
      return widget.tournament.runStages.any(
        (stage) => stage is KnockoutTournamentRunStage && stage.isKratzer,
      );
    }
    if (placement.widgetId == 'kratzerHandicaps') {
      return widget.tournament.runStages.any(
        (stage) =>
            stage is KnockoutTournamentRunStage &&
            stage.isKratzer &&
            stage.kratzerHandicapsEnabled,
      );
    }
    if (placement.widgetId == 'knockoutBracket') {
      return widget.tournament.runStages.any(
        (stage) => stage is KnockoutTournamentRunStage && !stage.isKratzer,
      );
    }
    return true;
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

  @override
  void didUpdateWidget(covariant TournamentSecondScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _monitorPlacements = _monitorPlacements
        .where(_isMonitorWidgetAvailable)
        .toList();
    unawaited(_removeUnavailableRankingWidgets());
    final resultFingerprint = _resultsInputFingerprint(widget.tournament);
    if (resultFingerprint != _eloInputFingerprint) {
      _refreshEloChanges(fingerprint: resultFingerprint);
      _refreshRankingStandings();
      _refreshPlayerInsights();
    }
    final forecastFingerprint = _calculationFingerprint(widget.tournament);
    if (forecastFingerprint != _forecastFingerprint) {
      _refreshAdvancementForecast(fingerprint: forecastFingerprint);
    }
  }

  String _resultsInputFingerprint(CreatedTournament tournament) => jsonEncode({
    'id': tournament.id,
    'countsForRanking': tournament.countsForRanking,
    'rankingIds': tournament.rankingIds,
    'showPlayerInsights': tournament.showPlayerInsights,
    'tournamentDate': tournament.tournamentDate?.toIso8601String(),
    'startedAt': tournament.startedAt?.toIso8601String(),
    'finishedAt': tournament.finishedAt?.toIso8601String(),
    'players': [
      for (final player in tournament.players)
        for (final individual in player.individuals)
          [individual.profileId, individual.name],
    ],
    'results': [
      for (final stage in tournament.runStages)
        for (final match in _matchesOf(stage))
          if (match.hasResult)
            {
              'round': match.round,
              'placementKey': match.placementKey,
              'label': matchDisplayLabel(match.label, fallback: ''),
              'isKratzer': match.isKratzer,
              'participants': [
                for (final player in [
                  if (match.homePlayer != null) match.homePlayer!,
                  if (match.awayPlayer != null) match.awayPlayer!,
                  ...match.players,
                ])
                  for (final individual in player.individuals)
                    [individual.profileId, individual.name],
              ],
              'scratchedPlayer': [
                match.scratchedPlayer?.profileId,
                match.scratchedPlayer?.name,
              ],
              'homeLegs': match.homeLegs,
              'awayLegs': match.awayLegs,
              'homeSets': match.homeSets,
              'awaySets': match.awaySets,
              'withdrawalSignature': match.withdrawalSignature,
              'withdrawalHadResult': match.withdrawalHadResult,
              'startedAt': match.startedAt?.toIso8601String(),
              'finishedAt': match.finishedAt?.toIso8601String(),
              'annulled': match.isAnnulled,
              'withdrawalIgnored': match.withdrawalIgnored,
              'bestPerformances': [
                for (final performance in match.bestPerformances)
                  performance.toJson(),
              ],
            },
    ],
  });

  String _calculationFingerprint(CreatedTournament tournament) => jsonEncode({
    'id': tournament.id,
    'countsForRanking': tournament.countsForRanking,
    'rankingIds': tournament.rankingIds,
    'showPlayerInsights': tournament.showPlayerInsights,
    'tournamentDate': tournament.tournamentDate?.toIso8601String(),
    'startedAt': tournament.startedAt?.toIso8601String(),
    'finishedAt': tournament.finishedAt?.toIso8601String(),
    'stages': [
      for (final stage in tournament.runStages)
        switch (stage) {
          GroupTournamentRunStage() => stage.toJson(),
          KnockoutTournamentRunStage() => stage.toJson(),
          _ => {'name': stage.name},
        },
    ],
  });

  Future<void> _removeUnavailableRankingWidgets() async {
    if (widget.tournament.leagueMatch == null &&
        widget.tournament.countsForRanking &&
        widget.tournament.rankingIds.isNotEmpty) {
      return;
    }

    final changedLayouts = <String, List<SecondScreenWidgetPlacement>>{};
    for (final entry in widget.tournament.secondScreenLayouts.entries) {
      final filtered = entry.value
          .where((placement) => placement.widgetId != 'ranking')
          .toList();
      if (filtered.length != entry.value.length) {
        changedLayouts[entry.key] = filtered;
      }
    }
    final activeLayout = widget.tournament.secondScreenActiveLayout;
    if (activeLayout != null &&
        _monitorPlacements.any(
          (placement) => placement.widgetId == 'ranking',
        )) {
      _monitorPlacements = _monitorPlacements
          .where((placement) => placement.widgetId != 'ranking')
          .toList();
      changedLayouts[activeLayout] = List.of(_monitorPlacements);
    }
    try {
      for (final entry in changedLayouts.entries) {
        await _storage.saveSecondScreenLayout(
          tournament: widget.tournament,
          name: entry.key,
          placements: entry.value,
          activate: false,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _prioritySettingsError =
              'Das inaktive Ranglisten-Widget konnte nicht aus dem Zweitmonitor-Layout entfernt werden: $error',
        );
      }
    }
  }

  void _refreshEloChanges({String? fingerprint}) {
    _eloInputFingerprint =
        fingerprint ?? _resultsInputFingerprint(widget.tournament);
    _eloChanges = TournamentMatchEloService(
      database: _database,
      tournamentStorage: _storage,
    ).calculate(widget.tournament);
  }

  void _refreshPlayerInsights() {
    final tournament = widget.tournament;
    if (!widget.isStandaloneWindow ||
        widget.showNextStagePreviewInitially ||
        !tournament.directorModeEnabled ||
        !tournament.showPlayerInsights ||
        tournament.players.any((player) => player.isTeam)) {
      _playerInsights = Future.value(const {});
      return;
    }
    _playerInsights = PlayerInsightsService(
      database: _database,
      storage: _storage,
    ).calculate(tournament: tournament);
  }

  void _refreshRankingStandings() {
    _rankingStandings = _loadRankingStandings(widget.tournament);
  }

  Future<List<_RankingStandings>> _loadRankingStandings(
    CreatedTournament tournament,
  ) async {
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return const [];
    }
    final selectedRankings = (await _database.loadLocalRankings())
        .where(
          (ranking) =>
              ranking.type == RankingType.elo &&
              !(ranking.isCompleted && tournament.finishedAt == null) &&
              tournament.rankingIds.contains(ranking.id),
        )
        .toList();
    final service = LocalRankingEloService(
      database: _database,
      tournamentStorage: _storage,
    );
    final profiles = await _database.loadPlayerProfiles();
    final profileNames = {
      for (final profile in profiles) profile.id: profile.displayName,
    };
    final changes = await TournamentRankingChangesService(
      database: _database,
      storage: _storage,
    ).calculate(tournament);
    final standings = <_RankingStandings>[];
    for (final ranking in selectedRankings) {
      final rankingPlayerIds = await _database.loadRankingPlayerIds(ranking.id);
      final before = await service.calculateThroughTournament(
        ranking,
        tournament,
        includeTournament: false,
      );
      final after = await service.calculateThroughTournament(
        ranking,
        tournament,
        includeTournament: true,
      );
      final beforeEntries = _allRankingMembers(
        rankingPlayerIds,
        profileNames,
        before.entries,
        ranking.startRating,
      );
      final afterEntries = _allRankingMembers(
        rankingPlayerIds,
        profileNames,
        after.entries,
        ranking.startRating,
      );
      final beforePositions = {
        for (var index = 0; index < beforeEntries.length; index++)
          beforeEntries[index].id: index + 1,
      };
      standings.add((
        rankingName: ranking.name,
        entries: afterEntries,
        deltas: {
          for (final change in changes)
            if (change.rankingId == ranking.id)
              change.playerProfileId: change.delta,
        },
        previousPositions: {
          for (final entry in after.entries)
            entry.id: beforePositions[entry.id],
        },
      ));
    }
    return standings;
  }

  List<LocalEloPlayer> _allRankingMembers(
    List<String> playerIds,
    Map<String, String> profileNames,
    List<LocalEloPlayer> rankedEntries,
    int startRating,
  ) {
    final entriesById = {for (final entry in rankedEntries) entry.id: entry};
    final entries = [
      for (final id in playerIds)
        if (profileNames[id] case final name?)
          entriesById[id] ??
              LocalEloPlayer(id: id, name: name, rating: startRating),
    ];
    entries.sort((left, right) => right.rating.compareTo(left.rating));
    return entries;
  }

  void _refreshAdvancementForecast({String? fingerprint}) {
    _forecastFingerprint =
        fingerprint ?? _calculationFingerprint(widget.tournament);
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
    final displayColors = TournamentDisplayColors(
      background: TournamentDisplayPalette.background,
      card: TournamentDisplayPalette.card,
      cardEmphasis: TournamentDisplayPalette.cardEmphasis,
      border: TournamentDisplayPalette.border,
      accent: theme.colorScheme.tertiary,
      text: TournamentDisplayPalette.text,
      mutedText: TournamentDisplayPalette.mutedText,
    );
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
        color: displayColors.background,
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
                      color: displayColors.cardEmphasis,
                      border: Border.all(color: displayColors.accent),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tv, size: 16, color: displayColors.accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.isStandaloneWindow
                                ? 'TV-LIVE-ÜBERSICHT'
                                : 'LIVE-TICKER',
                            style: TextStyle(
                              color: displayColors.accent,
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
                      color: displayColors.text,
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
                  icon: Icon(Icons.close, color: displayColors.mutedText),
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
                  )
                : _buildOverview(
                    context,
                    t: t,
                    activeIndex: activeIndex,
                    activeStage: activeStage,
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
    required List<GroupMatch> playedMatches,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1000 && constraints.maxHeight >= 620;
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
        if (activeStage is KnockoutTournamentRunStage &&
            !activeStage.isKratzer) {
          content = activeStage.eliminationLossLimit >= 3
              ? KnockoutBracketView(
                  stage: activeStage,
                  placementMatches: activeStage.placementMatches,
                  qualifyingRank: 1,
                  onEditResult: (_) {},
                  canEditResults: false,
                )
              : _buildBracketPreview(
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
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildRecentMatchesAndEloPanel(
                context,
                t,
                playedMatches,
                expand: false,
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
                  _MonitorTournamentClock(tournament: t),
                  if (stageMatchCounts != null &&
                      activeStage is KnockoutTournamentRunStage)
                    Text(
                      '${activeStage.name}: '
                      '$stagePlayedCount/$stageTotalCount',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  if (widget.isStandaloneWindow) ...[
                    if (_nextKnockoutStage(t, activeIndex, activeStage) != null)
                      OutlinedButton.icon(
                        key: const ValueKey(
                          'monitor-next-stage-preview-header-button',
                        ),
                        onPressed: () =>
                            setState(() => _showNextStagePreview = true),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Vorschau nächste Phase'),
                      ),
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
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCustomLayoutStatusBar(t, activeStage),
            LayoutBuilder(
              builder: (context, toolbarConstraints) =>
                  _buildCustomLayoutToolbar(
                    context,
                    t,
                    activeIndex,
                    activeStage,
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
          ],
        );
        final compactHeader =
            constraints.maxWidth < 480 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compactHeader)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: min(320, constraints.maxHeight * 0.42),
                ),
                child: SingleChildScrollView(child: header),
              )
            else
              header,
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
  ) {
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
          _MonitorTournamentClock(tournament: tournament),
          if (knockoutStage != null)
            Text(
              '${knockoutStage.name}: '
              '${_matchesOf(knockoutStage).where((match) => match.hasResult).length}/'
              '${_countMatchesForProgress(knockoutStage)}',
              style: const TextStyle(color: Colors.white70),
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
        _monitorPlacements.any((placement) => placement.widthUnits > 1) &&
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
    final rows = <List<int>>[[]];
    for (final index in indexes) {
      if (index != indexes.first && _monitorPlacements[index].startsNewRow) {
        rows.add([]);
      }
      rows.last.add(index);
    }
    return SizedBox(
      width: unitWidth * 2 + spacing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    int activeIndex,
    TournamentRunStage? activeStage,
    double width,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: width < 640 ? WrapAlignment.start : WrapAlignment.end,
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
        ],
        if (tournament.secondScreenLayouts.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _loadMonitorLayout,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Layout laden'),
          ),
        if (_isEditingLayout) ...[
          FilledButton.icon(
            onPressed: _applyMonitorLayout,
            icon: const Icon(Icons.check),
            label: const Text('Layout anwenden'),
          ),
          OutlinedButton.icon(
            onPressed: _resetMonitorLayout,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Layout zurücksetzen'),
          ),
        ],
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _useCustomLayout = false;
            _isEditingLayout = false;
          }),
          icon: const Icon(Icons.tv),
          label: const Text('Standardlayout'),
        ),
        if (!_isEditingLayout)
          OutlinedButton.icon(
            onPressed: _startMonitorLayoutEditing,
            icon: const Icon(Icons.dashboard_customize),
            label: const Text('Layout anpassen'),
          ),
        if (_nextKnockoutStage(tournament, activeIndex, activeStage) != null)
          OutlinedButton.icon(
            onPressed: () => setState(() => _showNextStagePreview = true),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Vorschau nächste Phase'),
          ),
      ],
    );
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
      case 'combined':
        return _buildStandingsAndForecastWidget(
          context,
          tournament,
          activeIndex,
          activeStage,
        );
      case 'knockoutBracket':
        final stage = activeStage is KnockoutTournamentRunStage
            ? activeStage
            : _nextKnockoutStage(tournament, activeIndex, activeStage);
        if (stage == null || stage.isKratzer) return const SizedBox.shrink();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: KnockoutBracketView(
              stage: stage,
              qualifyingRank: 1,
              placementMatches: stage.placementMatches,
              onEditResult: (_) {},
              canEditResults: false,
            ),
          ),
        );
      case 'recent':
        return _buildRecentMatchesAndEloPanel(
          context,
          tournament,
          playedMatches,
          expand: true,
        );
      case 'liveBoard':
        return const SizedBox.shrink();
      case 'stageProgress':
        return SingleChildScrollView(
          child: _buildStageProgressPanel(context, tournament),
        );
      case 'hints':
        return _buildPriorityHintsPanel(context, activeStage);
      case 'highlights':
        return SingleChildScrollView(
          child: _buildHighlightsPanel(context, tournament),
        );
      case 'ranking':
        return SingleChildScrollView(
          child: _buildRankingPanel(context, tournament),
        );
      case 'teamComparison':
        final league = tournament.leagueMatch;
        return league == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(child: LeagueOverview(league: league));
      case 'nextStagePreview':
        return const SizedBox.shrink();
      case 'kratzerLives':
        return SingleChildScrollView(
          child: _buildKratzerLivesPanel(tournament, activeStage),
        );
      case 'kratzerHandicaps':
        return SingleChildScrollView(
          child: _buildKratzerHandicapsPanel(context, tournament, activeStage),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildKratzerLivesPanel(
    CreatedTournament tournament,
    TournamentRunStage? activeStage,
  ) {
    final kratzerStages = tournament.runStages
        .whereType<KnockoutTournamentRunStage>()
        .where((stage) => stage.isKratzer)
        .toList();
    final stage =
        activeStage is KnockoutTournamentRunStage && activeStage.isKratzer
        ? activeStage
        : kratzerStages.isEmpty
        ? null
        : kratzerStages.first;
    if (stage == null) return const SizedBox.shrink();

    final players = stage.participants.isNotEmpty
        ? stage.participants
        : tournament.players;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final player in players)
          ListTile(
            key: ValueKey('kratzer-life-${player.name}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              player.name,
              style: const TextStyle(color: Colors.white),
            ),
            trailing: Text(
              '${stage.livesRemainingFor(player)} Leben',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: Icon(
              stage.livesRemainingFor(player) == 0
                  ? Icons.person_off_outlined
                  : Icons.favorite_outline,
              color: stage.livesRemainingFor(player) == 0
                  ? Colors.white54
                  : const Color(0xFF70E0BA),
            ),
          ),
      ],
    );
  }

  Widget _buildKratzerHandicapsPanel(
    BuildContext context,
    CreatedTournament tournament,
    TournamentRunStage? activeStage,
  ) {
    final stages = tournament.runStages
        .whereType<KnockoutTournamentRunStage>()
        .where((stage) => stage.isKratzer && stage.kratzerHandicapsEnabled)
        .toList();
    final stage =
        activeStage is KnockoutTournamentRunStage &&
            activeStage.isKratzer &&
            activeStage.kratzerHandicapsEnabled
        ? activeStage
        : stages.isEmpty
        ? null
        : stages.first;
    if (stage == null) return const SizedBox.shrink();

    final players = stage.participants.isNotEmpty
        ? stage.participants
        : tournament.players;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < players.length; index++)
          ListTile(
            key: ValueKey(
              'kratzer-handicap-player-$index-${players[index].name}',
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: players[index].name),
                  if (stage.kratzerHandicapAssignments[index] case final label?)
                    TextSpan(
                      text: ' · $label',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                      ).copyWith(color: Theme.of(context).colorScheme.tertiary),
                    ),
                ],
              ),
              style: const TextStyle(color: TournamentDisplayPalette.text),
            ),
          ),
      ],
    );
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
          startsNewRow: moving.widthUnits == 1 ? false : edge == 2 || edge == 3,
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
              _isMonitorWidgetAvailable(
                SecondScreenWidgetPlacement(widgetId: id),
              ),
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
    setState(() {
      if (selected == 'knockoutBracket') {
        _monitorPlacements = [
          for (final placement in _monitorPlacements)
            SecondScreenWidgetPlacement(
              widgetId: placement.widgetId,
              widthUnits: placement.widthUnits.clamp(1, 2),
              heightUnits: placement.heightUnits,
              startsNewRow: placement.startsNewRow,
            ),
          const SecondScreenWidgetPlacement(
            widgetId: 'knockoutBracket',
            widthUnits: 4,
            heightUnits: 3,
            startsNewRow: true,
          ),
        ];
      } else {
        _monitorPlacements.add(
          SecondScreenWidgetPlacement(
            widgetId: selected,
            columnIndex: hasIndependentColumns
                ? columnHeights[0] <= columnHeights[1]
                      ? 0
                      : 1
                : null,
          ),
        );
      }
    });
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
    return FutureBuilder<List<_RankingStandings>>(
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
        final participantIds = {
          for (final player in tournament.players)
            for (final individual in player.individuals)
              if (individual.profileId != null) individual.profileId!,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                key: const ValueKey('ranking-participants-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Nur Teilnehmer anzeigen'),
                subtitle: const Text('Ausgeschaltet: alle Mitglieder'),
                value: _showOnlyRankingParticipants,
                onChanged: (value) =>
                    setState(() => _showOnlyRankingParticipants = value),
              ),
            ),
            for (final ranking in standings) ...[
              Row(
                children: [
                  const Icon(
                    Icons.leaderboard_outlined,
                    color: Color(0xFF70E0BA),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ranking.rankingName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 12, color: Colors.white24),
              for (var index = 0; index < ranking.entries.length; index++)
                if (!_showOnlyRankingParticipants ||
                    participantIds.contains(ranking.entries[index].id))
                  _buildRankingEntry(
                    ranking,
                    ranking.entries[index],
                    index + 1,
                  ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRankingEntry(
    _RankingStandings ranking,
    LocalEloPlayer entry,
    int currentPosition,
  ) {
    final delta = ranking.deltas[entry.id] ?? 0;
    final previousPosition = ranking.previousPositions[entry.id];
    final positionChange = previousPosition == null
        ? null
        : previousPosition - currentPosition;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$currentPosition. ${entry.name} – ${entry.rating} Elo',
            style: const TextStyle(color: Colors.white),
          ),
          if (delta != 0)
            Text(
              delta > 0 ? '+$delta' : '$delta',
              key: ValueKey('ranking-elo-delta-${entry.id}'),
              style: TextStyle(
                color: delta > 0
                    ? const Color(0xFF65D58A)
                    : const Color(0xFFFF7777),
                fontWeight: FontWeight.bold,
              ),
            ),
          if (positionChange != null && positionChange != 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  positionChange > 0
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  key: ValueKey('ranking-position-arrow-${entry.id}'),
                  size: 16,
                  color: positionChange > 0
                      ? const Color(0xFF65D58A)
                      : const Color(0xFFFF7777),
                ),
                Text(
                  'Platz $currentPosition',
                  key: ValueKey('ranking-position-${entry.id}'),
                  style: TextStyle(
                    color: positionChange > 0
                        ? const Color(0xFF65D58A)
                        : const Color(0xFFFF7777),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStandingsAndPreviewControl(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? stage, {
    bool expand = true,
  }) {
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
            child: SingleChildScrollView(
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
                'Keine K.-o.-Phase als Nächstes geplant.',
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
        if (player != null && !player.name.startsWith('Teilnehmer ')) {
          return player.shortDisplayName;
        }
        if (roundIndex == 0) return 'Offen';
        final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
        return matchDisplayLabel(
          'Gewinner Spiel $sourceMatchNumber',
          fallback: '',
        );
      }
      if (!hasGroupStageResults) {
        if (roundIndex == 0) {
          return 'Teilnehmer offen';
        }
        if (roundIndex > 0) {
          final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
          if (player == null || player.name.startsWith('Teilnehmer ')) {
            return matchDisplayLabel(
              'Gewinner Spiel $sourceMatchNumber',
              fallback: '',
            );
          }
          return player.name;
        }
        if (player == null || player.name.startsWith('Teilnehmer ')) {
          return 'Teilnehmer offen';
        }
        return player.name;
      }
      if (roundIndex > 0) {
        final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
        return player?.name ??
            matchDisplayLabel(
              'Gewinner Spiel $sourceMatchNumber',
              fallback: '',
            );
      }
      if (player == null || player.name.startsWith('Teilnehmer ')) {
        return 'Teilnehmer offen';
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
                  ? 'Die Setzplätze der Phase stehen fest.'
                  : 'Die angezeigten Plätze entsprechen dem aktuellen Tabellenstand und sind vorläufig.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: previewStage.rounds.isEmpty
              ? const Center(
                  child: Text(
                    'Für diese Phase ist noch kein Turnierbaum vorhanden.',
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
            matchDisplayLabel(match.label, fallback: 'Begegnung $matchNumber'),
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
          'Keine aktive Phase vorhanden',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    if (stage is GroupTournamentRunStage) {
      final runStageIndex = t.runStages.indexOf(stage);
      final showDraws =
          runStageIndex < 0 ||
          runStageIndex >= t.stages.length ||
          t.stages[runStageIndex].gameFormat.allowsDraws;
      final cards = [
        for (var i = 0; i < stage.groups.length; i++)
          _buildGroupStandingsCard(
            context,
            stage.groups[i],
            groupNumber: i + 1,
            qualificationPlan: stage.qualificationPlan,
            tieBreakers: stage.tieBreakers,
            full: full,
            showDraws: showDraws,
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
              'Aktuelle Begegnungen und Paarungen siehe Spielansetzungen.',
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
    bool showDraws = true,
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
            showDraws: showDraws,
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
    final runningMatches = const OrderOfPlayController()
        .plan(t, activeIndex)
        .running;
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
        ? FutureBuilder<Map<String, List<PlayerInsight>>>(
            future: _playerInsights,
            builder: (context, snapshot) => _buildDirectorBoardQueue(
              context,
              t,
              activeIndex,
              playerInsights: snapshot.data ?? const {},
              playerInsightsError: snapshot.error,
            ),
          )
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
                        const Tooltip(
                          message:
                              'Prioritätshinweis: Diese Gruppe oder Teilnehmer '
                              'liegen im Spielplan zurück.',
                          child: Icon(
                            Icons.priority_high,
                            size: 18,
                            color: TournamentDisplayPalette.accent,
                          ),
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
                FutureBuilder<Map<String, List<PlayerInsight>>>(
                  future: _playerInsights,
                  builder: (context, snapshot) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (snapshot.hasError)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              'Player-Insights konnten nicht geladen werden: '
                              '${snapshot.error}',
                              style: const TextStyle(color: Colors.amber),
                            ),
                          ),
                        RecommendedMatchesTable(
                          groups: recommendedGroups,
                          prioritizedMatches: flowPriority.prioritizedMatches,
                          deprioritizedMatches:
                              flowPriority.deprioritizedMatches,
                          emptyMessage:
                              'Keine offenen Partien in dieser Phase.',
                          dense: true,
                          playerInsights: snapshot.data ?? const {},
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tournament.directorModeEnabled ||
            runningMatches.isNotEmpty) ...[
          Row(
            children: [
              const Icon(
                Icons.play_circle_fill,
                size: 22,
                color: TournamentDisplayPalette.accent,
              ),
              const SizedBox(width: 8),
              Text(
                widget.tournament.directorModeEnabled
                    ? 'Board Belegung & aktive Partien'
                    : 'Aktuelle Partien (${runningMatches.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.tournament.directorModeEnabled)
            FutureBuilder<Map<String, List<PlayerInsight>>>(
              future: _playerInsights,
              builder: (context, insightSnapshot) => LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final columns = constraints.maxWidth >= 740
                      ? 4
                      : constraints.maxWidth >= 460
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  final snapshot = TournamentDirectorSnapshot(
                    widget.tournament,
                    activeIndex,
                  );
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (
                        var board = 1;
                        board <= widget.tournament.boardCount;
                        board++
                      )
                        Builder(
                          builder: (context) {
                            final running = runningMatches
                                .where(
                                  (entry) => entry.match.boardNumber == board,
                                )
                                .firstOrNull;
                            return running == null
                                ? _buildFreeBoardOccupancyTile(
                                    context,
                                    board: board,
                                    since: _freeBoardSince(
                                      snapshot,
                                      widget.tournament,
                                      board,
                                    ),
                                    width: width,
                                  )
                                : _buildRunningMatchTile(
                                    context,
                                    running,
                                    width: width,
                                    playerInsights:
                                        insightSnapshot.data ?? const {},
                                  );
                          },
                        ),
                    ],
                  );
                },
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                final columns = constraints.maxWidth >= 740
                    ? 4
                    : constraints.maxWidth >= 460
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final entry in runningMatches)
                      _buildRunningMatchTile(context, entry, width: width),
                  ],
                );
              },
            ),
          const SizedBox(height: 16),
        ],
        Text(
          widget.tournament.directorModeEnabled
              ? 'Nächste Begegnungen'
              : 'Nächste Partien · Vorschläge',
          style: const TextStyle(
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
              'Keine offenen Partien in dieser Phase.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }

  String _displayGroupLabel(String? groupKey) {
    if (groupKey == null || groupKey.trim().isEmpty) return '';
    final cleaned = groupKey.trim();
    final separatorIndex = cleaned.indexOf(':');
    if (separatorIndex >= 0) {
      final prefix = cleaned.substring(0, separatorIndex).trim();
      if (prefix.isNotEmpty && int.tryParse(prefix) != null) {
        final remainder = cleaned.substring(separatorIndex + 1).trim();
        if (remainder.isNotEmpty) return remainder;
      }
    }
    return cleaned;
  }

  Widget _buildRunningMatchTile(
    BuildContext context,
    PlayEntry entry, {
    required double width,
    Map<String, List<PlayerInsight>> playerInsights = const {},
  }) {
    final match = entry.match;
    return Container(
      width: width,
      key: ValueKey(
        'second-screen-running-match-${match.round}-'
        '${match.homePlayer?.profileId ?? match.homePlayer?.name}-'
        '${match.awayPlayer?.profileId ?? match.awayPlayer?.name}',
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TournamentDisplayPalette.card,
        border: Border.all(color: TournamentDisplayPalette.accent, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RunningMatchElapsedLabel(
            boardNumber: match.boardNumber,
            startedAt: match.startedAt,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _runningPlayerName(
                  match.homePlayer,
                  match.awayPlayer,
                  playerInsights,
                  textAlign: TextAlign.start,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '-',
                  style: TextStyle(
                    color: TournamentDisplayPalette.mutedText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: _runningPlayerName(
                  match.awayPlayer,
                  match.homePlayer,
                  playerInsights,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runningPlayerName(
    TournamentPlayer? player,
    TournamentPlayer? opponent,
    Map<String, List<PlayerInsight>> playerInsights, {
    required TextAlign textAlign,
  }) {
    if (player == null) {
      return const Text(
        'Offen',
        style: TextStyle(
          color: TournamentDisplayPalette.text,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      );
    }
    final playerId =
        player.profileId ?? 'name:${player.name.trim().toLowerCase()}';
    final opponentId = opponent == null
        ? null
        : opponent.profileId ?? 'name:${opponent.name.trim().toLowerCase()}';
    final List<PlayerInsight> insights =
        (playerInsights[playerId] ?? const <PlayerInsight>[])
            .where(
              (insight) =>
                  insight.rivalId == null || insight.rivalId == opponentId,
            )
            .take(3)
            .toList();
    final name = Text(
      player.shortDisplayName,
      style: const TextStyle(
        color: TournamentDisplayPalette.text,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
    if (insights.isEmpty) return name;
    return Tooltip(
      message: insights
          .map((insight) => '${insight.type.label}: ${insight.explanation}')
          .join('\n'),
      child: name,
    );
  }

  Widget _buildFreeBoardOccupancyTile(
    BuildContext context, {
    required int board,
    required DateTime since,
    required double width,
  }) => Container(
    width: width,
    key: ValueKey('second-screen-free-board-$board'),
    constraints: const BoxConstraints(minHeight: 88),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: TournamentDisplayPalette.card,
      border: Border.all(color: const Color(0xFF4ED9A4), width: 2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: _FreeBoardStatusLabel(
      boardName: widget.tournament.boardDisplayName(board),
      since: since,
    ),
  );

  Widget _buildDirectorBoardQueue(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex, {
    Map<String, List<PlayerInsight>> playerInsights = const {},
    Object? playerInsightsError,
  }) {
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
              if (playerInsightsError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Player-Insights konnten nicht geladen werden: '
                    '$playerInsightsError',
                    style: const TextStyle(color: Colors.amber),
                  ),
                ),
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
                                  assignment.entry.match.hasPlayers &&
                                  !identical(
                                    assignment.entry.match,
                                    running?.match,
                                  ),
                            )
                            .take(3)
                            .toList();
                        final groupNames = <String>{
                          for (final assignment in upcoming)
                            _displayGroupLabel(assignment.entry.groupKey),
                        }.where((value) => value.isNotEmpty).toList()..sort();
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
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Empfohlene Partien für '
                                  '${tournament.boardDisplayName(board)}'
                                  '${tournament.directorSchedulingStrategy == 'group' && groupNames.isNotEmpty ? ' · ${groupNames.join(' · ')}' : ''}',
                                  style: const TextStyle(
                                    color: TournamentDisplayPalette.mutedText,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              if (upcoming.isEmpty && running == null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: _FreeBoardStatusLabel(
                                    boardName: tournament.boardDisplayName(
                                      board,
                                    ),
                                    since: _freeBoardSince(
                                      snapshot,
                                      tournament,
                                      board,
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
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              upcoming[index]
                                                  .entry
                                                  .match
                                                  .participantShortLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: TournamentDisplayPalette
                                                    .text,
                                              ),
                                            ),
                                            if (playerInsights.isNotEmpty)
                                              PlayerInsightBadgeRow(
                                                insights: insightsForMatch(
                                                  upcoming[index].entry.match,
                                                  playerInsights,
                                                ),
                                              ),
                                          ],
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
            ],
          ),
        );
      },
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
    final recentSubstitutions =
        t.activityLog.where((entry) => entry.type == 'substitution').toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.history, size: 20, color: Color(0xFF70E0BA)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t.leagueMatch == null
                    ? 'Zuletzt beendete Matches'
                    : 'Aktuelles',
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
                    final activityRows = [
                      for (final entry in recentSubstitutions.take(5))
                        ListTile(
                          key: ValueKey(
                            'recent-activity-${entry.timestamp.toIso8601String()}',
                          ),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(
                            Icons.swap_horiz,
                            color: Color(0xFF70E0BA),
                          ),
                          title: Text(
                            entry.message,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...activityRows,
                        if (expand)
                          Expanded(child: recentContent)
                        else
                          SizedBox(
                            key: const ValueKey('recent-results-scroll'),
                            height: recent.isEmpty
                                ? itemExtent
                                : itemExtent *
                                      recent.length.clamp(1, visibleItemCount),
                            child: recentContent,
                          ),
                      ],
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

  Widget _buildPriorityHintsPanel(
    BuildContext context,
    TournamentRunStage? stage,
  ) {
    final priority = TournamentFlowPriority.forStage(
      stage,
      settings: _prioritySettings,
    );
    if (priority.notices.isEmpty && _prioritySettingsError == null) {
      return const Center(child: Text('Keine aktuellen Hinweise.'));
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final notice in priority.notices)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.priority_high),
                    const SizedBox(width: 8),
                    Expanded(child: Text(notice)),
                  ],
                ),
              ),
            ),
          if (_prioritySettingsError case final error?) Text(error),
        ],
      ),
    );
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

class _MonitorTournamentClock extends StatefulWidget {
  const _MonitorTournamentClock({required this.tournament});

  final CreatedTournament tournament;

  @override
  State<_MonitorTournamentClock> createState() =>
      _MonitorTournamentClockState();
}

class _MonitorTournamentClockState extends State<_MonitorTournamentClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _MonitorTournamentClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    final tournament = widget.tournament;
    final shouldRun =
        tournament.startedAt != null &&
        tournament.finishedAt == null &&
        !tournament.isClockPaused;
    if (shouldRun == (_timer != null)) return;
    _timer?.cancel();
    _timer = shouldRun
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timing = TournamentTiming.snapshot(widget.tournament, DateTime.now());
    final elapsed = timing.elapsed;
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60);
    final seconds = elapsed.inSeconds.remainder(60);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        const Icon(Icons.timer, size: 20, color: Color(0xFF70E0BA)),
        Text(
          hours > 0
              ? 'Turnieruhr: $hours Std. $minutes Min. ${seconds}s'
              : 'Turnieruhr: $minutes Min. ${seconds}s',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (timing.forecast != null)
          Text(
            'Ende ca. ${_formatMonitorClockTime(timing.forecast!)}',
            style: const TextStyle(color: Colors.white),
          ),
      ],
    );
  }
}

class _RunningMatchElapsedLabel extends StatefulWidget {
  const _RunningMatchElapsedLabel({
    required this.boardNumber,
    required this.startedAt,
  });

  final int? boardNumber;
  final DateTime? startedAt;

  @override
  State<_RunningMatchElapsedLabel> createState() =>
      _RunningMatchElapsedLabelState();
}

class _RunningMatchElapsedLabelState extends State<_RunningMatchElapsedLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _RunningMatchElapsedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    final shouldRun = widget.startedAt != null;
    if (shouldRun == (_timer != null)) return;
    _timer?.cancel();
    _timer = shouldRun
        ? Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.startedAt;
    final elapsed = startedAt == null
        ? null
        : DateTime.now().difference(startedAt);
    final elapsedLabel = elapsed == null ? '' : ' · ${elapsed.inMinutes} Min.';
    return Text(
      'JETZT LIVE · BOARD ${widget.boardNumber}$elapsedLabel',
      style: const TextStyle(
        color: TournamentDisplayPalette.accent,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    );
  }
}

DateTime _freeBoardSince(
  TournamentDirectorSnapshot snapshot,
  CreatedTournament tournament,
  int board,
) {
  DateTime? latestFinished;
  for (final entry in snapshot.entries) {
    final match = entry.match;
    final finishedAt = match.finishedAt;
    if (match.boardNumber == board &&
        finishedAt != null &&
        !match.isAnnulled &&
        (latestFinished == null || finishedAt.isAfter(latestFinished))) {
      latestFinished = finishedAt;
    }
  }
  final tournamentStarted = tournament.startedAt ?? tournament.createdAt;
  if (latestFinished != null && latestFinished.isAfter(tournamentStarted)) {
    return latestFinished;
  }
  return tournamentStarted;
}

class _FreeBoardStatusLabel extends StatefulWidget {
  const _FreeBoardStatusLabel({required this.boardName, required this.since});

  final String boardName;
  final DateTime since;

  @override
  State<_FreeBoardStatusLabel> createState() => _FreeBoardStatusLabelState();
}

class _FreeBoardStatusLabelState extends State<_FreeBoardStatusLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final freeMinutes = DateTime.now().difference(widget.since).inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frei - ${widget.boardName} - ${freeMinutes < 0 ? 0 : freeMinutes}min.',
          style: const TextStyle(
            color: TournamentDisplayPalette.mutedText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Text(
          'Jetzt Partie zuweisen!',
          style: TextStyle(color: TournamentDisplayPalette.mutedText),
        ),
      ],
    );
  }
}

String _formatMonitorClockTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
