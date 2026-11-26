import 'dart:math';

import '../domain/engines/tournament_engine.dart';
import '../domain/tournament_models.dart';

/// Passt geplante Folge-Phasen an eine geänderte Anzahl Weiterkommender an.
///
/// Beim Bearbeiten einer bereits laufenden Phase dürfen die Ergebnisse der
/// aktuellen Phase nicht angefasst werden. Die Planung der Phasen danach muss
/// aber genauso nachgezogen werden wie beim „Bestehendes Turnier
/// aktualisieren“-Dialog: eine KO-Phase erhält die neue Teilnehmerzahl, das
/// passende Bracket und die zulässigen Platzierungsspiele.
class RunningRulesPropagation {
  const RunningRulesPropagation({this.engine = const TournamentEngine()});

  final TournamentEngine engine;

  bool isKnockoutStageType(String type) =>
      type == 'single_knockout' ||
      type == 'double_knockout' ||
      type == 'triple_knockout' ||
      type == 'kratzer';

  TournamentStage adaptStage(
    TournamentStage stage, {
    required int incomingPlayers,
  }) {
    if (isKnockoutStageType(stage.type)) {
      return _adaptKnockoutStage(stage, incomingPlayers: incomingPlayers);
    }
    if (stage.isGroupStage && stage.qualifiedParticipantCount != null) {
      final adaptedCount = min(
        stage.qualifiedParticipantCount!,
        max(0, incomingPlayers),
      );
      if (adaptedCount != stage.qualifiedParticipantCount) {
        return stage.copyWith(qualifiedParticipantCount: adaptedCount);
      }
    }
    return stage;
  }

  TournamentStage _adaptKnockoutStage(
    TournamentStage stage, {
    required int incomingPlayers,
  }) {
    final participantCount = max(0, incomingPlayers);
    final bracketSize = engine.nextPowerOfTwo(max(1, participantCount));
    final slotOrder = stage.knockoutSlotOrder.length == bracketSize
        ? stage.knockoutSlotOrder
        : [
            for (final seed in engine.seedOrderForSize(bracketSize))
              seed <= participantCount ? seed : null,
          ];

    var advancingCount = stage.knockoutAdvancingCount;
    if (advancingCount != null) {
      if (advancingCount >= participantCount) {
        advancingCount = participantCount >= 5 ? participantCount - 1 : null;
      } else if (advancingCount < 4) {
        advancingCount = null;
      }
    }

    return stage.withKnockoutPlan(
      participantCount: participantCount,
      bracketSize: bracketSize,
      byeCount: bracketSize - participantCount,
      slotOrder: slotOrder,
      seedingMode: stage.knockoutSeedingMode,
      advancingCount: advancingCount,
      placementPlaces: stage.placementPlaces
          .where((place) => place < participantCount)
          .toList(),
    );
  }
}
