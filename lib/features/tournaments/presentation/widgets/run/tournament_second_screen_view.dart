import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/engines/group_standings_engine.dart';
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
    this.showStandings = true,
    this.onClose,
  });

  final CreatedTournament tournament;
  final bool isStandaloneWindow;
  final bool showStandings;
  final VoidCallback? onClose;

  @override
  State<TournamentSecondScreenView> createState() =>
      _TournamentSecondScreenViewState();
}

class _TournamentSecondScreenViewState
    extends State<TournamentSecondScreenView> {
  bool _showNextStagePreview = false;
  bool _showForecast = false;
  late Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges;
  late String _eloInputFingerprint;
  Future<Map<String, AdvancementChance>>? _advancementForecast;
  late String _forecastFingerprint;

  @override
  void initState() {
    super.initState();
    _refreshEloChanges();
    _refreshAdvancementForecast();
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
    final stages = widget.tournament.runStages;
    if (stages.isEmpty) return Future.value(const {});
    final activeIndex = widget.tournament.activeStageIndex.clamp(
      0,
      stages.length - 1,
    );
    if (_nextKnockoutStage(widget.tournament, activeIndex, stage) == null) {
      return _advancementForecast = Future.value(const {});
    }
    return _advancementForecast = GroupAdvancementForecastService().calculate(
      tournament: widget.tournament,
      stage: stage,
    );
  }

  void _refreshEloChanges({String? fingerprint}) {
    _eloInputFingerprint =
        fingerprint ?? jsonEncode(widget.tournament.toJson());
    _eloChanges = TournamentMatchEloService().calculate(widget.tournament);
  }

  @override
  void dispose() {
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
        color: const Color(0xFF0D1318),
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
              Text(
                '${t.name} · ${activeStage?.name ?? "Turnier"}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
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
    required int progressPercent,
    required List<GroupMatch> playedMatches,
    required int totalMatches,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1000 && constraints.maxHeight >= 620;
        if (!widget.showStandings) {
          if (wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    progressPercent: progressPercent,
                    playedMatches: playedMatches,
                    totalMatches: totalMatches,
                    expand: true,
                  ),
                ),
              ],
            );
          }
        }
        if (wide) {
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
                        progressPercent: progressPercent,
                        playedMatches: playedMatches,
                        totalMatches: totalMatches,
                        expand: true,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showStandings) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: _buildStandingsForecastPanel(
                    context,
                    t,
                    activeIndex,
                    activeStage,
                    expand: true,
                  ),
                ),
              ],
            ],
          );
        }

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
                progressPercent: progressPercent,
                playedMatches: playedMatches,
                totalMatches: totalMatches,
                expand: false,
              ),
              if (widget.showStandings) ...[
                const SizedBox(height: 16),
                _buildCompactStandingsForecastControl(
                  context,
                  t,
                  activeIndex,
                  activeStage,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactStandingsForecastControl(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? activeStage,
  ) {
    return _buildStandingsForecastPanel(
      context,
      t,
      activeIndex,
      activeStage,
      expand: false,
    );
  }

  Widget _buildStandingsForecastPanel(
    BuildContext context,
    CreatedTournament t,
    int activeIndex,
    TournamentRunStage? activeStage, {
    required bool expand,
  }) {
    final content = _showForecast
        ? _buildKoPrognosisPanel(
            context,
            t,
            activeIndex,
            activeStage,
            expand: false,
          )
        : _buildStandingsAndPreviewControl(
            context,
            t,
            activeIndex,
            activeStage,
            expand: false,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _viewModeButton(
                    label: 'Tabellen & Zwischenstände',
                    value: false,
                    icon: Icons.leaderboard_outlined,
                  ),
                  const SizedBox(height: 4),
                  _viewModeButton(
                    label: 'Siegprognose & Weiterkommen',
                    value: true,
                    icon: Icons.account_tree_outlined,
                  ),
                ],
              );
            }
            return SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Tabellen & Zwischenstände'),
                  icon: Icon(Icons.leaderboard_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Siegprognose & Weiterkommen'),
                  icon: Icon(Icons.account_tree_outlined),
                ),
              ],
              selected: {_showForecast},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  setState(() => _showForecast = selection.first);
                }
              },
            );
          },
        ),
        const SizedBox(height: 8),
        if (expand)
          Expanded(child: SingleChildScrollView(child: content))
        else
          content,
      ],
    );
  }

  Widget _viewModeButton({
    required String label,
    required bool value,
    required IconData icon,
  }) {
    final selected = _showForecast == value;
    final onPressed = selected
        ? null
        : () => setState(() => _showForecast = value);
    if (selected) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expand)
          Expanded(child: SingleChildScrollView(child: standings))
        else
          standings,
        if (hasNextKnockout) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => setState(() => _showNextStagePreview = true),
            icon: const Icon(Icons.account_tree_outlined),
            label: const Text('Vorschau für die nächste Etappe'),
          ),
        ],
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
    final advancingPlayers = groupStage == null
        ? const <int, TournamentPlayer>{}
        : _currentAdvancerByInputIndex(groupStage);
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
        final advancing = playerIndex < 0
            ? null
            : advancingPlayers[playerIndex];
        if (advancing != null) {
          return '${advancing.name}\nAktuell weiter · Setzplatz vorläufig';
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
            fontSize: 20,
          ),
        ),
        if (advancingPlayers.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Die aktuell weiterkommenden Spieler sind vorläufig in die Plätze eingetragen. Gleichstände werden nach den aktiven Tie-Break-Regeln sortiert.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        if (advancingPlayers.isNotEmpty && !canShowSeedPositions)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final player in advancingPlayers.values)
                  Chip(label: Text('${player.name} · aktuell weiter')),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: stage.rounds.isEmpty
              ? const Center(
                  child: Text(
                    'Für diese Etappe ist noch kein Turnierbaum vorhanden.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          var roundIndex = 0;
                          roundIndex < stage.rounds.length;
                          roundIndex++
                        )
                          Container(
                            width: 280,
                            margin: const EdgeInsets.only(right: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    knockoutRoundName(
                                      roundIndex,
                                      stage.rounds.length,
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFF70E0BA),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                for (
                                  var matchIndex = 0;
                                  matchIndex < stage.rounds[roundIndex].length;
                                  matchIndex++
                                )
                                  _buildBracketMatchPreview(
                                    stage.rounds[roundIndex][matchIndex],
                                    homeLabel: playerLabel(
                                      stage
                                          .rounds[roundIndex][matchIndex]
                                          .homePlayer,
                                      roundIndex,
                                    ),
                                    awayLabel: playerLabel(
                                      stage
                                          .rounds[roundIndex][matchIndex]
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
                ),
        ),
      ],
    );
  }

  Map<int, TournamentPlayer> _currentAdvancerByInputIndex(
    GroupTournamentRunStage stage,
  ) {
    final plan = stage.qualificationPlan;
    if (plan == null) return const {};

    final advancingPlayers = <int, TournamentPlayer>{};
    final extraCandidates = <({int groupIndex, PlayerStanding standing})>[];
    var inputIndex = 0;
    for (var groupIndex = 0; groupIndex < stage.groups.length; groupIndex++) {
      final group = stage.groups[groupIndex];
      final standings = const GroupStandingsEngine().calculate(
        group,
        stage.tieBreakers,
      );
      final fixedPlaces = groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      for (var rank = 0; rank < min(fixedPlaces, standings.length); rank++) {
        advancingPlayers[inputIndex + rank] = standings[rank].player;
      }
      if (plan.extraCount > 0 && plan.extraGroups.contains(groupIndex + 1)) {
        final rankIndex = plan.extraRank - 1;
        if (rankIndex >= 0 && rankIndex < standings.length) {
          extraCandidates.add((
            groupIndex: groupIndex,
            standing: standings[rankIndex],
          ));
        }
      }
      inputIndex += fixedPlaces;
    }
    extraCandidates.sort((a, b) {
      final comparison = _compareStandings(
        a.standing,
        b.standing,
        stage.tieBreakers,
      );
      return comparison != 0
          ? comparison
          : a.groupIndex.compareTo(b.groupIndex);
    });
    for (
      var index = 0;
      index < min(plan.extraCount, extraCandidates.length);
      index++
    ) {
      advancingPlayers[inputIndex + index] =
          extraCandidates[index].standing.player;
    }
    return advancingPlayers;
  }

  int _compareStandings(
    PlayerStanding a,
    PlayerStanding b,
    List<String> tieBreakers,
  ) {
    for (final rule in tieBreakers) {
      final comparison = switch (rule) {
        'points' => b.points.compareTo(a.points),
        'legDifference' => b.legDifference.compareTo(a.legDifference),
        'legsFor' => b.legsFor.compareTo(a.legsFor),
        _ => 0,
      };
      if (comparison != 0) return comparison;
    }
    return a.player.name.compareTo(b.player.name);
  }

  Widget _buildBracketMatchPreview(
    GroupMatch match, {
    required String homeLabel,
    required String awayLabel,
    required int matchNumber,
  }) {
    final homeIsCertain = homeLabel.contains('Aktuell weiter');
    final awayIsCertain = awayLabel.contains('Aktuell weiter');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
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
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 6),
          _buildBracketParticipant(homeLabel, isCertain: homeIsCertain),
          const Divider(color: Color(0xFF263D52), height: 12),
          _buildBracketParticipant(awayLabel, isCertain: awayIsCertain),
        ],
      ),
    );
  }

  Widget _buildBracketParticipant(String label, {required bool isCertain}) {
    return Row(
      children: [
        if (isCertain) ...[
          const Icon(Icons.check_circle, color: Color(0xFF86EFAC), size: 18),
          const SizedBox(width: 6),
        ],
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
    final standings = const GroupStandingsEngine().calculate(
      group,
      tieBreakers,
    );
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
                      ? 'Siegprognose & Weiterkommen'
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
                ? 'Elo und historische Siegquoten simulieren die verbleibenden Gruppenspiele.'
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
                  final standings = const GroupStandingsEngine().calculate(
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
                              final currentlyAdvancing = rank < fixedPlaces;
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
                                        color: currentlyAdvancing
                                            ? const Color(0xFF86EFAC)
                                            : Colors.white70,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        standing.player.name,
                                        style: TextStyle(
                                          fontWeight: currentlyAdvancing
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
                                          'Siegchance: ${chance.groupWinProbability.toStringAsFixed(1)} %\nWeiterkommen: ${chance.advancementProbability.toStringAsFixed(1)} %',
                                      child: Text(
                                        '${chance.groupWinProbability.toStringAsFixed(1)} % Sieg · '
                                        '${chance.advancementProbability.toStringAsFixed(1)} % weiter',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: currentlyAdvancing
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
      for (final player in t.players)
        for (final individual in player.individuals)
          individual.profileId ?? individual.name: individual.name,
    };
    final preferredPlayers = <String>{};
    String? priorityNotice;
    if (openCounts.isNotEmpty) {
      final maxOpen = openCounts.values.reduce(max);
      final minOpen = openCounts.values.reduce(min);
      if (maxOpen >= 2 && maxOpen - minOpen >= 2) {
        preferredPlayers.addAll(
          openCounts.entries
              .where((entry) => entry.value == maxOpen)
              .map((entry) => entry.key),
        );
        final preferredNames = preferredPlayers
            .map((id) => namesById[id] ?? 'Spieler')
            .toList();
        priorityNotice =
            'Vorrang: ${preferredNames.join(', ')} hat mindestens zwei offene Partien mehr als andere Spieler ($maxOpen gegenüber $minOpen).';
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
              for (var i = 0; i < matches.take(6).length; i++)
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
              color: const Color(0xFF28251B),
              border: Border.all(color: const Color(0xFF786A45)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xFFD6C28C),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    priorityNotice,
                    style: const TextStyle(
                      color: Color(0xFFE8D9AC),
                      fontWeight: FontWeight.w600,
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
              ? const Color(0xFFB39A5A)
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
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFFD6C28C),
                      size: 18,
                    ),
                    Text(
                      'Bevorzugt',
                      style: TextStyle(
                        color: Color(0xFFE8D9AC),
                        fontWeight: FontWeight.w500,
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
    final recent = playedMatches.toList()
      ..sort(
        (a, b) => (b.finishedAt ?? DateTime(1970)).compareTo(
          a.finishedAt ?? DateTime(1970),
        ),
      );
    final latestMatches = recent.take(2).toList();

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
                    final recentContent = latestMatches.isEmpty
                        ? const Center(
                            child: Text(
                              'Noch keine beendeten Partien vorhanden.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final match in latestMatches) ...[
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
    String holderNames(Iterable<BestPerformance> performances) {
      final names = performances
          .map((performance) => performance.playerName.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      if (names.length <= 3) return names.join(', ');
      return '${names.take(3).join(', ')} +${names.length - 3}';
    }

    final topFinish = highFinishes.isEmpty
        ? null
        : highFinishes.map((p) => p.value ?? 100).reduce(max);
    final finishHolders = topFinish == null
        ? ''
        : holderNames(highFinishes.where((p) => (p.value ?? 100) == topFinish));
    final bestShortleg = shortLegs.isEmpty
        ? null
        : shortLegs.map((p) => p.value ?? 18).reduce(min);
    final shortlegHolders = bestShortleg == null
        ? ''
        : holderNames(shortLegs.where((p) => (p.value ?? 18) == bestShortleg));

    final breakdownContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fortschritt nach Etappen:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < t.runStages.length; i++)
          Builder(
            builder: (context) {
              final stage = t.runStages[i];
              final sMatches = _matchesOf(
                stage,
              ).where((m) => m.hasPlayers).toList();
              final sPlayed = sMatches.where((m) => m.hasResult).length;
              final sTotal = sMatches.length;
              final sPct = sTotal > 0 ? ((sPlayed / sTotal) * 100).round() : 0;

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
                          '${i + 1}. ${stage.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '$sPlayed von $sTotal Spielen ($sPct%)',
                          style: const TextStyle(
                            color: Color(0xFF70E0BA),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: sTotal > 0
                            ? (sPlayed / sTotal).clamp(0.0, 1.0)
                            : 0.0,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF70E0BA),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

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
                    '${oneSeventies.length}x geworfen${holderNames(oneSeventies).isEmpty ? '' : ' · ${holderNames(oneSeventies)}'}',
                  ),
                  _buildHighlightItem(
                    '180er',
                    '${oneEighties.length}x geworfen${holderNames(oneEighties).isEmpty ? '' : ' · ${holderNames(oneEighties)}'}',
                  ),
                  _buildHighlightItem(
                    'High Finish',
                    topFinish != null
                        ? '$topFinish Punkte${finishHolders.isEmpty ? '' : ' · $finishHolders'}'
                        : '–',
                  ),
                  _buildHighlightItem(
                    'Bestes Shortleg',
                    bestShortleg != null
                        ? '$bestShortleg Darts${shortlegHolders.isEmpty ? '' : ' · $shortlegHolders'}'
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
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$progressPercent% Gesamt',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Color(0xFF70E0BA),
            ),
          ),
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

  Widget _buildHighlightItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF70E0BA),
            ),
          ),
        ),
      ],
    );
  }
}
