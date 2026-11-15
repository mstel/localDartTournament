import '../domain/tournament_models.dart';

abstract interface class TournamentSimulationRuntime {
  TournamentRunStage build(
    TournamentStage stage,
    List<TournamentPlayer> players,
  );

  void activate(int index);

  void advance({DateTime? now});

  bool hasOpen(TournamentRunStage stage);

  List<TournamentPlayer> qualifiers(TournamentRunStage stage);

  List<GroupMatch> matches(TournamentRunStage stage);
}
