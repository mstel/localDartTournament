import 'dart:convert';

import '../domain/engines/group_standings_engine.dart';
import '../domain/tournament_models.dart';

/// Verwaltet die persistierte Bestätigung für das Ende einer Gruppenphase.
///
/// Der zweite Bildschirm läuft als eigener Prozess und liest das Turnier
/// periodisch von der Festplatte. Deshalb wird die Bestätigung direkt im
/// Turnier gespeichert und `updatedAt` erhöht, damit beide Fenster denselben
/// Freigabestand sehen. Der Fingerabdruck der Ergebnisse sorgt dafür, dass die
/// Anzeige nach einer Korrektur erneut erscheint.
class GroupEndReviewService {
  const GroupEndReviewService();

  /// Stabiler Schlüssel für den Freigabestand einer Gruppenphase.
  static String key(int stageIndex, GroupTournamentRunStage stage) =>
      'stage:$stageIndex|${fingerprint(stage)}';

  /// Fingerabdruck der Ergebnislage einer Gruppenphase.
  static String fingerprint(GroupTournamentRunStage stage) {
    final matches = stage.groups.expand((group) => group.matches).toList();
    return jsonEncode([
      for (final match in matches)
        [
          match.round,
          match.label,
          match.homePlayer?.profileId ?? match.homePlayer?.name,
          match.awayPlayer?.profileId ?? match.awayPlayer?.name,
          match.homeLegs,
          match.awayLegs,
          match.isAnnulled,
          match.isDecider,
        ],
    ]);
  }

  /// Ob in der Gruppenphase tatsächlich etwas zu prüfen ist: ein Vergleich um
  /// Zusatzplätze oder ein ungeklärter Gleichstand in den Abschlusstabellen.
  /// Ohne Gleichstand und ohne Vergleich ist kein Pflicht-Dialog nötig.
  static bool hasTieOrComparison(
    CreatedTournament tournament,
    GroupTournamentRunStage stage,
  ) {
    final plan = stage.qualificationPlan;
    if (plan != null && plan.extraCount > 0) return true;
    if (stage.tieBreakers.isEmpty) return false;

    const engine = GroupStandingsEngine();
    for (final group in stage.groups) {
      final standings = engine.calculate(
        group,
        stage.tieBreakers,
        tournament: tournament,
      );
      for (var index = 0; index + 1 < standings.length; index++) {
        if (engine.compare(
              standings[index],
              standings[index + 1],
              stage.tieBreakers,
              matches: group.matches,
            ) ==
            0) {
          return true;
        }
      }
    }
    return false;
  }

  static bool isAcknowledged(
    CreatedTournament tournament,
    int stageIndex,
    GroupTournamentRunStage stage,
  ) => tournament.acknowledgedGroupEndReviews.contains(key(stageIndex, stage));

  /// Markiert die Gruppenphase als geprüft. Schreibt nichts, wenn die Phase
  /// bereits bestätigt wurde.
  static void acknowledge(
    CreatedTournament tournament,
    int stageIndex,
    GroupTournamentRunStage stage,
  ) {
    tournament.acknowledgedGroupEndReviews.add(key(stageIndex, stage));
  }
}
