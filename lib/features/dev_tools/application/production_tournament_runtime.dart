part of '../../../tournament_workspace.dart';

/// Transitional bridge to the production methods still owned by the workspace.
/// No widget is mounted, no UI callbacks, storage or account operations run.
/// Remove this bridge when those methods become an independent runtime library.
class ProductionTournamentRuntime {
  ProductionTournamentRuntime(CreatedTournament tournament)
    : _state = _SimulationRunState(tournament);
  final _SimulationRunState _state;
  TournamentRunStage build(
    TournamentStage stage,
    List<TournamentPlayer> players,
  ) => _state._buildRunStageFromPlayers(stage, players);
  void activate(int index) {
    _state._activeStageIndex = index;
  }

  void advance() {
    final index = _state._activeStageIndex;
    if (index >= 0 && index < _state.widget.tournament.runStages.length) {
      final stage = _state.widget.tournament.runStages[index];
      if (stage is KnockoutTournamentRunStage && stage.isKratzer) {
        if (stage.rounds.isNotEmpty) {
          for (final match in stage.rounds.last) {
            if (match.scratchedPlayer == null &&
                match.homeLegs != null &&
                match.awayLegs != null &&
                match.scratchEligiblePlayers.isNotEmpty) {
              match
                ..scratchedPlayer = match.scratchEligiblePlayers.first
                ..finishedAt ??= DateTime.now();
            }
          }
        }
        _state._advanceKratzerRound(stage);
      }
    }
    _state._advanceKnockoutWinners();
    _state._ensureGroupDeciders();
  }

  bool hasOpen(TournamentRunStage stage) => _state._stageHasOpenMatches(stage);
  List<TournamentPlayer> qualifiers(TournamentRunStage stage) =>
      _state._advancingPlayersFromStage(stage);
  List<PlayerStanding> standings(TournamentGroup group, List<String> rules) =>
      _state._standingsFor(group, rules);
  List<GroupMatch> matches(TournamentRunStage stage) =>
      _state._matchesForStage(stage);
  List<TournamentPlayer> ranking(
    KnockoutTournamentRunStage stage,
    List<TournamentPlayer> players,
  ) => stage.eliminationLossLimit > 1
      ? _state._multiEliminationRanking(
          stage.rounds,
          stage.eliminationLossLimit,
          fallbackPlayers: players,
          finalEndsTournament: stage.finalEndsTournament,
        )
      : _state._knockoutRanking(
          stage.rounds,
          stage.placementMatches,
          fallbackPlayers: players,
        );
}

class _SimulationRunState extends _TournamentRunPageState {
  _SimulationRunState(CreatedTournament tournament)
    : _simulationWidget = _LiveTournamentRunPage(tournament: tournament);
  final _LiveTournamentRunPage _simulationWidget;
  @override
  _LiveTournamentRunPage get widget => _simulationWidget;
}
