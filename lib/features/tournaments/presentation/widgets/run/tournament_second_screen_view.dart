import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/engines/qualification_certainty.dart';
import '../../../application/tournament_timing.dart';
import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../application/group_advancement_forecast_service.dart';
import '../../../domain/engines/group_advancement_forecast_engine.dart';
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
  late Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges;
  late String _eloInputFingerprint;
  Future<Map<String, AdvancementChance>>? _advancementForecast;
  late String _forecastFingerprint;

  @override
  void initState() {
    super.initState();
    _showNextStagePreview = widget.showNextStagePreviewInitially;
    _refreshEloChanges();
    _refreshAdvancementForecast();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h Std. $m Min. ${s}s';
    return '$m Min. ${s}s';
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
    final totalMatches = allMatches.where((m) => m.hasPlayers).length;
    final pct = totalMatches > 0
        ? ((playedMatches.length / totalMatches) * 100).round()
        : 0;

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
                    '${t.name} · ${activeStage?.name ?? "Turnier"}',
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
                    progressPercent: pct,
                    playedMatches: playedMatches,
                    totalMatches: totalMatches,
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
    required int progressPercent,
    required List<GroupMatch> playedMatches,
    required int totalMatches,
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
                  timing: timing,
                  progressPercent: progressPercent,
                  playedMatches: playedMatches,
                  totalMatches: totalMatches,
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
                      timing: timing,
                      progressPercent: progressPercent,
                      playedMatches: playedMatches,
                      totalMatches: totalMatches,
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
    bool expand = true,
  }) {
    final hasNextKnockout = _nextKnockoutStage(t, activeIndex, stage) != null;
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
            flex: _showInlineNextStagePreview ? 2 : 1,
            child: SingleChildScrollView(child: panel),
          )
        else
          panel,
        if (hasNextKnockout) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => setState(
              () => _showInlineNextStagePreview = !_showInlineNextStagePreview,
            ),
            icon: Icon(
              _showInlineNextStagePreview
                  ? Icons.expand_less
                  : Icons.account_tree_outlined,
            ),
            label: Text(
              _showInlineNextStagePreview
                  ? 'Vorschau ausblenden'
                  : 'Vorschau für die nächste Etappe',
            ),
          ),
        ],
        if (_showInlineNextStagePreview && hasNextKnockout)
          if (expand)
            Expanded(
              flex: 3,
              child: _buildInlineNextStagePreview(
                context,
                t,
                activeIndex,
                stage,
              ),
            )
          else
            SizedBox(
              height: 620,
              child: _buildInlineNextStagePreview(
                context,
                t,
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
    final stage = _nextKnockoutStage(t, activeIndex, activeStage);
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
            onPressed: () => setState(() => _showNextStagePreview = false),
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
          onPressed: () => setState(() => _showNextStagePreview = false),
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
    final certainQualifiers = groupStage == null
        ? const <int, TournamentPlayer>{}
        : _certainQualifierByInputIndex(groupStage);
    final config = stageIndex != null && stageIndex < t.stages.length
        ? t.stages[stageIndex]
        : null;
    final canShowSeedPositions =
        config == null ||
        !config.knockoutDrawOnStart ||
        config.knockoutSlotOrder.isNotEmpty;

    String playerLabel(TournamentPlayer? player, int roundIndex) {
      if (roundIndex > 0) {
        return player?.name ?? 'Sieger der vorherigen Runde';
      }
      if (player != null && canShowSeedPositions) {
        final playerIndex = t.players.indexWhere(
          (candidate) =>
              candidate == player ||
              (candidate.profileId != null &&
                  candidate.profileId == player.profileId),
        );
        final guaranteed = playerIndex < 0
            ? null
            : certainQualifiers[playerIndex];
        if (guaranteed != null) {
          return '${guaranteed.name} · vorläufig weiter';
        }
      }
      return 'Qualifikant offen';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${stage.name} · Turnierbaum-Vorschau',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        if (certainQualifiers.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Setzplätze bleiben bis zum Abschluss der Etappe vorläufig.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        if (certainQualifiers.isNotEmpty && !canShowSeedPositions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Sicher weiter: ${certainQualifiers.values.map((player) => player.name).join(', ')}',
              style: const TextStyle(
                color: Color(0xFF86EFAC),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: stage.rounds.isEmpty
              ? const Center(
                  child: Text(
                    'Für diese Etappe ist noch kein Turnierbaum vorhanden.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final rounds = stage.rounds;
                    const roundWidth = 280.0;
                    const roundGap = 28.0;
                    const roundHeaderHeight = 42.0;
                    final boardWidth =
                        rounds.length * roundWidth +
                        (rounds.length - 1) * roundGap;
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final minimumBoardHeight =
                        rounds.first.length * 72 * scale + roundHeaderHeight;
                    final boardHeight = max(
                      constraints.maxHeight,
                      minimumBoardHeight,
                    );

                    return SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
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
                                                    ),
                                                    awayLabel: playerLabel(
                                                      rounds[roundIndex][matchIndex]
                                                          .awayPlayer,
                                                      roundIndex,
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

  Map<int, TournamentPlayer> _certainQualifierByInputIndex(
    GroupTournamentRunStage stage,
  ) {
    final plan = stage.qualificationPlan;
    if (plan == null) return const {};

    final certainPlayers = <int, TournamentPlayer>{};
    var inputIndex = 0;
    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final group = stage.groups[groupIndex];
      final standings = _calculateGroupStandings(group, stage.tieBreakers);
      final fixedPlaces = groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      if (group.playType == 'swiss' ||
          group.matches.any((match) => match.isDecider)) {
        inputIndex += fixedPlaces;
        continue;
      }
      final unsupportedTieBreaker = stage.tieBreakers.indexWhere(
        (rule) => !const {'points', 'legDifference', 'legsFor'}.contains(rule),
      );
      for (var rank = 0; rank < min(fixedPlaces, standings.length); rank++) {
        final standing = standings[rank];
        if (unsupportedTieBreaker >= 0 &&
            standings.any(
              (other) =>
                  other.player != standing.player &&
                  _tiesOnTieBreakerPrefix(
                    standing,
                    other,
                    stage.tieBreakers.take(unsupportedTieBreaker),
                  ),
            )) {
          continue;
        }
        if (const QualificationCertainty().isCertain(
          standing: standing,
          place: rank + 1,
          fixedPlaces: fixedPlaces,
          standings: standings,
          matches: group.matches,
          tieBreakers: stage.tieBreakers,
        )) {
          certainPlayers[inputIndex + rank] = standing.player;
        }
      }
      inputIndex += fixedPlaces;
    }
    return certainPlayers;
  }

  bool _tiesOnTieBreakerPrefix(
    PlayerStanding first,
    PlayerStanding second,
    Iterable<String> tieBreakers,
  ) {
    for (final rule in tieBreakers) {
      final comparison = switch (rule) {
        'points' => first.points.compareTo(second.points),
        'legDifference' => first.legDifference.compareTo(second.legDifference),
        'legsFor' => first.legsFor.compareTo(second.legsFor),
        _ => 0,
      };
      if (comparison != 0) return false;
    }
    return true;
  }

  Widget _buildBracketMatchPreview(
    GroupMatch match, {
    required String homeLabel,
    required String awayLabel,
    required int matchNumber,
  }) {
    final homeIsCertain = homeLabel.contains('vorläufig weiter');
    final awayIsCertain = awayLabel.contains('vorläufig weiter');
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
      final wrapContent = Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < stage.groups.length; i++)
            _buildGroupStandingsCard(
              context,
              stage.groups[i],
              groupNumber: i + 1,
              qualificationPlan: stage.qualificationPlan,
              tieBreakers: stage.tieBreakers,
              full: full,
            ),
        ],
      );

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
    final fixedPlaces = qualificationPlan?.fixedPerGroup ?? 2;

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
                'Top $fixedPlaces weiter',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
          const Divider(color: Color(0xFF263D52), height: 12),
          for (var r = 0; r < standings.length; r++)
            Builder(
              builder: (context) {
                final standing = standings[r];
                final place = r + 1;
                final isQualified = place <= fixedPlaces;
                final isCertain = const QualificationCertainty().isCertain(
                  standing: standing,
                  place: place,
                  fixedPlaces: fixedPlaces,
                  standings: standings,
                  matches: group.matches,
                  tieBreakers: tieBreakers,
                );

                return Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 6,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  decoration: BoxDecoration(
                    color: isCertain
                        ? const Color(0xFF144D34)
                        : isQualified
                        ? const Color(0xFF163828)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$place.',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isQualified
                              ? const Color(0xFF86EFAC)
                              : Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          standing.player.name,
                          style: TextStyle(
                            fontWeight: isQualified
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${standing.legsFor}:${standing.legsAgainst}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${standing.points} P',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF70E0BA),
                          fontSize: 13,
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
    final matches = _matchesOf(
      stage,
    ).where((m) => m.hasPlayers && !m.isResolved).toList();

    final schedule = const OrderOfPlayController().plan(t, activeIndex);
    final openCounts = <String, int>{};
    for (final assignment in schedule.planned) {
      for (final player in assignment.entry.players) {
        openCounts[player] = (openCounts[player] ?? 0) + 1;
      }
    }

    final namesById = <String, String>{
      for (final player in t.players) ...{
        if (player.profileId != null) player.profileId!: player.name,
        player.name: player.name,
        for (final individual in player.individuals)
          individual.profileId ?? individual.name: individual.name,
      },
    };
    final preferredPlayers = <String>{};
    String? priorityNotice;
    if (openCounts.isNotEmpty) {
      final maxOpen = openCounts.values.reduce(max);
      final minOpen = openCounts.values.reduce(min);
      if (maxOpen >= 2 && maxOpen - minOpen >= 1) {
        preferredPlayers.addAll(
          openCounts.entries
              .where((entry) => entry.value == maxOpen)
              .map((entry) => entry.key),
        );
        final preferredNames = preferredPlayers
            .map((id) => namesById[id] ?? 'Spieler')
            .toList();
        priorityNotice =
            'Priorität: ${preferredNames.join(', ')} hat noch $maxOpen offene Partien (Schnitt: $minOpen). Bevorzugt aufrufen!';
      }
    }

    final matchesContent = matches.isEmpty
        ? const Center(
            child: Text(
              'Keine offenen Partien in dieser Etappe.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        : Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < matches.take(8).length; i++)
                _buildMatchTile(
                  context,
                  matches[i],
                  isPreferred:
                      preferredPlayers.contains(
                        matches[i].homePlayer?.profileId ??
                            matches[i].homePlayer?.name,
                      ) ||
                      preferredPlayers.contains(
                        matches[i].awayPlayer?.profileId ??
                            matches[i].awayPlayer?.name,
                      ),
                ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.sports_esports,
              size: 20,
              color: Color(0xFF70E0BA),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Aktuelle & nächste Begegnungen (${t.boardCount} Boards)',
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
        if (priorityNotice != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF3E2D12),
              border: Border.all(color: Colors.amber.shade700),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.priority_high, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    priorityNotice,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (expand)
          Expanded(child: SingleChildScrollView(child: matchesContent))
        else
          matchesContent,
      ],
    );
  }

  Widget _buildMatchTile(
    BuildContext context,
    GroupMatch match, {
    required bool isPreferred,
  }) {
    final isRunning = match.boardNumber != null;

    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 340),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF14202B),
        border: Border.all(
          color: isPreferred
              ? Colors.amber
              : isRunning
              ? const Color(0xFF70E0BA)
              : const Color(0xFF263D52),
          width: isPreferred || isRunning ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isRunning ? const Color(0xFF144D34) : Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isRunning
                      ? 'Board ${match.boardNumber} (Läuft)'
                      : 'Nächste Partie',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isRunning ? const Color(0xFF86EFAC) : Colors.white70,
                  ),
                ),
              ),
              if (match.label != null && match.label!.isNotEmpty)
                Text(
                  match.label!,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              if (isPreferred)
                const Wrap(
                  spacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.priority_high, color: Colors.amber, size: 18),
                    Text(
                      'Bevorzugt',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${match.homePlayer?.name ?? "Offen"} vs. ${match.awayPlayer?.name ?? "Offen"}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
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
    final recent = playedMatches.reversed.take(6).toList();

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
                    final recentContent = recent.isEmpty
                        ? const Center(
                            child: Text(
                              'Noch keine beendeten Partien vorhanden.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final match in recent) ...[
                                _buildRecentMatchRow(
                                  context,
                                  match,
                                  _changesForMatch(t, match, snapshot.data),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          );
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (snapshot.hasError)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Ranglistenänderungen konnten nicht geladen werden.',
                                style: TextStyle(color: Colors.amber),
                              ),
                            ),
                          recentContent,
                        ],
                      ),
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
    GroupMatch m,
    List<TournamentMatchEloChange> eloChanges,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14202B),
        border: Border.all(color: const Color(0xFF263D52)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${m.homePlayer?.name ?? "?"} – ${m.awayPlayer?.name ?? "?"}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A2E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${m.homeScore ?? 0} : ${m.awayScore ?? 0}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF86EFAC),
                    fontSize: 13,
                  ),
                ),
              ),
              for (final change in eloChanges)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14202B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF263D52)),
                  ),
                  child: Text(
                    '${change.rankingName}: ${change.homeDelta == null ? '–' : _signedDelta(change.homeDelta!)} / ${change.awayDelta == null ? '–' : _signedDelta(change.awayDelta!)} Elo',
                    style: const TextStyle(
                      color: Color(0xFF70E0BA),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _signedDelta(int delta) => delta > 0 ? '+$delta' : '$delta';

  // ------------------------------------------
  // SLIDE 4 HELPER: Etappenfortschritt & Bestleistungen
  // ------------------------------------------
  Widget _buildProgressAndBestPerformancesPanel({
    required BuildContext context,
    required CreatedTournament t,
    required TimingSnapshot timing,
    required int progressPercent,
    required List<GroupMatch> playedMatches,
    required int totalMatches,
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

    final breakdownContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Fortschritt nach Etappen · $progressPercent% Gesamt',
          style: const TextStyle(
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
                  ),
                  _buildHighlightItem(
                    '180er',
                    '${oneEighties.length}x geworfen',
                  ),
                  _buildHighlightItem(
                    'High Finish',
                    highFinishes.isNotEmpty
                        ? '${highFinishes.map((p) => p.value ?? 100).reduce(max)} Punkte'
                        : '–',
                  ),
                  _buildHighlightItem(
                    'Bestes Shortleg',
                    shortLegs.isNotEmpty
                        ? '${shortLegs.map((p) => p.value ?? 18).reduce(min)} Darts'
                        : '–',
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
        // Overall timing
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Icon(Icons.timer, size: 20, color: Color(0xFF70E0BA)),
                Text(
                  'Turnieruhr: ${_formatDuration(timing.elapsed)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stages breakdown
        if (expand)
          Expanded(child: SingleChildScrollView(child: breakdownContent))
        else
          breakdownContent,
      ],
    );
  }

  List<Widget> _buildStageProgressItems(TournamentRunStage stage, int index) {
    final sections = stage is GroupTournamentRunStage && stage.groups.length > 1
        ? [
            for (final group in stage.groups)
              (
                label: '${index + 1}. ${stage.name} · ${group.name}',
                matches: group.matches,
              ),
          ]
        : [(label: '${index + 1}. ${stage.name}', matches: _matchesOf(stage))];

    return [
      for (final section in sections)
        Builder(
          builder: (context) {
            final matches = section.matches
                .where((match) => match.hasPlayers)
                .toList();
            final played = matches.where((match) => match.hasResult).length;
            final total = matches.length;
            final percent = total > 0 ? ((played / total) * 100).round() : 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF14202B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        section.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '$played von $total Spielen',
                        style: const TextStyle(
                          color: Color(0xFF70E0BA),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
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
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF70E0BA),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          color: Color(0xFF70E0BA),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
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

  Widget _buildHighlightItem(String label, String value) {
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
      ],
    );
  }

  List<PlayerStanding> _calculateGroupStandings(
    TournamentGroup group,
    List<String> tieBreakers,
  ) {
    final standings = {
      for (final player in group.players) player.name: PlayerStanding(player),
    };

    for (final match in group.matches.where(
      (m) => m.hasResult && !m.isDecider,
    )) {
      final homePlayer = match.homePlayer;
      final awayPlayer = match.awayPlayer;
      if (homePlayer == null || awayPlayer == null) continue;
      final home = standings[homePlayer.name];
      final away = standings[awayPlayer.name];
      if (home == null || away == null) continue;
      final homeLegs = match.homeLegs ?? 0;
      final awayLegs = match.awayLegs ?? 0;

      home.played++;
      home.legsFor += homeLegs;
      home.legsAgainst += awayLegs;
      away.played++;
      away.legsFor += awayLegs;
      away.legsAgainst += homeLegs;

      if (match.winner == homePlayer) {
        home.wins++;
        home.points += 3;
        away.losses++;
      } else if (match.winner == awayPlayer) {
        away.wins++;
        away.points += 3;
        home.losses++;
      } else {
        home.draws++;
        home.points++;
        away.draws++;
        away.points++;
      }
    }

    final sorted = standings.values.toList();
    sorted.sort((a, b) {
      for (final rule in tieBreakers) {
        final cmp = switch (rule) {
          'points' => b.points.compareTo(a.points),
          'legDifference' => b.legDifference.compareTo(a.legDifference),
          'legsFor' => b.legsFor.compareTo(a.legsFor),
          _ => 0,
        };
        if (cmp != 0) return cmp;
      }
      return a.player.name.compareTo(b.player.name);
    });
    return sorted;
  }
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
