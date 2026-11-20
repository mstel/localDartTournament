import '../../../../domain/tournament_models.dart';

/// Einheitliche Beschriftung der gewählten K.-o.-Auslosungsmethode.
String knockoutSeedingModeLabel(String mode) => switch (mode) {
  'random_cross' => 'Gruppenplatzierung - Zufällige Kreuzpaarungen',
  'elo' => 'Leistungsbasierte Setzliste (ELO)',
  'manual' => 'Manuelle Paarungszuordnung',
  'random' => 'Zufallsauslosung beim Turnierstart',
  _ => 'Gruppenplatzierung - Feste Kreuzpaarungen',
};

/// Beschriftung der Auslosungsmethode der Planungsphase, die zu [stage] gehört.
///
/// Der Laufzeit-Stage selbst enthält die Auslosungsmethode nicht; sie liegt in
/// [CreatedTournament.stages]. Die Zuordnung erfolgt über die Position in
/// [CreatedTournament.runStages] und als Rückfall über den Phasennamen.
String? knockoutSeedingModeLabelForStage(
  CreatedTournament? tournament,
  TournamentRunStage stage,
) {
  if (tournament == null) return null;

  final runIndex = tournament.runStages.indexOf(stage);
  TournamentStage? planningStage;
  if (runIndex >= 0 && runIndex < tournament.stages.length) {
    planningStage = tournament.stages[runIndex];
  } else {
    for (final candidate in tournament.stages) {
      if (candidate.name == stage.name) {
        planningStage = candidate;
        break;
      }
    }
  }

  if (planningStage == null) return null;
  return knockoutSeedingModeLabel(planningStage.knockoutSeedingMode);
}
