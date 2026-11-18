import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show KnockoutBracketView, ProductionTournamentRuntime;

import '../../../../../app/christmas_decorations.dart';
import '../../../../../app/theme_controller.dart';
import '../../../../../shared/theme/tournament_display_palette.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/engines/placement_engine.dart';
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
import '../../../../statistics/domain/best_performance.dart';
import '../../../data/tournament_storage.dart';
import 'recent_match_result_card.dart';
import '../../../../league/domain/league_match.dart';
import '../../../../league/domain/league_player_record.dart';
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

String _combinedMonitorWidgetTitle(bool isTeamMode) => isTeamMode
    ? 'Tabellen & Zwischenstände / Mannschaftsvergleich'
    : 'Tabellen/Siegprognose mit Umschalter';

const String _standardMonitorLayoutName = 'Standard';

class _CompletionPlayerStats {
  _CompletionPlayerStats(this.player);

  final TournamentPlayer player;
  int wins = 0;
  int losses = 0;
  int legsFor = 0;
  int legsAgainst = 0;
}

typedef _RankingStandings = ({
  String rankingName,
  List<LocalEloPlayer> entries,
  Map<String, int> deltas,
  Map<String, int?> previousPositions,
});

const List<SecondScreenWidgetPlacement> _defaultMonitorLayout = [
  SecondScreenWidgetPlacement(
    widgetId: 'teamComparison',
    widthUnits: 4,
    startsNewRow: true,
  ),
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
  final _completionTeamComparisonScrollController = ScrollController();
  final _completionPlayerRecordScrollController = ScrollController();
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
  DateTime? _completionObservedAt;
  Timer? _completionWatchTimer;
  List<SecondScreenWidgetPlacement>? _placementsBeforeEditing;
  String? _dragTargetWidgetId;
  int? _dragTargetEdge;
  final Map<String, GlobalKey> _monitorDropTargetKeys = {};
  final Map<String, GlobalKey> _monitorCardKeys = {};
  double _monitorUnitHeight = 220;

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
    _checkTournamentCompletion();
    if (_completionObservedAt == null) {
      _completionWatchTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkTournamentCompletion(),
      );
    }
  }

  List<SecondScreenWidgetPlacement> _savedLayoutOrDefault() {
    final activeName = widget.tournament.secondScreenActiveLayout;
    final saved = activeName == null
        ? null
        : widget.tournament.secondScreenLayouts[activeName];
    final isStandard =
        activeName != null && _isStandardMonitorLayout(activeName);
    final placements = saved == null
        ? _defaultMonitorLayout
        : isStandard &&
              widget.tournament.leagueMatch != null &&
              !saved.any((placement) => placement.widgetId == 'teamComparison')
        ? [
            ...saved,
            const SecondScreenWidgetPlacement(
              widgetId: 'teamComparison',
              widthUnits: 4,
              startsNewRow: true,
            ),
          ]
        : saved;
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
    _checkTournamentCompletion();
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
    _completionWatchTimer?.cancel();
    _previewVerticalController.dispose();
    _previewHorizontalController.dispose();
    _recentResultsController.dispose();
    _completionTeamComparisonScrollController.dispose();
    _completionPlayerRecordScrollController.dispose();
    super.dispose();
  }

  void _checkTournamentCompletion() {
    if (widget.tournament.finishedAt == null ||
        widget.tournament.reopenedForCorrections ||
        _completionObservedAt != null) {
      return;
    }
    _completionObservedAt = DateTime.now();
    _completionWatchTimer?.cancel();
    if (mounted) setState(() {});
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

  Color _monitorCardColor(Color color) {
    if (AppThemeController.instance.themeStyleNotifier.value !=
        AppThemeStyle.christmas) {
      return color;
    }
    return color.withValues(alpha: .84);
  }

  TournamentDisplayColors _displayColors(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final christmas =
        AppThemeController.instance.themeStyleNotifier.value ==
        AppThemeStyle.christmas;
    if (isLight && !christmas) {
      final base = TournamentDisplayPalette.forColorScheme(theme.colorScheme);
      return TournamentDisplayColors(
        background: base.background,
        card: base.card,
        cardEmphasis: base.cardEmphasis,
        border: base.border,
        accent: base.accent,
        text: base.text,
        mutedText: base.mutedText,
      );
    }
    return TournamentDisplayColors(
      background: christmas
          ? Colors.transparent
          : TournamentDisplayPalette.background,
      card: _monitorCardColor(TournamentDisplayPalette.card),
      cardEmphasis: _monitorCardColor(TournamentDisplayPalette.cardEmphasis),
      border: TournamentDisplayPalette.border,
      accent: TournamentDisplayPalette.accent,
      text: TournamentDisplayPalette.text,
      mutedText: TournamentDisplayPalette.mutedText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final theme = Theme.of(context);
    final displayColors = _displayColors(context);
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
            child: _completionObservedAt != null
                ? _buildTournamentCompletionCard(context, t, playedMatches)
                : _showNextStagePreview
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
      return SizedBox(
        height: 520,
        child: ChristmasSecondScreenBackground(child: viewWidget),
      );
    }
    return ChristmasSecondScreenBackground(child: viewWidget);
  }

  Widget _buildTournamentCompletionCard(
    BuildContext context,
    CreatedTournament tournament,
    List<GroupMatch> playedMatches,
  ) {
    final theme = Theme.of(context);
    final displayColors = _displayColors(context);
    final league = tournament.leagueMatch;
    final performances = [
      for (final match in playedMatches) ...match.bestPerformances,
    ];
    final measuredDuration = TournamentTiming.durationSummary(tournament);
    final duration =
        measuredDuration?.totalDuration ??
        tournament.finishedAt!.difference(
          tournament.startedAt ?? tournament.createdAt,
        );
    final durationLabel =
        '${duration.inHours} h ${duration.inMinutes % 60} min'
        '${measuredDuration == null ? ' (geschätzt)' : ''}';
    final List<Widget> sections;
    if (league == null) {
      final placements = _completionPlacements(tournament, playedMatches);
      sections = [
        _completionSection(
          'Platzierungen',
          placements.isEmpty
              ? const Text('Keine Platzierungen verfügbar.')
              : Column(
                  children: [
                    for (var index = 0; index < placements.length; index++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: index == 0
                              ? const Color(0xFFFFD54F)
                              : index == 1
                              ? const Color(0xFFB0BEC5)
                              : index == 2
                              ? const Color(0xFFB87333)
                              : const Color(0xFF546E7A),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('${index + 1}'),
                          ),
                        ),
                        title: Text(
                          placements[index].name,
                          style: TextStyle(color: displayColors.text),
                        ),
                      ),
                  ],
                ),
          colors: displayColors,
        ),
        _completionSection(
          'Ranglistenänderungen',
          _completionRankingChanges(colors: displayColors),
          colors: displayColors,
        ),
        _completionBestPerformancesSection(
          performances,
          colors: displayColors,
        ),
      ];
    } else {
      sections = [
        _completionSection(
          'Mannschaftsvergleich',
          _completionLeagueTeamComparison(league, colors: displayColors),
          colors: displayColors,
        ),
        _completionSection(
          'Spielbilanz',
          _completionLeaguePlayerRecords(
            league,
            leaguePlayerRecords(league),
            colors: displayColors,
          ),
          colors: displayColors,
        ),
        _completionBestPerformancesSection(
          performances,
          colors: displayColors,
        ),
      ];
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Card(
          color: displayColors.card,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sectionHeight = constraints.hasBoundedHeight
                  ? (constraints.maxHeight - 220).clamp(220.0, 520.0).toDouble()
                  : 420.0;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emoji_events_outlined,
                          size: 48,
                          color: displayColors.accent,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Turnier abgeschlossen',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: displayColors.text,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tournament.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: displayColors.accent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$durationLabel · ${tournament.players.length} Teilnehmer · '
                          '${playedMatches.length} Partien gespielt',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: displayColors.text,
                          ),
                        ),
                        Divider(
                          height: 24,
                          color: displayColors.border,
                        ),
                        LayoutBuilder(
                          builder: (context, sectionConstraints) {
                            if (sectionConstraints.maxWidth >= 820) {
                              return SizedBox(
                                height: sectionHeight,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < sections.length;
                                      index++
                                    )
                                      Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            left: index == 0 ? 0 : 8,
                                          ),
                                          child: sections[index],
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final section in sections) ...[
                                  SizedBox(height: 220, child: section),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _completionSection(
    String title,
    Widget content, {
    required TournamentDisplayColors colors,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.text,
              ),
            ),
            Divider(height: 16, color: colors.border),
            Expanded(child: SingleChildScrollView(child: content)),
          ],
        ),
      );

  Widget _completionBestPerformancesSection(
    List<BestPerformance> performances, {
    required TournamentDisplayColors colors,
  }) =>
      _completionSection(
        'Bestleistungen',
        performances.isEmpty
            ? Text(
                'Keine Bestleistungen eingetragen.',
                style: TextStyle(color: colors.mutedText),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final performance in performances.take(8))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${performance.playerName} · ${performance.label}'
                        '${performance.value == null ? '' : ' · ${performance.value}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.text),
                      ),
                    ),
                  if (performances.length > 8)
                    Text(
                      'Weitere ${performances.length - 8} …',
                      style: TextStyle(color: colors.mutedText),
                    ),
                ],
              ),
        colors: colors,
      );

  Widget _completionLeagueTeamComparison(
    LeagueMatch league, {
    required TournamentDisplayColors colors,
  }) {
    final played = league.games.where((game) => game.complete).length;
    final homeScores = league.games.fold<int>(
      0,
      (sum, game) => sum + (game.homeScore(league.gameFormat) ?? 0),
    );
    final awayScores = league.games.fold<int>(
      0,
      (sum, game) => sum + (game.awayScore(league.gameFormat) ?? 0),
    );
    final scoreLabel = league.gameFormat.bestOfSets > 1 ? 'Sets' : 'Legs';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${league.homeTeam} ${league.homePoints}:${league.awayPoints} ${league.awayTeam}',
          style: TextStyle(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$played von ${league.games.length} Begegnungen · ${league.outcome}',
          style: TextStyle(color: colors.mutedText),
        ),
        const SizedBox(height: 8),
        _completionDataTable(
          controller: _completionTeamComparisonScrollController,
          headers: ['Mannschaft', 'Sp', 'S', 'N', scoreLabel, 'Pkt.'],
          rows: [
            [
              league.homeTeam,
              '$played',
              '${league.homePoints}',
              '${league.awayPoints}',
              '$homeScores:$awayScores',
              '${league.homePoints}',
            ],
            [
              league.awayTeam,
              '$played',
              '${league.awayPoints}',
              '${league.homePoints}',
              '$awayScores:$homeScores',
              '${league.awayPoints}',
            ],
          ],
          colors: colors,
        ),
      ],
    );
  }

  Widget _completionLeaguePlayerRecords(
    LeagueMatch league,
    List<LeaguePlayerRecord> records, {
    required TournamentDisplayColors colors,
  }) {
    if (records.isEmpty) {
      return Text(
        'Noch keine Spielbilanzen erfasst.',
        style: TextStyle(color: colors.mutedText),
      );
    }
    return _completionDataTable(
      controller: _completionPlayerRecordScrollController,
      headers: ['Spieler', 'Team', 'Sp', 'S', 'N'],
      rows: [
        for (final record in records)
          [
            record.name,
            record.teamSide == 0 ? league.homeTeam : league.awayTeam,
            '${record.matches}',
            '${record.wins}',
            '${record.losses}',
          ],
      ],
      colors: colors,
    );
  }

  Widget _completionDataTable({
    required ScrollController controller,
    required List<String> headers,
    required List<List<String>> rows,
    required TournamentDisplayColors colors,
  }) =>
      Scrollbar(
        controller: controller,
        thumbVisibility: true,
        notificationPredicate:
            (notification) => notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            border: TableBorder.all(color: colors.border),
            columnSpacing: 12,
            headingTextStyle: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.bold,
            ),
            dataTextStyle: TextStyle(color: colors.text),
            columns: [
              for (final header in headers) DataColumn(label: Text(header)),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [for (final cell in row) DataCell(Text(cell))],
                ),
            ],
          ),
        ),
      );

  Widget _completionRankingChanges({
    required TournamentDisplayColors colors,
  }) =>
      FutureBuilder<List<_RankingStandings>>(
        future: _rankingStandings,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              'Ranglistenänderungen konnten nicht geladen werden.',
              style: TextStyle(color: colors.mutedText),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rankings = snapshot.data!;
          final changes = [
            for (final ranking in rankings)
              for (var index = 0; index < ranking.entries.length; index++)
                (
                  ranking: ranking,
                  entry: ranking.entries[index],
                  position: index + 1,
                  delta: ranking.deltas[ranking.entries[index].id] ?? 0,
                  previous:
                      ranking.previousPositions[ranking.entries[index].id],
                ),
          ].where(
            (change) =>
                change.delta != 0 ||
                (change.previous != null &&
                    change.previous != change.position),
          );
          if (changes.isEmpty) {
            return Text(
              'Keine Ranglistenänderungen erfasst.',
              style: TextStyle(color: colors.mutedText),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final ranking in rankings) ...[
                Text(
                  ranking.rankingName,
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final change in changes.where(
                  (change) => change.ranking == ranking,
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${change.entry.name} · '
                      '${change.delta > 0 ? '+' : ''}${change.delta} Elo'
                      '${change.previous == null || change.previous == change.position ? '' : ' · Platz ${change.previous} → ${change.position}'}',
                      style: TextStyle(
                        color: change.delta > 0
                            ? const Color(0xFF70E0BA)
                            : change.delta < 0
                            ? Colors.redAccent
                            : colors.text,
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      );

  List<TournamentPlayer> _completionPlacements(
    CreatedTournament tournament,
    List<GroupMatch> playedMatches,
  ) {
    List<TournamentPlayer>? stageRanking;
    if (tournament.runStages.isNotEmpty) {
      final finalStage = tournament.runStages.last;
      if (finalStage is GroupTournamentRunStage &&
          finalStage.groups.length == 1) {
        final standings = tournament.importedArchive?.usesNativeLogic == true
            ? ProductionTournamentRuntime(
                tournament,
              ).standings(finalStage.groups.single, finalStage.tieBreakers)
            : const GroupStandingsEngine().calculate(
                finalStage.groups.single,
                finalStage.tieBreakers,
                tournament: tournament,
              );
        stageRanking = standings.map((standing) => standing.player).toList();
      }
      if (finalStage is KnockoutTournamentRunStage) {
        if (finalStage.isKratzer) {
          final players = [...finalStage.participants]
            ..sort((left, right) {
              final lives = finalStage
                  .livesRemainingFor(right)
                  .compareTo(finalStage.livesRemainingFor(left));
              return lives != 0 ? lives : left.name.compareTo(right.name);
            });
          stageRanking = players;
        } else {
          final ranking = ProductionTournamentRuntime(
            tournament,
          ).ranking(finalStage, finalStage.participants);
          stageRanking = PlacementEngine.applyRanking(
            ranking,
            finalStage.placementMatches,
          );
        }
      }
    }

    final stats = {
      for (final player in tournament.players)
        player.name: _CompletionPlayerStats(player),
    };
    for (final match in playedMatches.where((match) => !match.isKratzer)) {
      final home = match.homePlayer;
      final away = match.awayPlayer;
      final homeLegs = match.homeLegs;
      final awayLegs = match.awayLegs;
      if (!match.hasResult ||
          home == null ||
          away == null ||
          homeLegs == null ||
          awayLegs == null) {
        continue;
      }
      final homeStats = stats.putIfAbsent(
        home.name,
        () => _CompletionPlayerStats(home),
      );
      final awayStats = stats.putIfAbsent(
        away.name,
        () => _CompletionPlayerStats(away),
      );
      homeStats
        ..legsFor += homeLegs
        ..legsAgainst += awayLegs;
      awayStats
        ..legsFor += awayLegs
        ..legsAgainst += homeLegs;
      if (match.winner == home) {
        homeStats.wins++;
        awayStats.losses++;
      } else if (match.winner == away) {
        awayStats.wins++;
        homeStats.losses++;
      }
    }
    final ranking = stats.values.toList()
      ..sort((left, right) {
        final wins = right.wins.compareTo(left.wins);
        if (wins != 0) return wins;
        final difference = (right.legsFor - right.legsAgainst).compareTo(
          left.legsFor - left.legsAgainst,
        );
        if (difference != 0) return difference;
        final legs = right.legsFor.compareTo(left.legsFor);
        return legs != 0 ? legs : left.player.name.compareTo(right.player.name);
      });
    final completeRanking = <TournamentPlayer>[];
    void addUnique(TournamentPlayer player) {
      if (!completeRanking.any((entry) => entry.name == player.name)) {
        completeRanking.add(player);
      }
    }

    for (final player in stageRanking ?? const <TournamentPlayer>[]) {
      addUnique(player);
    }
    for (final entry in ranking) {
      addUnique(entry.player);
    }
    return completeRanking;
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
                  context,
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
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildBoardsAndPriorityPanel(
                        context,
                        t,
                        activeIndex,
                        activeStage,
                        expand: true,
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
        _monitorUnitHeight = unitHeight;
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
    if (!_monitorPlacements.any((placement) => placement.widthUnits > 2)) {
      _monitorPlacements = _withIndependentColumns(_monitorPlacements);
    }
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
            height: min(height, 160),
            child: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.85,
                child: Card(
                  child: Center(
                    child: Text(
                      _monitorWidgetTitles[targetWidgetId] ?? targetWidgetId,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
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
    final title = placement.widgetId == 'combined'
        ? _combinedMonitorWidgetTitle(tournament.leagueMatch != null)
        : _monitorWidgetTitles[placement.widgetId];
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
      return ConstrainedBox(
        key: ValueKey('monitor-widget-${placement.widgetId}'),
        constraints: BoxConstraints(maxWidth: width, maxHeight: height),
        child: SingleChildScrollView(
          child: ClipRect(child: widgetContent),
        ),
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
        tooltip: 'Höhe an Inhalt anpassen',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: () => _snapMonitorWidgetHeight(index),
        icon: const Icon(Icons.vertical_align_center),
      ),
      IconButton(
        tooltip: 'Widget entfernen',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: () => _removeMonitorWidget(index),
        icon: const Icon(Icons.close),
      ),
    ];
    final contentKey =
        _monitorCardKeys.putIfAbsent(placement.widgetId, GlobalKey.new);
    return ConstrainedBox(
      key: ValueKey('monitor-widget-${placement.widgetId}'),
      constraints: BoxConstraints(maxWidth: width, maxHeight: height),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                              value: 'height-fit-content',
                              child: Text('Höhe an Inhalt anpassen'),
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
              Flexible(
                child: SingleChildScrollView(
                  child: SizedBox(
                    key: contentKey,
                    child: ClipRect(child: widgetContent),
                  ),
                ),
              ),
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
      case 'height-fit-content':
        _snapMonitorWidgetHeight(index);
      case 'remove':
        _removeMonitorWidget(index);
    }
  }

  /// Rastet die Kachelhöhe auf den tatsächlich gerenderten Inhalt ein, damit
  /// das nächste Widget direkt unter diesem beginnt.
  void _snapMonitorWidgetHeight(int index) {
    final widgetId = _monitorPlacements[index].widgetId;
    final renderObject = _monitorCardKeys[widgetId]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final measuredHeight = renderObject.size.height;
    if (measuredHeight <= 0) return;
    final unitHeight = _monitorUnitHeight > 0 ? _monitorUnitHeight : 220.0;
    final units = (measuredHeight / unitHeight * 2).ceilToDouble() / 2;
    _resizeMonitorWidget(index, heightUnits: units.clamp(0.5, 3.0));
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
          expand: false,
        );
      case 'standings':
        return _buildStandingsPanel(
          context,
          tournament,
          activeStage,
          full: true,
          expand: false,
        );
      case 'combined':
        return _buildStandingsAndForecastWidget(
          context,
          tournament,
          activeIndex,
          activeStage,
        );
      case 'knockoutBracket':
        var stage = activeStage is KnockoutTournamentRunStage
            ? activeStage
            : _nextKnockoutStage(tournament, activeIndex, activeStage);
        if (stage == null || stage.isKratzer) return const SizedBox.shrink();
        if (activeStage is GroupTournamentRunStage) {
          final nextIndex = _nextKnockoutStageIndex(
            tournament,
            activeIndex,
            activeStage,
          );
          if (nextIndex != null && nextIndex < tournament.stages.length) {
            final runtime = ProductionTournamentRuntime(tournament);
            final projectedPlayers = runtime.qualifiers(activeStage);
            final presentedPlayers = const GroupStagePreviewService()
                .presentProjectedPlayers(
                  stage: activeStage,
                  projectedPlayers: projectedPlayers,
                  tournament: tournament,
                );
            final rebuilt = runtime.build(
              tournament.stages[nextIndex],
              presentedPlayers,
            );
            if (rebuilt is KnockoutTournamentRunStage) {
              stage = rebuilt;
            }
          }
        }
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
          expand: false,
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
          child: _buildKratzerLivesPanel(context, tournament, activeStage),
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
    BuildContext context,
    CreatedTournament tournament,
    TournamentRunStage? activeStage,
  ) {
    final colors = _displayColors(context);
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
              style: TextStyle(color: colors.text),
            ),
            trailing: Text(
              '${stage.livesRemainingFor(player)} Leben',
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: Icon(
              stage.livesRemainingFor(player) == 0
                  ? Icons.person_off_outlined
                  : Icons.favorite_outline,
              color: stage.livesRemainingFor(player) == 0
                  ? colors.mutedText
                  : colors.accent,
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
    final colors = _displayColors(context);
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
              style: TextStyle(color: colors.text),
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
      if (!_monitorPlacements.any((placement) => placement.widthUnits > 2)) {
        _monitorPlacements = _withIndependentColumns(_monitorPlacements);
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
    if (!_monitorPlacements.any((placement) => placement.widthUnits > 2)) {
      _monitorPlacements = _withIndependentColumns(_monitorPlacements);
    }
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
    if (!_monitorPlacements.any((placement) => placement.widthUnits > 2)) {
      _monitorPlacements = _withIndependentColumns(_monitorPlacements);
    }
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
    if (!_monitorPlacements.any((placement) => placement.widthUnits > 2)) {
      _monitorPlacements = _withIndependentColumns(_monitorPlacements);
    }
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
    final storedLayout = widget.tournament.secondScreenLayouts[selected];
    if (storedLayout == null) return;
    final layout =
        _isStandardMonitorLayout(selected) &&
            widget.tournament.leagueMatch != null &&
            !storedLayout.any(
              (placement) => placement.widgetId == 'teamComparison',
            )
        ? [
            ...storedLayout,
            const SecondScreenWidgetPlacement(
              widgetId: 'teamComparison',
              widthUnits: 4,
              startsNewRow: true,
            ),
          ]
        : storedLayout;
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
    final colors = _displayColors(context);
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
        Text(
          '$played von $allWithPlayers Partien abgeschlossen',
          style: TextStyle(color: colors.text),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: allWithPlayers == 0 ? 0 : played / allWithPlayers,
          color: const Color(0xFF70E0BA),
          backgroundColor: colors.border,
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < stages.length; index++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              stages[index].name,
              style: TextStyle(color: colors.text),
            ),
            subtitle: Text(
              '${_matchesOf(stages[index]).where((match) => match.hasResult).length} / '
              '${_countMatchesForProgress(stages[index])} Partien',
              style: TextStyle(color: colors.mutedText),
            ),
            trailing: Icon(
              tournament.completedStageIndexes.contains(index)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: tournament.completedStageIndexes.contains(index)
                  ? const Color(0xFF70E0BA)
                  : colors.mutedText,
            ),
          ),
      ],
    );
  }

  Widget _buildHighlightsPanel(
    BuildContext context,
    CreatedTournament tournament,
  ) {
    final colors = _displayColors(context);
    final highlights = [
      for (final match in TournamentTiming.matches(tournament))
        for (final performance in match.bestPerformances)
          (match: match, performance: performance),
    ];
    if (highlights.isEmpty) {
      return Center(
        child: Text(
          'Noch keine Bestleistungen erfasst.',
          style: TextStyle(color: colors.mutedText),
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
            title: Text(
              item.performance.label,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              item.performance.playerName,
              style: TextStyle(color: colors.mutedText),
            ),
          ),
      ],
    );
  }

  Widget _buildRankingPanel(
    BuildContext context,
    CreatedTournament tournament,
  ) {
    final colors = _displayColors(context);
    if (!tournament.countsForRanking || tournament.rankingIds.isEmpty) {
      return Center(
        child: Text(
          'Für dieses Turnier ist keine Rangliste ausgewählt.',
          style: TextStyle(color: colors.mutedText),
        ),
      );
    }
    return FutureBuilder<List<_RankingStandings>>(
      future: _rankingStandings,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Die ELO-Rangliste konnte nicht geladen werden.',
              style: TextStyle(color: colors.mutedText),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final standings = snapshot.data!;
        if (standings.isEmpty ||
            standings.every((ranking) => ranking.entries.isEmpty)) {
          return Center(
            child: Text(
              'Für dieses Turnier ist keine ELO-Rangliste ausgewählt.',
              style: TextStyle(color: colors.mutedText),
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
                title: Text(
                  'Nur Teilnehmer anzeigen',
                  style: TextStyle(color: colors.text),
                ),
                subtitle: Text(
                  'Ausgeschaltet: alle Mitglieder',
                  style: TextStyle(color: colors.mutedText),
                ),
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
                        color: colors.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Divider(height: 12, color: colors.border),
              for (var index = 0; index < ranking.entries.length; index++)
                if (!_showOnlyRankingParticipants ||
                    participantIds.contains(ranking.entries[index].id))
                  _buildRankingEntry(
                    context,
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
    BuildContext context,
    _RankingStandings ranking,
    LocalEloPlayer entry,
    int currentPosition,
  ) {
    final colors = _displayColors(context);
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
            style: TextStyle(color: colors.text),
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
    final isTeamMode = widget.tournament.leagueMatch != null;
    final comparisonLabel = isTeamMode
        ? 'Mannschaftsvergleich'
        : 'Siegprognose & Weiterkommen';
    if (width < 560) {
      return DropdownButton<_StandingsDisplayMode>(
        value: _standingsDisplayMode,
        isExpanded: true,
        items: [
          const DropdownMenuItem(
            value: _StandingsDisplayMode.standings,
            child: Text('Tabellen & Zwischenstände'),
          ),
          DropdownMenuItem(
            value: _StandingsDisplayMode.forecast,
            child: Text(comparisonLabel),
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
      segments: [
        const ButtonSegment(
          value: _StandingsDisplayMode.standings,
          label: Text('Tabellen & Zwischenstände'),
          icon: Icon(Icons.table_chart_outlined),
        ),
        ButtonSegment(
          value: _StandingsDisplayMode.forecast,
          label: Text(comparisonLabel),
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
        final league = tournament.leagueMatch;
        if (league != null) {
          return LeagueOverview(league: league);
        }
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              _buildStandingsDisplaySelector(context, constraints.maxWidth),
        ),
        const Divider(height: 8),
        SingleChildScrollView(
          child: _buildStandingsDisplayPanel(
            context,
            tournament,
            activeIndex,
            stage,
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
            context,
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
    BuildContext context,
    CreatedTournament t,
    KnockoutTournamentRunStage stage,
    int? stageIndex, {
    bool isActiveStage = false,
  }) {
    final colors = _displayColors(context);
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

    String playerLabel(
      TournamentPlayer? player,
      int roundIndex,
      int matchIndex, {
      required bool home,
    }) {
      if (isActiveStage) {
        if (player != null && !player.name.contains('(noch offen)')) {
          return player.shortDisplayName;
        }
        if (roundIndex == 0) return 'Offen';
        final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
        return matchDisplayLabel(
          'Gewinner Spiel $sourceMatchNumber',
          fallback: '',
        );
      }
      if (roundIndex == 0) {
        if (player != null && !player.name.contains('(noch offen)')) {
          return player.name;
        }
        return 'Teilnehmer offen';
      }
      final sourceMatchNumber = matchIndex * 2 + (home ? 1 : 2);
      if (player == null || player.name.contains('(noch offen)')) {
        return matchDisplayLabel(
          'Gewinner Spiel $sourceMatchNumber',
          fallback: '',
        );
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
                style: TextStyle(
                  color: colors.text,
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
                        rounds.first.length * 125 * scale + roundHeaderHeight;
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
                                                          context,
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
    BuildContext context,
    GroupMatch match, {
    required int roundIndex,
    required int matchIndex,
    required String homeLabel,
    required String awayLabel,
    required int matchNumber,
  }) {
    final colors = _displayColors(context);
    final homeIsCertain =
        homeLabel.contains('vorläufig') || homeLabel.contains('gesetzt');
    final awayIsCertain =
        awayLabel.contains('vorläufig') || awayLabel.contains('gesetzt');
    return Container(
      key: ValueKey('knockout-preview-match-$roundIndex-$matchIndex'),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            matchDisplayLabel(match.label, fallback: 'Begegnung $matchNumber'),
            style: TextStyle(color: colors.mutedText, fontSize: 11),
          ),
          const SizedBox(height: 3),
          _buildBracketParticipant(context, homeLabel, isCertain: homeIsCertain),
          Divider(color: colors.border, height: 8),
          _buildBracketParticipant(context, awayLabel, isCertain: awayIsCertain),
        ],
      ),
    );
  }

  Widget _buildBracketParticipant(
    BuildContext context,
    String label, {
    required bool isCertain,
  }) {
    final colors = _displayColors(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isCertain
                  ? (isLight
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF86EFAC))
                  : colors.text,
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
              Flexible(
                child: Text(
                  'Tabellen & Zwischenstände',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _displayColors(context).text,
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

    final colors = _displayColors(context);
    return Card(
      color: colors.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'K.-o.-Runde: ${stage.name}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Aktuelle Begegnungen und Paarungen siehe Spielansetzungen.',
              style: TextStyle(color: colors.mutedText),
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
    final colors = _displayColors(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
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
      key: ValueKey('second-screen-standings-group-$groupNumber'),
      constraints: BoxConstraints(
        minWidth: full ? 280 : 220,
        maxWidth: full ? double.infinity : 340,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isLight
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFF70E0BA),
                ),
              ),
              Text(
                '$playedMatches/$totalMatches',
                style: TextStyle(
                  fontSize: 11,
                  color: isLight
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFF70E0BA),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Top $fixedPlaces weiter',
                style: TextStyle(fontSize: 11, color: colors.mutedText),
              ),
            ],
          ),
          Divider(color: colors.border, height: 12),
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
    final colors = _displayColors(context);
    final prognosisContent = hasPrognosis
        ? _buildContenderPrognosisList(context, currentStage)
        : (koStage != null
              ? _buildKnockoutRoundsPreview(context, koStage)
              : Center(
                  child: Text(
                    'Keine K.-o.-Phase im aktuellen Turnier geplant.',
                    style: TextStyle(color: colors.mutedText),
                  ),
                ));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // The group tables already use the translucent display card color.
        // Keeping this container transparent avoids stacking two semi
        // transparent layers and hiding the Christmas background.
        color: hasPrognosis ? Colors.transparent : colors.card,
        border: hasPrognosis ? null : Border.all(color: colors.border),
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
                  t.leagueMatch != null
                      ? 'Mannschaftsvergleich'
                      : hasPrognosis
                      ? 'Siegprognose & Weiterkommen'
                      : 'Turnierbaum Vorschau',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.leagueMatch != null
                ? 'Direkter Vergleich der Mannschaften und aktuelle Zwischenstände:'
                : hasPrognosis
                ? 'Sieg- und Weiterkommen-Wahrscheinlichkeiten basierend auf aktuellen Tabellenständen:'
                : 'Turnierbaum der finalen Phase:',
            style: TextStyle(fontSize: 12, color: colors.mutedText),
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        final forecast = snapshot.data!;
        final plan = groupStage.qualificationPlan;
        final cards = [
          for (var groupIndex = 0; groupIndex < groupStage.groups.length; groupIndex++)
            _buildGroupForecastCard(
              context,
              groupStage.groups[groupIndex],
              groupNumber: groupIndex + 1,
              forecast: forecast,
              fixedPlaces: plan == null
                  ? 0
                  : groupIndex < plan.fixedByGroup.length
                  ? plan.fixedByGroup[groupIndex]
                  : plan.fixedPerGroup,
              tieBreakers: groupStage.tieBreakers,
            ),
        ];
        // Same two-column behavior as the standings view: on wide monitors the
        // groups sit side by side, on narrow screens they stack vertically.
        return LayoutBuilder(
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
        );
      },
    );
  }

  Widget _buildGroupForecastCard(
    BuildContext context,
    TournamentGroup group, {
    required int groupNumber,
    required Map<String, AdvancementChance> forecast,
    required int fixedPlaces,
    required List<String> tieBreakers,
  }) {
    final colors = _displayColors(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final certainColor =
        isLight ? const Color(0xFF2E7D32) : const Color(0xFF86EFAC);
    final standings = _calculateGroupStandings(group, tieBreakers);

    Widget headerCell(String label, {TextAlign align = TextAlign.start}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          textAlign: align,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: colors.mutedText,
          ),
        ),
      );
    }

    String percentText(double value) {
      final formatted = value.toStringAsFixed(1);
      return formatted.endsWith('.0')
          ? '${formatted.substring(0, formatted.length - 2)}%'
          : '$formatted%';
    }

    return Container(
      key: ValueKey('second-screen-forecast-group-$groupNumber'),
      constraints: const BoxConstraints(minWidth: 300),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // Translucent in the Christmas theme so the background stays visible.
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                group.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                  fontSize: 15,
                ),
              ),
              if (fixedPlaces > 0)
                Text(
                  'Top $fixedPlaces weiter',
                  style: TextStyle(fontSize: 12, color: colors.mutedText),
                ),
            ],
          ),
          Divider(color: colors.border, height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 260),
              child: Table(
                columnWidths: const {
                  1: FixedColumnWidth(64),
                  2: FixedColumnWidth(64),
                },
                children: [
                  TableRow(
                    children: [
                      headerCell('Teilnehmer'),
                      headerCell('% Sieg', align: TextAlign.end),
                      headerCell('% Weiter', align: TextAlign.end),
                    ],
                  ),
                  for (var rank = 0; rank < standings.length; rank++)
                    TableRow(
                      children: [
                        ...() {
                          final standing = standings[rank];
                          final chance = forecast[standing.player.profileId ??
                                  standing.player.name] ??
                              const AdvancementChance(
                                groupWinProbability: 0,
                                advancementProbability: 0,
                                tournamentWinProbability: 0,
                              );
                          final isCertain = const QualificationCertainty()
                              .isCertain(
                            standing: standing,
                            place: rank + 1,
                            fixedPlaces: fixedPlaces,
                            standings: standings,
                            matches: group.matches,
                            tieBreakers: tieBreakers,
                          );
                          final valueColor = isCertain
                              ? certainColor
                              : colors.mutedText;
                          final tooltip =
                              'Turniersieg: ${chance.tournamentWinProbability.toStringAsFixed(1)} %\n'
                              'Weiterkommen: ${chance.advancementProbability.toStringAsFixed(1)} %';
                          return [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              child: Text(
                                standing.player.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isCertain
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: colors.text,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Tooltip(
                                message: tooltip,
                                child: Text(
                                  percentText(chance.tournamentWinProbability),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: valueColor,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Tooltip(
                                message: tooltip,
                                child: Text(
                                  percentText(chance.advancementProbability),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: valueColor,
                                  ),
                                ),
                              ),
                            ),
                          ];
                        }(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKnockoutRoundsPreview(
    BuildContext context,
    KnockoutTournamentRunStage koStage,
  ) {
    final colors = _displayColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < koStage.rounds.length; i++) ...[
          Text(
            knockoutRoundName(i, koStage.rounds.length),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: 4),
          for (final m in koStage.rounds[i])
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.cardEmphasis,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${m.homePlayer?.name ?? "Offen"} vs. ${m.awayPlayer?.name ?? "Offen"}',
                      style: TextStyle(color: colors.text, fontSize: 13),
                    ),
                  ),
                  if (m.hasResult)
                    Text(
                      '${m.homeScore} : ${m.awayScore}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
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
    final colors = _displayColors(context);
    final runningMatches = const OrderOfPlayController()
        .plan(t, activeIndex)
        .running;
    final flowPriority = TournamentFlowPriority.forStage(
      stage,
      settings: _prioritySettings,
    );
    final orderedEntries = const OrderOfPlayController().orderedEntriesForStage(
      t,
      activeIndex,
      prioritizedMatches: flowPriority.prioritizedMatches,
      deprioritizedMatches: flowPriority.deprioritizedMatches,
    );
    final recommendedGroups = stage is GroupTournamentRunStage
        ? [
            for (final group in stage.groups)
              RecommendedMatchGroup(
                name: group.name,
                matches: [
                  for (final entry in orderedEntries)
                    if (entry.groupKey ==
                        tournamentGroupBoardKey(activeIndex, group.name))
                      entry.match,
                ],
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
                matches: [for (final entry in orderedEntries) entry.match],
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
                      color: colors.cardEmphasis,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Tooltip(
                          message:
                              'Prioritätshinweis: Diese Gruppe oder Teilnehmer '
                              'liegen im Spielplan zurück.',
                          child: Icon(
                            Icons.priority_high,
                            size: 18,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            notice,
                            style: TextStyle(
                              color: colors.text,
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
                          prioritizeForDisplay: false,
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

    final scrollLargeTextPanel =
        expand && MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tournament.directorModeEnabled ||
            runningMatches.isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.play_circle_fill,
                size: 22,
                color: colors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.tournament.directorModeEnabled
                      ? 'Board Belegung & aktive Partien'
                      : 'Aktuelle Partien (${runningMatches.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: colors.text,
                  ),
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
                  final columns = constraints.maxWidth >= 460 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  final snapshot = TournamentDirectorSnapshot(
                    widget.tournament,
                    activeIndex,
                  );
                  final busyPlayers = {
                    for (final entry in snapshot.schedule.running)
                      ...entry.players,
                  };
                  final hasAvailableMatches = snapshot.ready.any(
                    (entry) => !entry.players.any(busyPlayers.contains),
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
                            if (running != null) {
                              return _buildRunningMatchTile(
                                context,
                                running,
                                width: width,
                                playerInsights:
                                    insightSnapshot.data ?? const {},
                              );
                            }
                            if (widget.tournament.blockedBoards.contains(
                                  board,
                                ) ||
                                !hasAvailableMatches) {
                              return _buildBlockedBoardOccupancyTile(
                                context,
                                board: board,
                                width: width,
                              );
                            }
                            return _buildFreeBoardOccupancyTile(
                              context,
                              board: board,
                              width: width,
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 8),
        if (scrollLargeTextPanel)
          recommendedContent
        else if (expand)
          Expanded(child: recommendedContent)
        else
          recommendedContent,
        if (!hasOpenMatches && expand)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Keine offenen Partien in dieser Phase.',
              style: TextStyle(color: colors.mutedText),
            ),
          ),
      ],
    );
    return scrollLargeTextPanel ? SingleChildScrollView(child: panel) : panel;
  }

  Widget _buildRunningMatchTile(
    BuildContext context,
    PlayEntry entry, {
    required double width,
    Map<String, List<PlayerInsight>> playerInsights = const {},
  }) {
    final match = entry.match;
    final colors = _displayColors(context);
    final nameStyle = TextStyle(
      color: colors.text,
      fontWeight: FontWeight.bold,
      fontSize: 14,
      height: 1.2,
    );
    final separatorStyle = TextStyle(
      color: colors.mutedText,
      fontWeight: FontWeight.bold,
      fontSize: 14,
      height: 1.2,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    TextPainter measure(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final homeName = match.homePlayer?.shortDisplayName ?? 'Offen';
    final awayName = match.awayPlayer?.shortDisplayName ?? 'Offen';
    final boardName = widget.tournament
        .boardDisplayName(match.boardNumber ?? 1)
        .toUpperCase();
    return Container(
      width: width,
      key: ValueKey(
        'second-screen-running-match-${match.round}-'
        '${match.homePlayer?.profileId ?? match.homePlayer?.name}-'
        '${match.awayPlayer?.profileId ?? match.awayPlayer?.name}',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.accent, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  boardName,
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const _PulsingLiveBadge(),
            ],
          ),
          const SizedBox(height: 2),
          LayoutBuilder(
              builder: (context, constraints) {
                final namesFitSideBySide =
                    measure(homeName, nameStyle).width +
                        measure(awayName, nameStyle).width +
                        measure('–', separatorStyle).width +
                        20 <=
                    constraints.maxWidth;
                if (!namesFitSideBySide) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _runningPlayerName(
                        match.homePlayer,
                        match.awayPlayer,
                        playerInsights,
                        textAlign: TextAlign.center,
                        style: nameStyle,
                      ),
                      const SizedBox(height: 2),
                      _runningPlayerName(
                        match.awayPlayer,
                        match.homePlayer,
                        playerInsights,
                        textAlign: TextAlign.center,
                        style: nameStyle,
                      ),
                    ],
                  );
                }
                return Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: _runningPlayerName(
                          match.homePlayer,
                          match.awayPlayer,
                          playerInsights,
                          textAlign: TextAlign.end,
                          style: nameStyle,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('–', style: separatorStyle),
                      ),
                      Flexible(
                        child: _runningPlayerName(
                          match.awayPlayer,
                          match.homePlayer,
                          playerInsights,
                          textAlign: TextAlign.start,
                          style: nameStyle,
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
  }

  Widget _runningPlayerName(
    TournamentPlayer? player,
    TournamentPlayer? opponent,
    Map<String, List<PlayerInsight>> playerInsights, {
    required TextAlign textAlign,
    required TextStyle style,
  }) {
    if (player == null) {
      return Text('Offen', style: style);
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
      style: style,
      maxLines: 1,
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
    required double width,
  }) {
    final colors = _displayColors(context);
    return Container(
      width: width,
      key: ValueKey('second-screen-free-board-$board'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: const Color(0xFF4ED9A4), width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.tournament.boardDisplayName(board).toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF4ED9A4),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            const _BoardStatusBadge(label: 'FREI', color: Color(0xFF4ED9A4)),
          ],
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            'Aktuell keine Partie',
            style: TextStyle(
              color: colors.text,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

  Widget _buildBlockedBoardOccupancyTile(
    BuildContext context, {
    required int board,
    required double width,
  }) {
    final colors = _displayColors(context);
    return Container(
      width: width,
      key: ValueKey('second-screen-blocked-board-$board'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: Colors.redAccent, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.tournament.boardDisplayName(board).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const _BoardStatusBadge(
                label: 'GESPERRT',
                color: Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Center(
            child: Text(
              'Keine Partie möglich',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorBoardQueue(
    BuildContext context,
    CreatedTournament tournament,
    int activeIndex, {
    Map<String, List<PlayerInsight>> playerInsights = const {},
    Object? playerInsightsError,
  }) {
    final colors = _displayColors(context);
    final snapshot = TournamentDirectorSnapshot(tournament, activeIndex);
    final mergedGroupBoards = snapshot.mergedGroupBoards();
    final boardToMergedGroup = <int, String>{
      for (final entry in mergedGroupBoards.entries)
        for (final board in entry.value) board: entry.key,
    };
    final boardTiles = <MapEntry<List<int>, String?>>[
      for (var board = 1; board <= tournament.boardCount; board++)
        if (boardToMergedGroup[board] == null) MapEntry([board], null),
      for (final entry in mergedGroupBoards.entries)
        MapEntry(entry.value, entry.key),
    ]..sort((a, b) => a.key.first.compareTo(b.key.first));
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        return SingleChildScrollView(
          key: const ValueKey('second-screen-director-queue-scroll'),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: () {
                  final rows = <List<MapEntry<List<int>, String?>>>[];
                  var currentRow = <MapEntry<List<int>, String?>>[];
                  var currentSpan = 0;
                  const maxRowSpan = 2;
                  for (final tile in boardTiles) {
                    final span = tile.key.length > 1 ? 2 : 1;
                    if (currentRow.isNotEmpty &&
                        currentSpan + span > maxRowSpan) {
                      rows.add(currentRow);
                      currentRow = <MapEntry<List<int>, String?>>[];
                      currentSpan = 0;
                    }
                    currentRow.add(tile);
                    currentSpan += span;
                  }
                  if (currentRow.isNotEmpty) {
                    rows.add(currentRow);
                  }
                  return [
                    for (final rowTiles in rows)
                      Builder(
                        builder: (context) {
                          final totalSpan = rowTiles.fold<int>(
                            0,
                            (sum, tile) => sum + (tile.key.length > 1 ? 2 : 1),
                          );
                          final singleColumnWidth =
                              (constraints.maxWidth -
                                  spacing * (totalSpan - 1)) /
                              totalSpan;
                          final rowChildren = <Widget>[];
                          for (
                            var index = 0;
                            index < rowTiles.length;
                            index++
                          ) {
                            if (index > 0) {
                              rowChildren.add(SizedBox(width: spacing));
                            }
                            rowChildren.add(
                              Builder(
                                builder: (context) {
                                  final boardTile = rowTiles[index];
                                  final boards = boardTile.key;
                                  final mergedGroupKey = boardTile.value;
                                  final board = boards.first;
                                  final boardNames = boards
                                      .map(tournament.boardDisplayName)
                                      .toList();
                                  final displayName = boards.length == 1
                                      ? boardNames.first
                                      : boardNames.every(
                                          (name) => name.startsWith('Board '),
                                        )
                                      ? '${boardNames.first} & ${boardNames.skip(1).map((name) => name.substring('Board '.length)).join(' & ')}'
                                      : boardNames.join(' & ');
                                  final recommendations = mergedGroupKey == null
                                      ? snapshot.suggestionsForBoard(board)
                                      : snapshot.upcomingForBoards(
                                          boards,
                                          groupKey: mergedGroupKey,
                                          limit: boards.length * 3,
                                        );
                                  final upcoming = recommendations
                                      .where(
                                        (assignment) =>
                                            !snapshot.schedule.running.any(
                                              (active) => identical(
                                                active.match,
                                                assignment.entry.match,
                                              ),
                                            ),
                                      )
                                      .take(
                                        mergedGroupKey == null
                                            ? 3
                                            : boards.length * 3,
                                      )
                                      .toList();
                                  final assignedGroupLabels =
                                      tournament.directorSchedulingStrategy ==
                                              'group'
                                          ? upcoming
                                              .map(
                                                (assignment) =>
                                                    assignment.entry.groupKey,
                                              )
                                              .whereType<String>()
                                              .toSet()
                                              .map((key) {
                                                final prefix = '$activeIndex:';
                                                return key.startsWith(prefix)
                                                    ? key.substring(
                                                      prefix.length,
                                                    )
                                                    : key;
                                              })
                                              .where((name) => name.isNotEmpty)
                                              .toList()
                                          : const <String>[];
                                  final statuses = [
                                    for (final boardNumber in boards)
                                      (
                                        label:
                                            snapshot.runningOn(boardNumber) !=
                                                null
                                            ? 'Besetzt'
                                            : tournament.blockedBoards.contains(
                                                    boardNumber,
                                                  ) ||
                                                  snapshot
                                                      .selectableForBoard(
                                                        boardNumber,
                                                      )
                                                      .isEmpty
                                            ? 'Board gesperrt'
                                            : 'Frei',
                                        color:
                                            snapshot.runningOn(boardNumber) !=
                                                null
                                            ? colors.accent
                                            : tournament.blockedBoards.contains(
                                                    boardNumber,
                                                  ) ||
                                                  snapshot
                                                      .selectableForBoard(
                                                        boardNumber,
                                                      )
                                                      .isEmpty
                                            ? Colors.redAccent
                                            : const Color(0xFF4ED9A4),
                                      ),
                                  ];
                                  final allBlocked = statuses.every(
                                    (status) =>
                                        status.label == 'Board gesperrt',
                                  );
                                  final anyRunning = statuses.any(
                                    (status) => status.label == 'Besetzt',
                                  );
                                  final span = boards.length > 1 ? 2 : 1;
                                  final tileWidth =
                                      singleColumnWidth * span +
                                      spacing * (span - 1);
                                  return SizedBox(
                                    width: tileWidth,
                                    child: Container(
                                      key: ValueKey(
                                        boards.length == 1
                                            ? 'second-screen-director-board-$board'
                                            : 'second-screen-director-boards-${boards.join('-')}',
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.card,
                                        border: Border.all(
                                          color: anyRunning
                                              ? TournamentDisplayPalette.accent
                                              : allBlocked
                                              ? Colors.redAccent
                                              : const Color(0xFF4ED9A4),
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: displayName
                                                      .toUpperCase(),
                                                  style: TextStyle(
                                                    color: colors.text,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text:
                                                      ' | Empfohlene Partien',
                                                  style: TextStyle(
                                                    color: colors.mutedText,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (assignedGroupLabels
                                                    .isNotEmpty)
                                                  TextSpan(
                                                    text:
                                                        ' · ${assignedGroupLabels.join(' & ')}',
                                                    style: TextStyle(
                                                      color: colors.accent,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              for (
                                                var boardIndex = 0;
                                                boardIndex < boards.length;
                                                boardIndex++
                                              )
                                                Expanded(
                                                  child: Padding(
                                                    padding: EdgeInsets.only(
                                                      left: boardIndex == 0
                                                          ? 0
                                                          : 8,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        for (
                                                          var index =
                                                              boardIndex * 3;
                                                          index <
                                                              min(
                                                                upcoming.length,
                                                                (boardIndex +
                                                                        1) *
                                                                    3,
                                                              );
                                                          index++
                                                        )
                                                          Padding(
                                                            key: ValueKey(
                                                              'second-screen-director-recommendation-'
                                                              '${boards.join('-')}-$index',
                                                            ),
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  top: 4,
                                                                ),
                                                            child: Row(
                                                              children: [
                                                                SizedBox(
                                                                  width: 20,
                                                                  child: Text(
                                                                    '${index + 1}.',
                                                                    style: TextStyle(
                                                                      color: colors.accent,
                                                                    ),
                                                                  ),
                                                                ),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        upcoming[index]
                                                                            .entry
                                                                            .match
                                                                            .participantShortLabel,
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: TextStyle(
                                                                          color: colors.text,
                                                                          fontSize:
                                                                              12,
                                                                        ),
                                                                      ),
                                                                      if (playerInsights
                                                                          .isNotEmpty)
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
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          }
                          return Padding(
                            padding: EdgeInsets.only(bottom: spacing),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: rowChildren,
                            ),
                          );
                        },
                      ),
                  ];
                }(),
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
    final colors = _displayColors(context);
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
            Icon(Icons.history, size: 20, color: colors.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t.leagueMatch == null
                    ? 'Zuletzt beendete Matches'
                    : 'Aktuelles',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: colors.text,
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
                        ? Center(
                            child: Text(
                              'Ranglistenänderungen konnten nicht geladen werden.',
                              style: TextStyle(color: Colors.amber),
                            ),
                          )
                        : recent.isEmpty
                        ? Center(
                            child: Text(
                              'Noch keine beendeten Partien vorhanden.',
                              style: TextStyle(color: colors.mutedText),
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
                                  Divider(
                                    height: 1,
                                    color: colors.border,
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
                          leading: Icon(
                            Icons.swap_horiz,
                            color: colors.accent,
                          ),
                          title: Text(
                            entry.message,
                            style: TextStyle(color: colors.text),
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
    final colors = TournamentDisplayPalette.forColorScheme(
      Theme.of(context).colorScheme,
    );
    final timing = TournamentTiming.snapshot(widget.tournament, DateTime.now());
    final elapsed = timing.elapsed;
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60);
    final seconds = elapsed.inSeconds.remainder(60);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Icon(Icons.timer, size: 20, color: colors.accent),
        Text(
          hours > 0
              ? 'Turnieruhr: $hours Std. $minutes Min. ${seconds}s'
              : 'Turnieruhr: $minutes Min. ${seconds}s',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.text,
          ),
        ),
        if (timing.forecast != null)
          Text(
            'Ende ca. ${_formatMonitorClockTime(timing.forecast!)}',
            style: TextStyle(color: colors.text),
          ),
      ],
    );
  }
}

class _BoardStatusBadge extends StatelessWidget {
  const _BoardStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(28),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class _PulsingLiveBadge extends StatefulWidget {
  const _PulsingLiveBadge();

  @override
  State<_PulsingLiveBadge> createState() => _PulsingLiveBadgeState();
}

class _PulsingLiveBadgeState extends State<_PulsingLiveBadge> {
  static final ValueNotifier<bool> _bright = ValueNotifier(true);
  static Timer? _timer;
  static int _activeBadges = 0;

  @override
  void initState() {
    super.initState();
    _activeBadges++;
    _timer ??= Timer.periodic(const Duration(milliseconds: 800), (_) {
      _bright.value = !_bright.value;
    });
  }

  @override
  void dispose() {
    _activeBadges--;
    if (_activeBadges == 0) {
      _timer?.cancel();
      _timer = null;
      _bright.value = true;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _bright,
    builder: (context, bright, _) => AnimatedOpacity(
      opacity: bright ? 1 : 0.45,
      duration: const Duration(milliseconds: 300),
      child: const _BoardStatusBadge(label: 'LIVE', color: Colors.redAccent),
    ),
  );
}

String _formatMonitorClockTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
