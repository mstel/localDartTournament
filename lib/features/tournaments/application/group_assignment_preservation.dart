import '../domain/tournament_models.dart';

/// Behält eine bereits vorgenommene manuelle Gruppenzuordnung beim Bearbeiten
/// anderer Turniereinstellungen bei.
///
/// Eine noch ausstehende manuelle Zuordnung wird bewusst nicht aus den
/// vorläufig alphabetisch sortierten Laufgruppen nachgezogen: Solange der
/// Modus „manuell zuweisen“ nicht verlassen wird, bleibt der
/// Zweitmonitor-Hinweis bestehen. Wird die Zuweisungsmethode geändert, gilt
/// ebenfalls die neue Einstellung statt der alten Zuordnung.
List<TournamentStage> preserveExistingGroupAssignment({
  required CreatedTournament? existing,
  required List<TournamentStage> stages,
  required List<TournamentPlayer> players,
}) {
  if (existing == null ||
      stages.isEmpty ||
      !stages.first.isGroupStage ||
      existing.stages.isEmpty ||
      !existing.stages.first.isGroupStage ||
      existing.runStages.isEmpty ||
      existing.runStages.first is! GroupTournamentRunStage) {
    return stages;
  }

  final previousStage = existing.stages.first;
  final nextStage = stages.first;
  if (previousStage.groupAssignmentMode != nextStage.groupAssignmentMode ||
      previousStage.hasPendingManualGroupAssignment) {
    return stages;
  }

  final oldStage = existing.runStages.first as GroupTournamentRunStage;
  final ordered = oldStage.groups.expand((group) => group.players).toList();
  String identity(TournamentPlayer player) =>
      player.profileId ?? player.name.trim().toLowerCase();
  final currentByIdentity = {
    for (final player in players) identity(player): player,
  };
  final preserved = <TournamentPlayer>[];
  final seen = <String>{};
  for (final player in ordered) {
    final key = identity(player);
    final current = currentByIdentity[key];
    if (current != null && seen.add(key)) preserved.add(current);
  }
  final slotsNeeded = nextStage.groupSizes.fold<int>(
    0,
    (sum, size) => sum + size,
  );
  for (final player in players) {
    if (preserved.length >= slotsNeeded) break;
    if (seen.add(identity(player))) preserved.add(player);
  }
  if (preserved.length != slotsNeeded) return stages;
  final slotOrder = preserved
      .map((player) => players.indexOf(player) + 1)
      .toList();
  if (slotOrder.any((slot) => slot < 1) ||
      slotOrder.toSet().length != slotOrder.length) {
    return stages;
  }
  final firstStage = nextStage.copyWith(
    groupDrawOnStart: false,
    groupSlotOrder: List<int?>.unmodifiable(slotOrder),
  );
  return [firstStage, ...stages.skip(1)];
}
