import 'dart:math';

import 'engines/board_scheduling_engine.dart';
import 'engines/tournament_engine.dart';
import 'tournament_models.dart';

/// Estimates a flexible round-robin order with equally long matches.
/// Board capacity and each group's player availability both limit throughput.
/// Knockout rounds remain sequential because they depend on prior results.
class PlanningDuration {
  const PlanningDuration({
    required this.groupSlots,
    required this.knockoutSlots,
    required this.matchMinutes,
    this.boardIdleMinutes = 0,
    this.groupIdleUnits = 0,
    this.knockoutIdleUnits = 0,
    num? knockoutMatchMinutes,
  }) : knockoutMatchMinutes = knockoutMatchMinutes ?? matchMinutes;
  final int groupSlots;
  final int knockoutSlots;
  final num boardIdleMinutes;
  final num groupIdleUnits;
  final num knockoutIdleUnits;
  final num matchMinutes;
  final num knockoutMatchMinutes;
  // Avoid rounding floating-point residues above whole minutes up again.
  int get groupMinutes =>
      (groupSlots * matchMinutes + groupIdleUnits * boardIdleMinutes - 1e-9)
          .ceil();
  int get knockoutMinutes =>
      (knockoutSlots * knockoutMatchMinutes +
              knockoutIdleUnits * boardIdleMinutes -
              1e-9)
          .ceil();
  int get totalMinutes => groupMinutes + knockoutMinutes;

  static double estimatedLegs(int bestOfLegs) {
    if (bestOfLegs < 1) {
      throw ArgumentError.value(bestOfLegs, 'bestOfLegs');
    }
    final minimum = bestOfLegs ~/ 2 + 1;
    return (minimum + bestOfLegs) / 2;
  }

  static double estimatedMatchLegs(TournamentGameFormat format) =>
      estimatedLegs(format.bestOfLegs) * estimatedLegs(format.bestOfSets);

  factory PlanningDuration.calculate({
    required List<int> groupSizes,
    required int qualifiers,
    required int boards,
    required num matchMinutes,
    num boardIdleMinutes = 0,
    num? knockoutMatchMinutes,
  }) {
    if (boards < 1 ||
        matchMinutes < 1 ||
        (knockoutMatchMinutes ?? matchMinutes) < 1) {
      throw ArgumentError('Positive boards and match duration required');
    }
    final groupEntries = <PlayEntry>[];
    for (var group = 0; group < groupSizes.length; group++) {
      final players = [
        for (var player = 0; player < groupSizes[group]; player++)
          TournamentPlayer(name: 'G$group-P$player', isGenerated: true),
      ];
      for (final match in tournamentEngine.buildRoundRobinMatches(players)) {
        groupEntries.add(PlayEntry(match, 0, 'G$group'));
      }
    }
    final assignments = const BoardSchedulingEngine().schedule(
      all: groupEntries,
      ready: groupEntries,
      boardCount: boards,
    );
    final groupSlots = assignments.isEmpty ? 0 : assignments.last.block + 1;
    final assignmentsPerBlock = <int, int>{};
    for (final assignment in assignments) {
      assignmentsPerBlock.update(
        assignment.block,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final groupIdleUnits = assignmentsPerBlock.values.fold<int>(
      0,
      (idle, assigned) => idle + max(0, boards - assigned),
    );
    var knockoutSlots = 0;
    var knockoutIdleUnits = 0.0;
    if (qualifiers > 1) {
      var bracket = 1;
      while (bracket < qualifiers) {
        bracket *= 2;
      }
      // Only actual first-round matches count; byes need no board time.
      final firstRoundMatches = qualifiers - bracket ~/ 2;
      knockoutSlots += _knockoutRoundSlots(firstRoundMatches, boards);
      knockoutIdleUnits += _idleBoardSlots(firstRoundMatches, boards);
      for (var matches = bracket ~/ 4; matches >= 1; matches ~/= 2) {
        knockoutSlots += _knockoutRoundSlots(matches, boards);
        knockoutIdleUnits += _idleBoardSlots(matches, boards);
      }
    }
    return PlanningDuration(
      groupSlots: groupSlots,
      knockoutSlots: knockoutSlots,
      matchMinutes: matchMinutes,
      boardIdleMinutes: boardIdleMinutes,
      groupIdleUnits: groupIdleUnits,
      knockoutIdleUnits: knockoutIdleUnits,
      knockoutMatchMinutes: knockoutMatchMinutes,
    );
  }
}

int _knockoutRoundSlots(int matches, int boards) {
  final entries = [
    for (var index = 0; index < matches; index++)
      PlayEntry(
        GroupMatch(
          homePlayer: TournamentPlayer.generated(index * 2 + 1),
          awayPlayer: TournamentPlayer.generated(index * 2 + 2),
          round: 1,
        ),
        0,
        'KO',
      ),
  ];
  final schedule = const BoardSchedulingEngine().schedule(
    all: entries,
    ready: entries,
    boardCount: boards,
  );
  return schedule.isEmpty ? 0 : schedule.last.block + 1;
}

int _idleBoardSlots(int matches, int boards) =>
    matches <= 0 ? 0 : _knockoutRoundSlots(matches, boards) * boards - matches;
